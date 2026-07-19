import type { InspectorResult } from "./inspector-cli.js";
import { inspectorEnvelopeSchemaVersion } from "./inspector-envelope.js";
import type { InspectorEnvelope } from "./inspector-envelope.js";

const diagnosticOutputLimit = 4096;
const diagnosticTruncationMarker = "\n...[truncated]";

export function toolResponse(result: InspectorResult) {
  const payload = responsePayload(result);
  const isError = payload.success === false;

  return {
    content: [
      {
        type: "text" as const,
        text: JSON.stringify(payload, null, 2)
      }
    ],
    structuredContent: payload,
    isError
  };
}

function responsePayload(result: InspectorResult): InspectorEnvelope {
  if (result.envelope?.success === false) {
    return {
      ...result.envelope,
      errorCode: result.envelope.errorCode ?? "cli_command_failed",
      error: result.envelope.error ?? "Astrolabe Host command failed",
      recoverySuggestion: result.envelope.recoverySuggestion
        ?? "Call list_apps first and inspect compatibility, capabilities, and recoverySuggestion"
    };
  }
  if (result.envelope && result.exitedSuccessfully && !result.error) {
    return result.envelope;
  }
  return {
    schemaVersion: inspectorEnvelopeSchemaVersion,
    success: false,
    ...(result.envelope?.command ? { command: result.envelope.command } : {}),
    errorCode: result.errorCode ?? "mcp_adapter_invalid_cli_response",
    error: result.error ?? "Failure: Astrolabe Host did not return a valid JSON envelope",
    recoverySuggestion: result.recoverySuggestion
      ?? "Ensure the Astrolabe Host executable exists and inspect stderr/stdout",
    stdout: boundedDiagnosticOutput(result.stdout),
    stderr: boundedDiagnosticOutput(result.stderr)
  };
}

function boundedDiagnosticOutput(value: string): string {
  if (value.length <= diagnosticOutputLimit) {
    return value;
  }
  return `${value.slice(0, diagnosticOutputLimit - diagnosticTruncationMarker.length)}${diagnosticTruncationMarker}`;
}
