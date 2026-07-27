import test from "node:test";
import assert from "node:assert/strict";

import { parseInstallArgs } from "../scripts/installation/install-options.mjs";
import { createAIClientRegistry } from "../scripts/installation/install-command.mjs";
import { defaultClaudeCodeSkillDirectory } from "../scripts/installation/clients/claude-code-installer.mjs";

test("shared installer accepts multiple AI clients without duplicating them", () => {
  const options = parseInstallArgs([
    "--client",
    "codex",
    "--client",
    "opencode",
    "--client",
    "codex",
    "--package-dir",
    "/tmp/astrolabe-package",
    "--client-config",
    "codex=/tmp/codex/config.toml",
    "--client-config",
    "opencode=/tmp/opencode/opencode.json"
  ], {
    projectRoot: "/local/project",
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

test("shared installer rejects conflicting lifecycle actions", () => {
  assert.throws(
    () => parseInstallArgs(["--client", "codex", "--check", "--uninstall"]),
    /--check and --uninstall cannot be used together/
  );
});

test("shared installer maps repository updates to the source checkout", () => {
  const options = parseInstallArgs([
    "--client",
    "opencode",
    "--repo",
    "https://github.com/regulusleow/astrolabe.git",
    "--install-dir",
    "/tmp/astrolabe-source"
  ], {
    projectRoot: "/local/project"
  });

  assert.equal(options.repoUrl, "https://github.com/regulusleow/astrolabe.git");
  assert.equal(options.installDir, "/tmp/astrolabe-source");
  assert.equal(options.projectRoot, "/tmp/astrolabe-source");
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
