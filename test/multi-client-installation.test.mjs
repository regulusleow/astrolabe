import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  OpenCodeInstaller,
  removeOpenCodeServerConfig,
  upsertOpenCodeServerConfig
} from "../scripts/installation/clients/opencode-installer.mjs";
import { AIClientRegistry } from "../scripts/installation/ai-client-registry.mjs";
import { runInstallation } from "../scripts/installation/installation-orchestrator.mjs";

test("OpenCode installer preserves JSONC comments and unrelated configuration", () => {
  const existing = `{
  // Keep the selected providers.
  "enabled_providers": ["openai"],
  "mcp": {
    "figma": {
      "type": "remote",
      "url": "http://127.0.0.1:3845/mcp",
      "enabled": false,
    },
  },
}\n`;

  const updated = upsertOpenCodeServerConfig(existing, {
    serverName: "astrolabe",
    mcpEntryPath: "/tmp/astrolabe/mcp-adapter/dist/index.js",
    inspectorBinPath: "/tmp/astrolabe/bin/astrolabe"
  });

  assert.match(updated, /\/\/ Keep the selected providers\./);
  assert.match(updated, /"enabled_providers": \["openai"\]/);
  assert.match(updated, /"figma"/);
  assert.match(updated, /"astrolabe"/);
  assert.match(updated, /"type": "local"/);
  assert.match(updated, /"command": \[/);
  assert.match(updated, /"node"/);
  assert.match(updated, /"enabled": true/);
  assert.match(updated, /"ASTROLABE_BIN": "\/tmp\/astrolabe\/bin\/astrolabe"/);
});

test("OpenCode installer replaces and removes only its managed MCP entry", () => {
  const existing = `{
  "mcp": {
    "astrolabe": {
      "type": "local",
      "command": ["node", "/old/index.js"],
      "environment": {"ASTROLABE_BIN": "/old/astrolabe"}
    },
    "codegraph": {
      "type": "local",
      "command": ["codegraph", "serve", "--mcp"]
    }
  }
}\n`;

  const updated = upsertOpenCodeServerConfig(existing, {
    serverName: "astrolabe",
    mcpEntryPath: "/new/index.js",
    inspectorBinPath: "/new/astrolabe"
  });
  assert.doesNotMatch(updated, /\/old\/index\.js/);
  assert.match(updated, /\/new\/index\.js/);
  assert.match(updated, /"codegraph"/);

  const removed = removeOpenCodeServerConfig(updated, "astrolabe");
  assert.doesNotMatch(removed, /"astrolabe"/);
  assert.match(removed, /"codegraph"/);
});

test("OpenCode installer configures, checks, and uninstalls one global MCP entry", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-opencode-test-"));
  const configPath = join(root, "opencode.json");
  const packagePaths = {
    mcpEntryPath: "/tmp/astrolabe/mcp-adapter/dist/index.js",
    inspectorBinPath: "/tmp/astrolabe/bin/astrolabe"
  };
  writeFileSync(configPath, `{
  // Existing user setting.
  "enabled_providers": ["openai"]
}\n`);
  const installer = new OpenCodeInstaller({
    configPath,
    serverName: "astrolabe",
    packagePaths,
    skillDirectories: ["/tmp/agents/skills/astrolabe"],
    dryRun: false
  });

  try {
    installer.install();
    assert.equal(installer.isConfigured(), true);
    assert.deepEqual(installer.check(), []);
    assert.equal(existsSync(`${configPath}.astrolabe.bak`), true);
    assert.match(readFileSync(configPath, "utf8"), /Existing user setting/);

    installer.uninstall();
    assert.equal(installer.isConfigured(), false);
    assert.match(readFileSync(configPath, "utf8"), /"enabled_providers"/);
    assert.doesNotMatch(readFileSync(configPath, "utf8"), /"astrolabe"/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("OpenCode installer reports paths that do not match the installed package", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-opencode-test-"));
  const configPath = join(root, "opencode.json");
  writeFileSync(configPath, `{
  "mcp": {
    "astrolabe": {
      "type": "local",
      "command": ["node", "/old/index.js"],
      "environment": {"ASTROLABE_BIN": "/old/astrolabe"}
    }
  }
}\n`);
  const installer = new OpenCodeInstaller({
    configPath,
    serverName: "astrolabe",
    packagePaths: {
      mcpEntryPath: "/new/index.js",
      inspectorBinPath: "/new/astrolabe"
    },
    skillDirectories: [],
    dryRun: false
  });

  try {
    assert.deepEqual(installer.check(), [
      "OpenCode configuration does not point to the MCP adapter: /new/index.js",
      "OpenCode configuration does not point to the CLI binary: /new/astrolabe",
      "OpenCode MCP server must be enabled: astrolabe"
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("OpenCode installer rejects a non-object mcp configuration", () => {
  assert.throws(
    () => upsertOpenCodeServerConfig(`{"mcp": false}\n`, {
      serverName: "astrolabe",
      mcpEntryPath: "/new/index.js",
      inspectorBinPath: "/new/astrolabe"
    }),
    /OpenCode mcp configuration must be an object/
  );
});

test("installation builds the shared package once and configures every selected client", () => {
  const events = [];
  const sharedSkillDirectory = "/tmp/skills/astrolabe";
  const registry = new AIClientRegistry([
    fakeClient("codex", sharedSkillDirectory, events),
    fakeClient("opencode", sharedSkillDirectory, events)
  ]);

  runInstallation(
    {
      action: "install",
      clientIDs: ["codex", "opencode"]
    },
    {
      registry,
      preparePackage: () => events.push("package:prepare"),
      installSkillLink: (path) => events.push(`skill:install:${path}`),
      removeSkillLink: () => assert.fail("install must not remove a skill link")
    }
  );

  assert.deepEqual(events, [
    "package:prepare",
    `skill:install:${sharedSkillDirectory}`,
    "codex:install",
    "opencode:install"
  ]);
});

test("installation manages distinct skill directories for different AI clients", () => {
  const events = [];
  const registry = new AIClientRegistry([
    fakeClient("codex", "/tmp/.agents/skills/astrolabe", events),
    fakeClient("claude-code", "/tmp/.claude/skills/astrolabe", events)
  ]);

  runInstallation(
    {
      action: "install",
      clientIDs: ["codex", "claude-code"]
    },
    {
      registry,
      preparePackage: () => events.push("package:prepare"),
      installSkillLink: (path) => events.push(`skill:install:${path}`),
      removeSkillLink: () => assert.fail("install must not remove a skill link")
    }
  );

  assert.deepEqual(events, [
    "package:prepare",
    "skill:install:/tmp/.agents/skills/astrolabe",
    "skill:install:/tmp/.claude/skills/astrolabe",
    "codex:install",
    "claude-code:install"
  ]);
});

test("installation check validates skill directories owned by selected clients", () => {
  const checkedSkillDirectories = [];
  const registry = new AIClientRegistry([
    fakeClient("codex", "/tmp/.agents/skills/astrolabe", []),
    fakeClient("claude-code", "/tmp/.claude/skills/astrolabe", [])
  ]);

  runInstallation(
    {
      action: "check",
      clientIDs: ["claude-code"]
    },
    {
      registry,
      checkSharedInstallation(skillDirectories) {
        checkedSkillDirectories.push(...skillDirectories);
        return [];
      }
    }
  );

  assert.deepEqual(checkedSkillDirectories, ["/tmp/.claude/skills/astrolabe"]);
});

test("OpenCode installer requires the exact managed local command", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-opencode-test-"));
  const configPath = join(root, "opencode.json");
  writeFileSync(configPath, `{
  "mcp": {
    "astrolabe": {
      "type": "local",
      "command": ["custom-launcher", "/new/index.js", "--unsafe"],
      "enabled": true,
      "environment": {"ASTROLABE_BIN": "/new/astrolabe"}
    }
  }
}\n`);
  const installer = new OpenCodeInstaller({
    configPath,
    serverName: "astrolabe",
    packagePaths: {
      mcpEntryPath: "/new/index.js",
      inspectorBinPath: "/new/astrolabe"
    },
    skillDirectories: [],
    dryRun: false
  });

  try {
    assert.deepEqual(installer.check(), [
      "OpenCode configuration does not point to the MCP adapter: /new/index.js"
    ]);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("uninstall retains shared skills when another client configuration is unreadable", () => {
  const events = [];
  const sharedSkillDirectory = "/tmp/skills/astrolabe";
  const registry = new AIClientRegistry([
    fakeClient("codex", sharedSkillDirectory, events),
    {
      ...fakeClient("opencode", sharedSkillDirectory, events),
      isConfigured() {
        throw new Error("invalid client configuration");
      }
    }
  ]);

  runInstallation(
    {
      action: "uninstall",
      clientIDs: ["codex"]
    },
    {
      registry,
      preparePackage: () => assert.fail("uninstall must not build the package"),
      installSkillLink: () => assert.fail("uninstall must not install a skill link"),
      removeSkillLink: (path) => events.push(`skill:remove:${path}`)
    }
  );

  assert.deepEqual(events, ["codex:uninstall"]);
});

test("uninstall keeps a shared skill while another configured client needs it", () => {
  const events = [];
  const sharedSkillDirectory = "/tmp/skills/astrolabe";
  const codex = fakeClient("codex", sharedSkillDirectory, events);
  const opencode = fakeClient("opencode", sharedSkillDirectory, events, true);
  const registry = new AIClientRegistry([codex, opencode]);

  runInstallation(
    {
      action: "uninstall",
      clientIDs: ["codex"]
    },
    {
      registry,
      preparePackage: () => assert.fail("uninstall must not build the package"),
      installSkillLink: () => assert.fail("uninstall must not install a skill link"),
      removeSkillLink: (path) => events.push(`skill:remove:${path}`)
    }
  );

  assert.deepEqual(events, ["codex:uninstall"]);
});

test("uninstall removes a shared skill when no configured client needs it", () => {
  const events = [];
  const sharedSkillDirectory = "/tmp/skills/astrolabe";
  const registry = new AIClientRegistry([
    fakeClient("codex", sharedSkillDirectory, events),
    fakeClient("opencode", sharedSkillDirectory, events)
  ]);

  runInstallation(
    {
      action: "uninstall",
      clientIDs: ["codex"]
    },
    {
      registry,
      preparePackage: () => assert.fail("uninstall must not build the package"),
      installSkillLink: () => assert.fail("uninstall must not install a skill link"),
      removeSkillLink: (path) => events.push(`skill:remove:${path}`)
    }
  );

  assert.deepEqual(events, [
    "codex:uninstall",
    `skill:remove:${sharedSkillDirectory}`
  ]);
});

test("uninstall treats selected clients as removed when checking shared ownership", () => {
  const events = [];
  const sharedSkillDirectory = "/tmp/skills/astrolabe";
  const registry = new AIClientRegistry([
    fakeClient("codex", sharedSkillDirectory, events, true),
    fakeClient("opencode", sharedSkillDirectory, events)
  ]);

  runInstallation(
    {
      action: "uninstall",
      clientIDs: ["codex"]
    },
    {
      registry,
      preparePackage: () => assert.fail("uninstall must not build the package"),
      installSkillLink: () => assert.fail("uninstall must not install a skill link"),
      removeSkillLink: (path) => events.push(`skill:remove:${path}`)
    }
  );

  assert.deepEqual(events, [
    "codex:uninstall",
    `skill:remove:${sharedSkillDirectory}`
  ]);
});

function fakeClient(id, skillDirectory, events, configured = false) {
  return {
    id,
    skillDirectories: [skillDirectory],
    install() {
      events.push(`${id}:install`);
    },
    uninstall() {
      events.push(`${id}:uninstall`);
    },
    check() {
      events.push(`${id}:check`);
      return [];
    },
    isConfigured() {
      return configured;
    }
  };
}
