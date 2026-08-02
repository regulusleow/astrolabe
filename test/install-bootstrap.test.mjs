import test from "node:test";
import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  ensureInstallerDependencies,
  runSourceInstaller
} from "../scripts/install.mjs";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

test("installer bootstrap skips npm ci when dependencies are available", () => {
  const commands = [];

  ensureInstallerDependencies({
    resolveDependency: () => "/tmp/node_modules/jsonc-parser/package.json",
    runCommand: (...args) => commands.push(args)
  });

  assert.deepEqual(commands, []);
});

test("installer bootstrap restores locked dependencies for a fresh clone", () => {
  const commands = [];
  let attempts = 0;

  ensureInstallerDependencies({
    resolveDependency() {
      attempts += 1;
      if (attempts === 1) {
        const error = new Error("missing dependency");
        error.code = "MODULE_NOT_FOUND";
        throw error;
      }
      return "/tmp/node_modules/jsonc-parser/package.json";
    },
    runCommand(command, args, options) {
      commands.push({ command, args, options });
    }
  });

  assert.deepEqual(commands, [{
    command: "npm",
    args: ["ci", "--ignore-scripts"],
    options: { cwd: projectRoot }
  }]);
  assert.equal(attempts, 2);
});

test("installer bootstrap does not hide dependency resolution failures", () => {
  assert.throws(
    () => ensureInstallerDependencies({
      resolveDependency() {
        const error = new Error("invalid package metadata");
        error.code = "ERR_INVALID_PACKAGE_CONFIG";
        throw error;
      },
      runCommand: () => assert.fail("npm ci must not run for unrelated failures")
    }),
    /invalid package metadata/
  );
});

test("source installer builds only for install and invokes the assembled launcher", () => {
  const calls = [];

  const exitCode = runSourceInstaller([
    "--client",
    "codex",
    "--package-dir",
    "/tmp/astrolabe-source-distribution"
  ], {
    projectRoot,
    architecture: "arm64",
    ensureDependencies: () => calls.push({ type: "dependencies" }),
    buildDistribution: (options) => {
      calls.push({ type: "build", options });
      return { root: options.outputRoot };
    },
    runLauncher: (launcherPath, args) => {
      calls.push({ type: "launcher", launcherPath, args });
      return 0;
    }
  });

  assert.equal(exitCode, 0);
  assert.deepEqual(calls, [
    { type: "dependencies" },
    {
      type: "build",
      options: {
        projectRoot,
        outputRoot: "/tmp/astrolabe-source-distribution",
        version: "2.0.0",
        channel: "source",
        platform: "darwin",
        architecture: "arm64"
      }
    },
    {
      type: "launcher",
      launcherPath: "/tmp/astrolabe-source-distribution/bin/astrolabe",
      args: ["install", "--client", "codex"]
    }
  ]);
});

test("source installer check uses the existing Distribution without rebuilding", () => {
  const calls = [];

  const exitCode = runSourceInstaller([
    "--client",
    "codex",
    "--check",
    "--package-dir",
    "/tmp/astrolabe-source-distribution"
  ], {
    projectRoot,
    architecture: "arm64",
    ensureDependencies: () => assert.fail("check must not install source dependencies"),
    buildDistribution: () => assert.fail("check must not build a Distribution"),
    runLauncher: (launcherPath, args) => {
      calls.push({ launcherPath, args });
      return 0;
    }
  });

  assert.equal(exitCode, 0);
  assert.deepEqual(calls, [{
    launcherPath: "/tmp/astrolabe-source-distribution/bin/astrolabe",
    args: ["check", "--client", "codex"]
  }]);
});

test("source installer rejects removed Git source options", () => {
  assert.throws(
    () => runSourceInstaller(["--client", "codex", "--repo", "https://example.com/repo.git"]),
    /source acquisition is outside the installer/
  );
});
