import test from "node:test";
import assert from "node:assert/strict";
import { inspectorTimeoutMs, runInspector } from "../dist/inspector-cli.js";

test("baseline workflows use the extended MCP timeout", () => {
  assert.equal(inspectorTimeoutMs(["record-baseline"]), 110000);
  assert.equal(inspectorTimeoutMs(["compare-baseline"]), 110000);
  assert.equal(inspectorTimeoutMs(["inspect-diff"]), 110000);
  assert.equal(inspectorTimeoutMs(["list-apps"]), 30000);
});

test("runInspector kills a hung CLI process after timeout", async () => {
  const result = await Promise.race([
    runInspector(process.execPath, ["-e", "setTimeout(() => {}, 500)"], { timeoutMs: 50 }),
    delay(200).then(() => "hung")
  ]);

  assert.notEqual(result, "hung");
  assert.equal(result.exitedSuccessfully, false);
  assert.match(result.error, /timed out/);
});

test("runInspector accepts a valid versioned CLI envelope", async () => {
  const envelope = {
    schemaVersion: 4,
    command: "list-apps",
    success: true,
    data: { apps: [] }
  };

  const result = await runInspector(process.execPath, [
    "-e",
    `process.stdout.write(${JSON.stringify(JSON.stringify(envelope))})`
  ]);

  assert.equal(result.exitedSuccessfully, true);
  assert.deepEqual(result.envelope, envelope);
  assert.equal(result.error, undefined);
});

test("runInspector rejects JSON that does not match the CLI envelope contract", async () => {
  const result = await runInspector(process.execPath, [
    "-e",
    `process.stdout.write(${JSON.stringify(JSON.stringify({ data: {} }))})`
  ]);

  assert.equal(result.exitedSuccessfully, true);
  assert.equal(result.envelope, undefined);
  assert.equal(result.errorCode, "mcp_adapter_invalid_cli_envelope");
  assert.match(result.error, /response contract/);
  assert.match(result.recoverySuggestion, /Host/);
});

test("runInspector rejects an unsupported CLI envelope schema version", async () => {
  const result = await runInspector(process.execPath, [
    "-e",
    `process.stdout.write(${JSON.stringify(JSON.stringify({
      schemaVersion: 5,
      command: "list-apps",
      success: true,
      data: { apps: [] }
    }))})`
  ]);

  assert.equal(result.envelope, undefined);
  assert.equal(result.errorCode, "mcp_adapter_invalid_cli_envelope");
  assert.match(result.error, /schemaVersion/);
});

function delay(intervalMs) {
  return new Promise((resolvePromise) => {
    setTimeout(resolvePromise, intervalMs);
  });
}
