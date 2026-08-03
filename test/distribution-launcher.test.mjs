import test from "node:test";
import assert from "node:assert/strict";

import { runLauncher } from "../scripts/distribution/launcher.mjs";

function launcherDependencies(overrides = {}) {
  return {
    paths: {
      mcpEntryPath: "/pkg/libexec/mcp-adapter/dist/index.js",
      nativeExecutablePath: "/pkg/libexec/astrolabe-native"
    },
    manifest: { version: "2.0.0" },
    spawn() {
      return { status: 0 };
    },
    stdout: { write() {} },
    stderr: { write() {} },
    runManagement: async () => 0,
    runDoctor: async () => 0,
    ...overrides
  };
}

test("launcher routes MCP through Node and native inspection through astrolabe-native", async () => {
  const calls = [];
  const dependencies = launcherDependencies({
    spawn(command, args, options) {
      calls.push({ command, args, options });
      return { status: 0 };
    }
  });

  assert.equal(await runLauncher(["mcp"], dependencies), 0);
  assert.equal(
    await runLauncher(["inspect-screen", "app-id", "--json"], dependencies),
    0
  );
  assert.deepEqual(calls, [
    {
      command: process.execPath,
      args: ["/pkg/libexec/mcp-adapter/dist/index.js"],
      options: { stdio: "inherit" }
    },
    {
      command: "/pkg/libexec/astrolabe-native",
      args: ["inspect-screen", "app-id", "--json"],
      options: { stdio: "inherit" }
    }
  ]);
});

test("launcher forwards MCP arguments and child exit status", async () => {
  const calls = [];
  const exitCode = await runLauncher(["mcp", "--transport", "stdio"], launcherDependencies({
    spawn(command, args) {
      calls.push({ command, args });
      return { status: 7 };
    }
  }));

  assert.equal(exitCode, 7);
  assert.deepEqual(calls, [{
    command: process.execPath,
    args: ["/pkg/libexec/mcp-adapter/dist/index.js", "--transport", "stdio"]
  }]);
});

test("launcher routes client lifecycle and Doctor without spawning", async () => {
  const calls = [];
  const dependencies = launcherDependencies({
    spawn() {
      assert.fail("management commands must not spawn through native routing");
    },
    async runManagement(command, args) {
      calls.push({ kind: "management", command, args });
      return 3;
    },
    async runDoctor(args) {
      calls.push({ kind: "doctor", args });
      return 4;
    }
  });

  assert.equal(await runLauncher(["install", "--client", "codex"], dependencies), 3);
  assert.equal(await runLauncher(["doctor", "--verbose"], dependencies), 4);
  assert.deepEqual(calls, [
    { kind: "management", command: "install", args: ["--client", "codex"] },
    { kind: "doctor", args: ["--verbose"] }
  ]);
});

test("launcher prints help and manifest version without spawning", async () => {
  const stdout = [];
  const dependencies = launcherDependencies({
    stdout: { write: (value) => stdout.push(value) },
    spawn() {
      assert.fail("help and version must not spawn");
    }
  });

  assert.equal(await runLauncher([], dependencies), 0);
  assert.equal(await runLauncher(["--version"], dependencies), 0);
  assert.match(stdout[0], /Usage:/);
  assert.equal(stdout[1], "2.0.0\n");
});

test("launcher rejects an unknown command without spawning", async () => {
  const stderr = [];
  let spawned = false;
  const exitCode = await runLauncher(["unknown-command"], launcherDependencies({
    spawn() {
      spawned = true;
      return { status: 0 };
    },
    stderr: { write: (value) => stderr.push(value) }
  }));

  assert.equal(exitCode, 2);
  assert.equal(spawned, false);
  assert.match(stderr.join(""), /Unknown command: unknown-command/);
});

test("launcher reports a failed child spawn", async () => {
  const stderr = [];
  const exitCode = await runLauncher(["list-apps"], launcherDependencies({
    spawn() {
      return { status: null, error: new Error("permission denied") };
    },
    stderr: { write: (value) => stderr.push(value) }
  }));

  assert.equal(exitCode, 1);
  assert.match(stderr.join(""), /Failed to start subprocess: permission denied/);
});
