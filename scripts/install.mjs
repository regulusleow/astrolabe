#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { createRequire } from "node:module";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { distributionPaths } from "./distribution/distribution-layout.mjs";
import { buildSourceDistribution } from "./distribution/source-distribution-builder.mjs";
import { runCommand } from "./installation/command-runner.mjs";

const scriptPath = fileURLToPath(import.meta.url);
const projectRoot = resolve(dirname(scriptPath), "..");
const require = createRequire(import.meta.url);

/**
 * @typedef {Object} SourceInstallerDependencies
 * @property {string} projectRoot - Astrolabe source root.
 * @property {"arm64"|"x86_64"} architecture - Current build-machine architecture.
 * @property {() => void} ensureDependencies - Restores locked source bootstrap dependencies.
 * @property {typeof buildSourceDistribution} buildDistribution - Builds and assembles a source Distribution.
 * @property {(launcherPath: string, args: string[]) => number} runLauncher - Runs the assembled launcher and returns its exit status.
 */

/**
 * @typedef {Object} SourceInstallerArgs
 * @property {"install"|"check"|"uninstall"} action - Requested lifecycle action.
 * @property {string} outputRoot - Source Distribution directory selected by the developer entry point.
 * @property {string[]} launcherArgs - Client arguments forwarded to the installed launcher.
 */

export function ensureInstallerDependencies(dependencies = {}) {
  const resolveDependency = dependencies.resolveDependency ?? (() => require.resolve("jsonc-parser"));
  const commandRunner = dependencies.runCommand ?? runCommand;
  try {
    resolveDependency();
    return;
  } catch (error) {
    if (error?.code !== "MODULE_NOT_FOUND" && error?.code !== "ERR_MODULE_NOT_FOUND") {
      throw error;
    }
  }

  commandRunner("npm", ["ci", "--ignore-scripts"], { cwd: projectRoot });
  resolveDependency();
}

/**
 * @param {string[]} argv
 * @param {Partial<SourceInstallerDependencies>} [dependencyOverrides]
 * @returns {number}
 */
export function runSourceInstaller(argv, dependencyOverrides = {}) {
  const dependencies = {
    projectRoot,
    architecture: hostArchitecture(),
    ensureDependencies: ensureInstallerDependencies,
    buildDistribution: buildSourceDistribution,
    runLauncher: runLauncherProcess,
    ...dependencyOverrides
  };
  const parsed = parseSourceInstallerArgs(argv);
  const packageJson = JSON.parse(readFileSync(join(dependencies.projectRoot, "package.json"), "utf8"));

  if (parsed.action === "install") {
    dependencies.ensureDependencies();
    dependencies.buildDistribution({
      projectRoot: dependencies.projectRoot,
      outputRoot: parsed.outputRoot,
      version: packageJson.version,
      channel: "source",
      platform: "darwin",
      architecture: dependencies.architecture
    });
  }

  const launcherPath = distributionPaths(parsed.outputRoot).publicLauncherPath;
  return dependencies.runLauncher(launcherPath, [parsed.action, ...parsed.launcherArgs]);
}

/**
 * @param {string[]} argv
 * @returns {SourceInstallerArgs}
 */
export function parseSourceInstallerArgs(argv) {
  let action = "install";
  let outputRoot = join(homedir(), ".astrolabe", "distributions", "source");
  const launcherArgs = [];
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (["--repo", "--git", "--install-dir"].includes(arg)) {
      throw new Error("Failed: source acquisition is outside the installer");
    }
    if (arg === "--package-dir") {
      const value = argv[index + 1];
      if (!value || value.startsWith("--")) {
        throw new Error("Failed: missing value for --package-dir");
      }
      outputRoot = resolve(value);
      index += 1;
      continue;
    }
    if (arg === "--check" || arg === "--uninstall") {
      const requestedAction = arg === "--check" ? "check" : "uninstall";
      if (action !== "install") {
        throw new Error("Failed: --check and --uninstall cannot be used together");
      }
      action = requestedAction;
      continue;
    }
    launcherArgs.push(arg);
  }
  return Object.freeze({ action, outputRoot, launcherArgs: Object.freeze(launcherArgs) });
}

function hostArchitecture() {
  if (process.arch === "arm64") {
    return "arm64";
  }
  if (process.arch === "x64") {
    return "x86_64";
  }
  throw new Error(`Failed: unsupported host architecture: ${process.arch}`);
}

function runLauncherProcess(launcherPath, args) {
  if (!existsSync(launcherPath)) {
    throw new Error(`Failed: installed Astrolabe Launcher does not exist: ${launcherPath}`);
  }
  const result = spawnSync(launcherPath, args, { stdio: "inherit" });
  if (typeof result.status === "number") {
    return result.status;
  }
  const detail = result.error instanceof Error ? result.error.message : "unknown error";
  throw new Error(`Failed: Launcher startup failed: ${detail}`);
}

function isMainModule() {
  if (!process.argv[1]) {
    return false;
  }
  try {
    return realpathSync(process.argv[1]) === realpathSync(scriptPath);
  } catch {
    return resolve(process.argv[1]) === scriptPath;
  }
}

if (isMainModule()) {
  try {
    process.exitCode = runSourceInstaller(process.argv.slice(2));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`${message.startsWith("Failed:") ? message : `Failed: ${message}`}\n`);
    process.exitCode = 1;
  }
}
