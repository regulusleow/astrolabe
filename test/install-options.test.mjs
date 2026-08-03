import test from "node:test";
import assert from "node:assert/strict";

import { parseInstallArgs } from "../scripts/installation/install-options.mjs";
import {
  createAIClientRegistry,
  installationHelpText,
  resolveLifecycleClientIDs
} from "../scripts/installation/install-command.mjs";
import { detectAIClients } from "../scripts/installation/ai-client-detector.mjs";
import { defaultClaudeCodeSkillDirectory } from "../scripts/installation/clients/claude-code-installer.mjs";

test("shared installer accepts multiple AI clients without duplicating them", () => {
  const options = parseInstallArgs([
    "--client",
    "codex",
    "--client",
    "opencode",
    "--client",
    "codex",
    "--client-config",
    "codex=/tmp/codex/config.toml",
    "--client-config",
    "opencode=/tmp/opencode/opencode.json"
  ], {
    packageDir: "/tmp/astrolabe-package",
    userSkillDir: "/tmp/agents/skills/astrolabe"
  });

  assert.deepEqual(options.clientIDs, ["codex", "opencode"]);
  assert.equal(options.action, "install");
  assert.equal(options.packageDir, "/tmp/astrolabe-package");
  assert.equal(options.userSkillDir, "/tmp/agents/skills/astrolabe");
  assert.equal(options.clientConfigPaths.codex, "/tmp/codex/config.toml");
  assert.equal(options.clientConfigPaths.opencode, "/tmp/opencode/opencode.json");
});

test("shared installer requires at least one explicit AI client", () => {
  assert.throws(
    () => parseInstallArgs([]),
    /at least one --client is required/
  );
});

test("all-detected selects only clients with a command or config location", () => {
  assert.deepEqual(detectAIClients({
    homeDirectory: "/Users/tester",
    environment: { PATH: "/usr/bin" },
    commandExists: (name) => name === "codex",
    pathExists: (path) => path === "/Users/tester/.config/opencode"
  }), ["codex", "opencode"]);
});

test("all-detected honors the OpenCode configuration override", () => {
  assert.deepEqual(detectAIClients({
    homeDirectory: "/Users/tester",
    environment: {
      PATH: "",
      OPENCODE_CONFIG: "/private/config/opencode.json"
    },
    commandExists: () => false,
    pathExists: (path) => path === "/private/config/opencode.json"
  }), ["opencode"]);
});

test("shared installer accepts all-detected for install", () => {
  const options = parseInstallArgs(["--all-detected"]);

  assert.equal(options.clientSelection, "detected");
  assert.deepEqual(options.clientIDs, []);
});

test("shared installer accepts all-configured for uninstall", () => {
  const options = parseInstallArgs(["--all-configured"], { action: "uninstall" });

  assert.equal(options.action, "uninstall");
  assert.equal(options.clientSelection, "configured");
});

test("installation help documents every client selection mode", () => {
  const help = installationHelpText();

  assert.match(help, /install .*--all-detected/);
  assert.match(help, /check .*--all-configured/);
  assert.match(help, /uninstall .*--all-configured/);
  assert.match(help, /--client-config/);
});

test("shared installer rejects mixed explicit and automatic selection", () => {
  assert.throws(
    () => parseInstallArgs(["--client", "codex", "--all-detected"]),
    /choose exactly one client selection mode/
  );
});

test("shared installer rejects selection modes incompatible with the action", () => {
  assert.throws(
    () => parseInstallArgs(["--all-configured"]),
    /--all-configured is available only for check or uninstall/
  );
  assert.throws(
    () => parseInstallArgs(["--all-detected"], { action: "uninstall" }),
    /--all-detected is available only for install or check/
  );
});

test("configured selection resolves only configured clients", () => {
  const registry = {
    all() {
      return [
        { id: "codex", isConfigured: () => true },
        { id: "opencode", isConfigured: () => false },
        { id: "claude-code", isConfigured: () => true }
      ];
    }
  };

  assert.deepEqual(resolveLifecycleClientIDs({
    clientSelection: "configured",
    clientIDs: []
  }, registry, []), ["codex", "claude-code"]);
});

test("installed lifecycle action cannot be changed by an option", () => {
  for (const actionOption of ["--check", "--uninstall"]) {
    assert.throws(
      () => parseInstallArgs(["--client", "codex", actionOption], { action: "install" }),
      /unknown option/
    );
  }
});

test("installed lifecycle rejects source and package relocation options", () => {
  for (const args of [
    ["--client", "opencode", "--repo", "https://example.com/repo.git"],
    ["--client", "opencode", "--git", "https://example.com/repo.git"],
    ["--client", "opencode", "--install-dir", "/tmp/source"],
    ["--client", "opencode", "--package-dir", "/tmp/package"]
  ]) {
    assert.throws(() => parseInstallArgs(args), /unknown option/);
  }
});

test("shared installer rejects malformed client configuration overrides", () => {
  assert.throws(
    () => parseInstallArgs([
      "--client",
      "opencode",
      "--client-config",
      "missing-separator"
    ]),
    /client configuration override must use <client>=<path>/
  );
});

test("shared installer rejects configuration overrides for unknown clients", () => {
  const options = parseInstallArgs([
    "--client",
    "codex",
    "--client-config",
    "unknown=/tmp/unknown.json"
  ]);

  assert.throws(
    () => createAIClientRegistry(options),
    /unsupported AI client: unknown/
  );
});

test("shared installer rejects configuration overrides for unselected clients", () => {
  const options = parseInstallArgs([
    "--client",
    "codex",
    "--client-config",
    "opencode=/tmp/opencode.json"
  ]);

  assert.throws(
    () => createAIClientRegistry(options),
    /--client-config provided for unselected AI client: opencode/
  );
});

test("shared installer registers Claude Code with its user configuration and skill", () => {
  const options = parseInstallArgs([
    "--client",
    "claude-code",
    "--client-config",
    "claude-code=/tmp/claude/.claude.json"
  ]);

  const client = createAIClientRegistry(options).resolve(["claude-code"])[0];

  assert.equal(client.id, "claude-code");
  assert.equal(client.configPath, "/tmp/claude/.claude.json");
  assert.deepEqual(client.skillDirectories, [defaultClaudeCodeSkillDirectory()]);
});
