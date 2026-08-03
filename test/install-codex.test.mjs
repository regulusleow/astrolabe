import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  CodexInstaller,
  removeCodexSkillConfig,
  removeCodexServerConfig,
  renderCodexServerConfig,
  upsertCodexServerConfig
} from "../scripts/installation/clients/codex-installer.mjs";
import {
  checkManagedSkillLink,
  installManagedSkillLink,
  removeManagedSkillLink
} from "../scripts/installation/managed-skill-link.mjs";

const validSkill = `---
name: astrolabe
description: Use when inspecting a running mobile UI with Astrolabe.
---

# Astrolabe
`;

test("Codex installer renders the stable launcher MCP command", () => {
  const block = renderCodexServerConfig({
    serverName: "astrolabe",
    launcherPath: "/tmp/astrolabe-package/bin/astrolabe"
  });

  assert.match(block, /\[mcp_servers\.astrolabe]/);
  assert.match(block, /command = "\/tmp\/astrolabe-package\/bin\/astrolabe"/);
  assert.match(block, /args = \["mcp"]/);
  assert.doesNotMatch(block, /ASTROLABE_BIN/);
  assert.doesNotMatch(block, /mcp-adapter/);
});

test("Codex installer replaces only the managed astrolabe sections", () => {
  const existing = [
    `model = "gpt-5.5"`,
    ``,
    `[mcp_servers.figma]`,
    `url = "https://mcp.figma.com/mcp"`,
    ``,
    `[mcp_servers.astrolabe]`,
    `command = "node"`,
    `args = ["/old/index.js"]`,
    ``,
    `[mcp_servers.astrolabe.env]`,
    `ASTROLABE_BIN = "/old/astrolabe"`,
    ``,
    `[projects."/tmp/app"]`,
    `trust_level = "trusted"`,
    ``
  ].join("\n");

  const updated = upsertCodexServerConfig(existing, {
    serverName: "astrolabe",
    launcherPath: "/new/astrolabe"
  });

  assert.match(updated, /\[mcp_servers\.figma]/);
  assert.match(updated, /\[projects\."\/tmp\/app"]/);
  assert.match(updated, /command = "\/new\/astrolabe"/);
  assert.match(updated, /args = \["mcp"]/);
  assert.doesNotMatch(updated, /ASTROLABE_BIN/);
  assert.doesNotMatch(updated, /\/old\/index\.js/);
  assert.doesNotMatch(updated, /\/old\/astrolabe/);
});

test("Codex installer can remove stale managed skill config entries", () => {
  const existing = [
    `[[skills.config]]`,
    `path = "/tmp/astrolabe-package/skills/astrolabe/SKILL.md"`,
    `enabled = true`,
    ``,
    `[[skills.config]]`,
    `path = "/tmp/other-skill/SKILL.md"`,
    `enabled = false`,
    ``
  ].join("\n");

  const removed = removeCodexSkillConfig(existing, "/tmp/astrolabe-package/skills/astrolabe/SKILL.md");

  assert.doesNotMatch(removed, /astrolabe/);
  assert.match(removed, /path = "\/tmp\/other-skill\/SKILL\.md"/);
});

test("Codex installer can remove managed sections", () => {
  const existing = [
    `[mcp_servers.astrolabe]`,
    `command = "node"`,
    ``,
    `[mcp_servers.astrolabe.env]`,
    `ASTROLABE_BIN = "/tmp/bin"`,
    ``,
    `[mcp_servers.codegraph]`,
    `command = "codegraph"`,
    ``
  ].join("\n");

  const removed = removeCodexServerConfig(existing, "astrolabe");

  assert.doesNotMatch(removed, /astrolabe/);
  assert.match(removed, /\[mcp_servers\.codegraph]/);
  assert.match(removed, /command = "codegraph"/);
});

test("Codex check validates command and args inside the managed section", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-codex-check-"));
  const configPath = join(root, "config.toml");
  const launcherPath = "/stable/bin/astrolabe";
  writeFileSync(configPath, [
    "[mcp_servers.astrolabe]",
    "command = \"/wrong/astrolabe\"",
    "args = [\"wrong\"]",
    "",
    "[mcp_servers.other]",
    `command = "${launcherPath}"`,
    "args = [\"mcp\"]",
    ""
  ].join("\n"));
  try {
    const installer = new CodexInstaller({
      configPath,
      serverName: "astrolabe",
      distributionPaths: {
        publicLauncherPath: launcherPath,
        skillPath: "/stable/skills/astrolabe/SKILL.md"
      },
      skillDirectories: [],
      dryRun: false
    });

    assert.match(installer.check().join("\n"), /does not use the managed MCP launcher/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("shared installer manages one agent-compatible skill link", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-skill-link-test-"));
  const packageSkillDir = join(root, "package/skills/astrolabe");
  const userSkillDir = join(root, "agents/skills/astrolabe");
  mkdirSync(packageSkillDir, { recursive: true });
  writeFileSync(join(packageSkillDir, "SKILL.md"), validSkill);

  try {
    installManagedSkillLink(userSkillDir, packageSkillDir, false);
    assert.equal(realpathSync(userSkillDir), realpathSync(packageSkillDir));
    assert.deepEqual(checkManagedSkillLink(userSkillDir, packageSkillDir), []);
    assert.equal(removeManagedSkillLink(userSkillDir, packageSkillDir, false), true);
    assert.equal(existsSync(userSkillDir), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("shared installer never replaces an unmanaged skill directory", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-skill-link-test-"));
  const packageSkillDir = join(root, "package/skills/astrolabe");
  const userSkillDir = join(root, "agents/skills/astrolabe");
  mkdirSync(packageSkillDir, { recursive: true });
  mkdirSync(userSkillDir, { recursive: true });

  try {
    assert.throws(
      () => installManagedSkillLink(userSkillDir, packageSkillDir, false),
      /skill directory exists and is not a symbolic link/
    );
    assert.equal(removeManagedSkillLink(userSkillDir, packageSkillDir, false), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
