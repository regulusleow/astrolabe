import assert from "node:assert/strict";
import {
  chmodSync,
  cpSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readlinkSync,
  realpathSync,
  rmSync,
  symlinkSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import test from "node:test";

import { assembleDistribution } from "../scripts/distribution/distribution-assembler.mjs";
import { distributionPaths } from "../scripts/distribution/distribution-layout.mjs";

const repositoryRoot = resolve(import.meta.dirname, "..");

test("installed launcher configures and removes Codex without source build commands", () => {
  const fixture = createInstalledLifecycleFixture();
  try {
    const install = runLauncher(fixture, ["install", ...fixture.clientArgs]);
    assert.equal(install.status, 0, install.stderr);

    const config = readFileSync(fixture.configPath, "utf8");
    assert.match(config, new RegExp(`command = "${escapeRegExp(fixture.stableLauncherPath)}"`));
    assert.match(config, /args = \["mcp"\]/);
    assert.equal(readlinkSync(fixture.userSkillDirectory), fixture.stableSkillDirectory);
    assert.doesNotMatch(`${install.stdout}\n${install.stderr}`, /\b(?:git|npm|swift|tsc)\b/);

    fixture.simulateUpgrade();

    const check = runLauncher(fixture, ["check", ...fixture.clientArgs]);
    assert.equal(check.status, 0, check.stderr ?? check.error?.message);

    const uninstall = runLauncher(fixture, ["uninstall", ...fixture.clientArgs]);
    assert.equal(uninstall.status, 0, uninstall.stderr ?? uninstall.error?.message);
    assert.doesNotMatch(readFileSync(fixture.configPath, "utf8"), /mcp_servers\.astrolabe/);
  } finally {
    fixture.cleanup();
  }
});

function createInstalledLifecycleFixture() {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-installed-lifecycle-"));
  const realRoot = realpathSync(root);
  const projectRoot = join(root, "project");
  const homebrewPrefix = join(realRoot, "homebrew");
  const formulaRoot = join(homebrewPrefix, "Cellar", "astrolabe", "2.0.0");
  const outputRoot = join(formulaRoot, "libexec");
  const configPath = join(root, "codex", "config.toml");
  const userSkillDirectory = join(root, "skills", "astrolabe");

  cpSync(join(repositoryRoot, "scripts", "distribution"), join(projectRoot, "scripts", "distribution"), {
    recursive: true
  });
  cpSync(join(repositoryRoot, "scripts", "installation"), join(projectRoot, "scripts", "installation"), {
    recursive: true
  });
  cpSync(join(repositoryRoot, "skills", "astrolabe"), join(projectRoot, "skills", "astrolabe"), {
    recursive: true
  });
  cpSync(
    join(repositoryRoot, "node_modules", "jsonc-parser"),
    join(projectRoot, "node_modules", "jsonc-parser"),
    { recursive: true }
  );
  mkdirSync(join(projectRoot, ".build", "release"), { recursive: true });
  mkdirSync(join(projectRoot, "mcp-adapter", "dist"), { recursive: true });
  writeFileSync(join(projectRoot, ".build", "release", "astrolabe"), "native fixture\n");
  chmodSync(join(projectRoot, ".build", "release", "astrolabe"), 0o755);
  writeFileSync(join(projectRoot, "mcp-adapter", "dist", "index.js"), "export {};\n");
  writeFileSync(join(projectRoot, "mcp-adapter", "package.json"), "{\"type\":\"module\"}\n");
  writeFileSync(join(projectRoot, "mcp-adapter", "package-lock.json"), "{\"lockfileVersion\":3}\n");
  cpSync(join(repositoryRoot, "LICENSE"), join(projectRoot, "LICENSE"));
  cpSync(join(repositoryRoot, "THIRD_PARTY_NOTICES"), join(projectRoot, "THIRD_PARTY_NOTICES"));

  assembleDistribution({
    projectRoot,
    outputRoot,
    version: "2.0.0",
    channel: "homebrew",
    platform: "darwin",
    architecture: "arm64"
  }, {
    readArchitectures: () => ["arm64"],
    installProductionDependencies: () => {}
  });
  const paths = distributionPaths(realpathSync(outputRoot));
  const optFormulaRoot = join(homebrewPrefix, "opt", "astrolabe");
  mkdirSync(dirname(optFormulaRoot), { recursive: true });
  symlinkSync(formulaRoot, optFormulaRoot);
  const stableLauncherPath = join(homebrewPrefix, "bin", "astrolabe");
  mkdirSync(dirname(stableLauncherPath), { recursive: true });
  symlinkSync(join(optFormulaRoot, "libexec", "bin", "astrolabe"), stableLauncherPath);

  return {
    paths,
    stableLauncherPath,
    stableSkillDirectory: join(optFormulaRoot, "libexec", "skills", "astrolabe"),
    configPath,
    clientArgs: [
      "--client",
      "codex",
      "--user-skill-dir",
      userSkillDirectory,
      "--client-config",
      `codex=${configPath}`
    ],
    userSkillDirectory,
    simulateUpgrade() {
      const upgradedFormulaRoot = join(homebrewPrefix, "Cellar", "astrolabe", "2.0.1");
      cpSync(formulaRoot, upgradedFormulaRoot, { recursive: true, verbatimSymlinks: true });
      rmSync(optFormulaRoot);
      symlinkSync(upgradedFormulaRoot, optFormulaRoot);
      rmSync(formulaRoot, { recursive: true, force: true });
    },
    cleanup() {
      rmSync(root, { recursive: true, force: true });
    }
  };
}

function runLauncher(fixture, args) {
  return spawnSync(fixture.stableLauncherPath, args, {
    encoding: "utf8"
  });
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}
