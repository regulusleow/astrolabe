import test from "node:test";
import assert from "node:assert/strict";
import { toolResponse } from "../dist/tool-response.js";

test("toolResponse returns non-error MCP payload for successful inspector output", () => {
  const payload = {
    schemaVersion: 4,
    command: "list-apps",
    success: true,
    data: {
      apps: []
    }
  };

  const response = toolResponse({
    exitedSuccessfully: true,
    envelope: payload,
    stdout: JSON.stringify(payload),
    stderr: ""
  });

  assert.equal(response.isError, false);
  assert.deepEqual(response.structuredContent, payload);
  assert.deepEqual(JSON.parse(response.content[0].text), payload);
});

test("toolResponse marks business failure payloads as MCP errors", () => {
  const payload = {
    schemaVersion: 4,
    command: "capture-hierarchy",
    success: false,
    errorCode: "target_capability_unsupported",
    error: "The target Runtime does not support hierarchy",
    recoverySuggestion: "Update the Runtime or use a tool declared by its current capabilities"
  };

  const response = toolResponse({
    exitedSuccessfully: true,
    envelope: payload,
    stdout: JSON.stringify(payload),
    stderr: ""
  });

  assert.equal(response.isError, true);
  assert.deepEqual(response.structuredContent, payload);
});

test("toolResponse completes incomplete CLI failures with actionable diagnostics", () => {
  const response = toolResponse({
    exitedSuccessfully: false,
    envelope: {
      schemaVersion: 4,
      command: "capture-hierarchy",
      success: false,
      error: "The target Runtime does not support hierarchy"
    },
    stdout: "",
    stderr: ""
  });

  assert.equal(response.isError, true);
  assert.equal(response.structuredContent.errorCode, "cli_command_failed");
  assert.match(response.structuredContent.recoverySuggestion, /list_apps/);
});

test("toolResponse never exposes a successful payload after the CLI process fails", () => {
  const response = toolResponse({
    exitedSuccessfully: false,
    envelope: {
      schemaVersion: 4,
      command: "list-apps",
      success: true,
      data: { apps: [] }
    },
    stdout: "",
    stderr: "broken",
    errorCode: "mcp_adapter_cli_process_failed",
    error: "Failure: astrolabe exited with code 2",
    recoverySuggestion: "Check the Host installation and command output"
  });

  assert.equal(response.isError, true);
  assert.equal(response.structuredContent.success, false);
  assert.equal(response.structuredContent.errorCode, "mcp_adapter_cli_process_failed");
  assert.match(response.structuredContent.recoverySuggestion, /Host/);
});

test("toolResponse exposes stdout and stderr when inspector returns no JSON envelope", () => {
  const response = toolResponse({
    exitedSuccessfully: false,
    stdout: "not json",
    stderr: "broken",
    error: "Failure: unable to parse astrolabe JSON output"
  });

  assert.equal(response.isError, true);
  assert.deepEqual(response.structuredContent, {
    schemaVersion: 4,
    success: false,
    errorCode: "mcp_adapter_invalid_cli_response",
    error: "Failure: unable to parse astrolabe JSON output",
    recoverySuggestion: "Ensure the Astrolabe Host executable exists and inspect stderr/stdout",
    stdout: "not json",
    stderr: "broken"
  });
});

test("toolResponse bounds raw process diagnostics", () => {
  const response = toolResponse({
    exitedSuccessfully: false,
    stdout: "x".repeat(10000),
    stderr: "y".repeat(10000),
    error: "Failure: unable to parse Astrolabe Host JSON output"
  });

  assert.ok(response.structuredContent.stdout.length <= 4096);
  assert.ok(response.structuredContent.stderr.length <= 4096);
  assert.match(response.structuredContent.stdout, /\[truncated]$/);
  assert.match(response.structuredContent.stderr, /\[truncated]$/);
});
