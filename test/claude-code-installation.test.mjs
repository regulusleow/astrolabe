import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  ClaudeCodeInstaller,
  defaultClaudeCodeConfigPath,
  defaultClaudeCodeSkillDirectory,
  removeClaudeCodeServerConfig,
  upsertClaudeCodeServerConfig
} from "../scripts/installation/clients/claude-code-installer.mjs";

test("Claude Code installer preserves unrelated user state", () => {
  const existing = `{
  "firstStartTime": "2026-07-20T10:26:57.753Z",
  "projects": {
    "/tmp/example": {"allowedTools": []}
  },
  "mcpServers": {
    "other": {
      "type": "stdio",
      "command": "other-server"
    }
  }
}\n`;

  const updated = upsertClaudeCodeServerConfig(existing, {
    serverName: "astrolabe",
    launcherPath: "/tmp/astrolabe/bin/astrolabe"
  });

  assert.match(updated, /"firstStartTime": "2026-07-20T10:26:57\.753Z"/);
  assert.match(updated, /"projects"/);
  assert.match(updated, /"other"/);
  assert.match(updated, /"astrolabe"/);
  assert.match(updated, /"type": "stdio"/);
  assert.match(updated, /"command": "\/tmp\/astrolabe\/bin\/astrolabe"/);
  assert.match(updated, /"args": \[\s*"mcp"\s*]/);
  assert.doesNotMatch(updated, /ASTROLABE_BIN/);
});

test("Claude Code installer replaces and removes only its MCP entry", () => {
  const existing = `{
  "mcpServers": {
    "astrolabe": {
      "type": "stdio",
      "command": "node",
      "args": ["/old/index.js"],
      "env": {"ASTROLABE_BIN": "/old/astrolabe"}
    },
    "other": {
      "type": "stdio",
      "command": "other-server"
    }
  }
}\n`;

  const updated = upsertClaudeCodeServerConfig(existing, {
    serverName: "astrolabe",
    launcherPath: "/new/astrolabe"
  });
  assert.doesNotMatch(updated, /\/old\/index\.js/);
  assert.match(updated, /\/new\/astrolabe/);
  assert.match(updated, /"mcp"/);
  assert.match(updated, /"other"/);

  const removed = removeClaudeCodeServerConfig(updated, "astrolabe");
  assert.doesNotMatch(removed, /"astrolabe"/);
  assert.match(removed, /"other"/);
});

test("Claude Code installer configures, checks, and uninstalls one user MCP entry", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-claude-code-test-"));
  const configPath = join(root, ".claude.json");
  const distributionPaths = {
    publicLauncherPath: "/tmp/astrolabe/bin/astrolabe"
  };
  writeFileSync(configPath, `{"projects":{"/tmp/example":{}}}\n`);
  const installer = new ClaudeCodeInstaller({
    configPath,
    serverName: "astrolabe",
    distributionPaths,
    skillDirectories: [join(root, ".claude", "skills", "astrolabe")],
    dryRun: false
  });

  try {
    installer.install();
    assert.equal(installer.isConfigured(), true);
    assert.deepEqual(installer.check(), []);
    assert.equal(existsSync(`${configPath}.astrolabe.bak`), true);
    assert.match(readFileSync(configPath, "utf8"), /"projects"/);

    installer.uninstall();
    assert.equal(installer.isConfigured(), false);
    assert.match(readFileSync(configPath, "utf8"), /"projects"/);
    assert.doesNotMatch(readFileSync(configPath, "utf8"), /"astrolabe"/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("Claude Code installer requires the exact managed stdio command", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-claude-code-test-"));
  const configPath = join(root, ".claude.json");
  writeFileSync(configPath, `{
  "mcpServers": {
    "astrolabe": {
      "type": "stdio",
      "command": "custom-launcher",
      "args": ["/new/index.js", "--unsafe"],
      "env": {"ASTROLABE_BIN": "/new/astrolabe"}
    }
  }
}\n`);
  const installer = new ClaudeCodeInstaller({
    configPath,
    serverName: "astrolabe",
    distributionPaths: {
      publicLauncherPath: "/new/astrolabe"
    },
    skillDirectories: [],
    dryRun: false
  });

  try {
    assert.deepEqual(installer.check(), [
      "Claude Code configuration does not use the managed MCP command: astrolabe"
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("Claude Code paths follow CLAUDE_CONFIG_DIR when configured", () => {
  const environment = { CLAUDE_CONFIG_DIR: "~/custom-claude" };

  assert.equal(
    defaultClaudeCodeConfigPath(environment, "/Users/example"),
    "/Users/example/custom-claude/.claude.json"
  );
  assert.equal(
    defaultClaudeCodeSkillDirectory(environment, "/Users/example"),
    "/Users/example/custom-claude/skills/astrolabe"
  );
});

test("Claude Code paths use the documented user defaults", () => {
  assert.equal(
    defaultClaudeCodeConfigPath({}, "/Users/example"),
    "/Users/example/.claude.json"
  );
  assert.equal(
    defaultClaudeCodeSkillDirectory({}, "/Users/example"),
    "/Users/example/.claude/skills/astrolabe"
  );
});
