import { spawn } from "node:child_process";
import { parseInspectorEnvelope } from "./inspector-envelope.js";
import type { InspectorEnvelope } from "./inspector-envelope.js";

export type InspectorResult = {
  /** Whether the CLI exit code is zero. */
  exitedSuccessfully: boolean;
  /** Parsed JSON output from the CLI. */
  envelope?: InspectorEnvelope;
  /** Raw standard output from the CLI. */
  stdout: string;
  /** Raw standard error from the CLI. */
  stderr: string;
  /** Error message for launch or parsing failures. */
  error?: string;

  /** Stable error code for launch, timeout, process, or response parsing failures. */
  errorCode?: string;

  /** Actionable recovery suggestion for adapter-layer failures. */
  recoverySuggestion?: string;
};

export type InspectorRunOptions = {
  /** Subprocess timeout in milliseconds. */
  timeoutMs?: number;
};

export async function runInspector(inspectorBin: string, args: string[], options: InspectorRunOptions = {}): Promise<InspectorResult> {
  return await new Promise((resolvePromise) => {
    const timeoutMs = options.timeoutMs ?? inspectorTimeoutMs(args);
    let didResolve = false;
    const child = spawn(inspectorBin, args, {
      stdio: ["ignore", "pipe", "pipe"]
    });

    let stdout = "";
    let stderr = "";

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");

    child.stdout.on("data", (chunk: string) => {
      stdout += chunk;
    });

    child.stderr.on("data", (chunk: string) => {
      stderr += chunk;
    });

    const resolveOnce = (result: InspectorResult): void => {
      if (didResolve) {
        return;
      }
      didResolve = true;
      clearTimeout(timeout);
      resolvePromise(result);
    };

    const timeout = setTimeout(() => {
      child.kill("SIGTERM");
      resolveOnce({
        exitedSuccessfully: false,
        stdout,
        stderr,
        errorCode: "mcp_adapter_cli_timeout",
        error: `Failure: Astrolabe Host timed out after ${timeoutMs}ms`,
        recoverySuggestion: "Ensure the target app and Runtime are still running, then retry the current tool"
      });
    }, timeoutMs);

    child.on("error", (error) => {
      resolveOnce({
        exitedSuccessfully: false,
        stdout,
        stderr,
        errorCode: "mcp_adapter_cli_spawn_failed",
        error: `Failure: unable to launch Astrolabe Host: ${error.message}`,
        recoverySuggestion: "Run the Astrolabe Codex installation again and check ASTROLABE_BIN"
      });
    });

    child.on("close", (code) => {
      const parsed = parseInspectorEnvelope(stdout);
      const processFailedWithoutBusinessError = code !== 0 && parsed.envelope?.success !== false;
      resolveOnce({
        exitedSuccessfully: code === 0,
        envelope: parsed.envelope,
        stdout,
        stderr,
        errorCode: parsed.errorCode ?? (processFailedWithoutBusinessError ? "mcp_adapter_cli_process_failed" : undefined),
        error: parsed.error ?? (processFailedWithoutBusinessError ? `Failure: Astrolabe Host exited with code ${code ?? "unknown"}` : undefined),
        recoverySuggestion: parsed.recoverySuggestion ?? (processFailedWithoutBusinessError
          ? "Check the Astrolabe Host installation, command arguments, and standard error output"
          : undefined)
      });
    });
  });
}

export function inspectorTimeoutMs(args: string[]): number {
  switch (args[0]) {
    case "record-baseline":
    case "compare-baseline":
    case "inspect-diff":
      return 110000;
    default:
      return 30000;
  }
}
