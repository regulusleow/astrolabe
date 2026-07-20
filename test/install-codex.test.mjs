import test from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  removeCodexSkillConfig,
  removeCodexServerConfig,
  renderCodexServerConfig,
  upsertCodexServerConfig
} from "../scripts/installation/clients/codex-installer.mjs";
import {
  packageArtifactPaths,
  sourceArtifactPaths
} from "../scripts/installation/package-layout.mjs";
import {
  assertSafePackageDir,
  assertSkillMetadata,
  installRuntimePackage,
  replaceRuntimePackage,
} from "../scripts/installation/runtime-package-installer.mjs";
import { parseInstallArgs } from "../scripts/installation/install-options.mjs";
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

test("Codex installer renders the managed MCP sections", () => {
  const paths = packageArtifactPaths("/tmp/astrolabe-package");
  const block = renderCodexServerConfig({
    serverName: "astrolabe",
    mcpEntryPath: paths.mcpEntryPath,
    inspectorBinPath: paths.inspectorBinPath
  });

  assert.match(block, /\[mcp_servers\.astrolabe]/);
  assert.match(block, /command = "node"/);
  assert.match(block, /args = \["\/tmp\/astrolabe-package\/mcp-adapter\/dist\/index\.js"]/);
  assert.match(block, /\[mcp_servers\.astrolabe\.env]/);
  assert.match(block, /ASTROLABE_BIN = "\/tmp\/astrolabe-package\/bin\/astrolabe"/);
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
    mcpEntryPath: "/new/index.js",
    inspectorBinPath: "/new/astrolabe"
  });

  assert.match(updated, /\[mcp_servers\.figma]/);
  assert.match(updated, /\[projects\."\/tmp\/app"]/);
  assert.match(updated, /args = \["\/new\/index\.js"]/);
  assert.match(updated, /ASTROLABE_BIN = "\/new\/astrolabe"/);
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

test("Codex installer maps repo installs to the install directory", () => {
  const options = parseInstallArgs([
    "--client",
    "codex",
    "--repo",
    "https://github.com/regulusleow/astrolabe.git",
    "--install-dir",
    "/tmp/astrolabe-install",
    "--package-dir",
    "/tmp/astrolabe-package",
    "--client-config",
    "codex=/tmp/codex/config.toml"
  ], {
    projectRoot: "/local/project",
    packageDir: "/default/package"
  });

  assert.equal(options.repoUrl, "https://github.com/regulusleow/astrolabe.git");
  assert.equal(options.projectRoot, "/tmp/astrolabe-install");
  assert.equal(options.installDir, "/tmp/astrolabe-install");
  assert.equal(options.packageDir, "/tmp/astrolabe-package");
  assert.equal(options.clientConfigPaths.codex, "/tmp/codex/config.toml");
});

test("Codex installer separates source artifacts from package artifacts", () => {
  const sourcePaths = sourceArtifactPaths("/tmp/astrolabe-source");
  const packagePaths = packageArtifactPaths("/tmp/astrolabe-package");

  assert.equal(sourcePaths.inspectorBuildPath, "/tmp/astrolabe-source/.build/release/astrolabe");
  assert.equal(sourcePaths.mcpEntryPath, "/tmp/astrolabe-source/mcp-adapter/dist/index.js");
  assert.equal(sourcePaths.skillPath, "/tmp/astrolabe-source/skills/astrolabe/SKILL.md");
  assert.equal(packagePaths.inspectorBinPath, "/tmp/astrolabe-package/bin/astrolabe");
  assert.equal(packagePaths.mcpEntryPath, "/tmp/astrolabe-package/mcp-adapter/dist/index.js");
  assert.equal(packagePaths.skillPath, "/tmp/astrolabe-package/skills/astrolabe/SKILL.md");
});

test("Codex installer installs packaged MCP dependencies from the package directory", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-install-test-"));
  const projectRoot = join(root, "source");
  const packageDir = join(root, "package");
  const commands = [];
  mkdirSync(join(projectRoot, ".build/release"), { recursive: true });
  mkdirSync(join(projectRoot, "mcp-adapter/dist"), { recursive: true });
  mkdirSync(join(projectRoot, "skills/astrolabe"), { recursive: true });
  writeFileSync(join(projectRoot, ".build/release/astrolabe"), "binary");
  writeFileSync(join(projectRoot, "mcp-adapter/dist/index.js"), "entry");
  writeFileSync(join(projectRoot, "mcp-adapter/package.json"), "{}");
  writeFileSync(join(projectRoot, "mcp-adapter/package-lock.json"), "{}");
  writeFileSync(join(projectRoot, "skills/astrolabe/SKILL.md"), validSkill);

  try {
    installRuntimePackage(
      { projectRoot, packageDir, dryRun: false },
      (command, args, options) => commands.push({ command, args, options })
    );

    assert.equal(commands.length, 1);
    assert.equal(commands[0].command, "npm");
    assert.deepEqual(commands[0].args, ["ci", "--omit=dev"]);
    assert.match(commands[0].options.cwd, /\.staging-\d+-\d+\/mcp-adapter$/);
    assert.equal(existsSync(join(packageDir, ".astrolabe-package")), true);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("Codex installer validates the packaged skill discovery metadata", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-skill-test-"));
  const skillPath = join(root, "SKILL.md");
  try {
    writeFileSync(skillPath, validSkill);
    assert.doesNotThrow(() => assertSkillMetadata(skillPath));

    writeFileSync(skillPath, "# missing frontmatter\n");
    assert.throws(() => assertSkillMetadata(skillPath), /skill metadata/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("Codex installer rejects existing unmanaged package directories", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-install-test-"));
  const projectRoot = join(root, "source");
  const packageDir = join(root, "custom-package");
  mkdirSync(projectRoot);
  mkdirSync(packageDir);
  try {
    assert.throws(
      () => assertSafePackageDir(packageDir, projectRoot),
      /refusing to overwrite a directory not managed by Astrolabe/
    );
    writeFileSync(join(packageDir, ".astrolabe-package"), "managed\n");
    assert.doesNotThrow(() => assertSafePackageDir(packageDir, projectRoot));
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("Codex installer rejects a package directory containing the source", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-install-test-"));
  const projectRoot = join(root, "source");
  mkdirSync(projectRoot);
  try {
    assert.throws(
      () => assertSafePackageDir(root, projectRoot),
      /local runtime package directory cannot contain the source directory/
    );
    const nestedPackageDir = join(projectRoot, "package");
    mkdirSync(nestedPackageDir);
    assert.throws(
      () => assertSafePackageDir(nestedPackageDir, projectRoot),
      /local runtime package directory cannot be inside the source directory/
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("Codex installer atomically replaces a managed package", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-install-test-"));
  const packageDir = join(root, "package");
  const stagingDir = join(root, "staging");
  mkdirSync(packageDir);
  mkdirSync(stagingDir);
  writeFileSync(join(packageDir, "version"), "old");
  writeFileSync(join(stagingDir, "version"), "new");
  try {
    replaceRuntimePackage(stagingDir, packageDir);
    assert.equal(readFileSync(join(packageDir, "version"), "utf8"), "new");
    assert.equal(existsSync(stagingDir), false);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("Codex installer restores the previous package when replacement fails", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-install-test-"));
  const packageDir = join(root, "package");
  mkdirSync(packageDir);
  writeFileSync(join(packageDir, "version"), "old");
  try {
    assert.throws(
      () => replaceRuntimePackage(join(root, "missing-staging"), packageDir)
    );
    assert.equal(readFileSync(join(packageDir, "version"), "utf8"), "old");
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
