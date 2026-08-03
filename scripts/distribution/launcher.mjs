#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { distributionPaths } from "../distribution/distribution-layout.mjs";
import { readDistributionManifest } from "../distribution/distribution-manifest.mjs";

const managementCommandNames = new Set(["install", "uninstall", "check"]);

export const nativeCommandNames = new Set([
  "list-apps",
  "capture-hierarchy",
  "node-detail",
  "summarize-node-detail",
  "check-node-detail",
  "summarize-hierarchy",
  "inspect-screen",
  "find-nodes",
  "inspect-node",
  "check-node",
  "check-style",
  "check-layout",
  "capture-screenshot",
  "compare-screenshot",
  "inspect-diff",
  "record-baseline",
  "compare-baseline",
  "list-patchable-attributes",
  "apply-attribute-patch",
  "list-attribute-patches",
  "revert-attribute-patch",
  "clear-attribute-patches"
]);

/**
 * @typedef {Object} LauncherDependencies
 * @property {import("./distribution-layout.mjs").DistributionPaths} paths - Installed Distribution paths.
 * @property {{version: string}} manifest - Validated Distribution manifest.
 * @property {(command: string, args: string[], options: {stdio: "inherit", env?: Record<string, string|undefined>}) => {status: number|null, error?: Error}} spawn - Synchronous child runner.
 * @property {{write: (value: string) => void}} stdout - Standard output writer.
 * @property {{write: (value: string) => void}} stderr - Standard error writer.
 * @property {(command: string, args: string[]) => Promise<number>} runManagement - AI-client lifecycle runner.
 * @property {(args: string[]) => Promise<number>} runDoctor - Diagnostic command runner.
 */

/**
 * @param {string[]} argv
 * @param {LauncherDependencies} [dependencies]
 * @returns {Promise<number>}
 */
export async function runLauncher(argv, dependencies = defaultDependencies()) {
  const command = argv[0];
  if (!command || command === "help" || command === "--help" || command === "-h") {
    dependencies.stdout.write(helpText());
    return 0;
  }
  if (command === "version" || command === "--version") {
    dependencies.stdout.write(`${dependencies.manifest.version}\n`);
    return 0;
  }
  if (managementCommandNames.has(command)) {
    return dependencies.runManagement(command, argv.slice(1));
  }
  if (command === "doctor") {
    return dependencies.runDoctor(argv.slice(1));
  }
  if (command === "mcp") {
    return runChild(
      process.execPath,
      [dependencies.paths.mcpEntryPath, ...argv.slice(1)],
      dependencies,
      {
        ...process.env,
        ASTROLABE_BIN: dependencies.paths.nativeExecutablePath
      }
    );
  }
  if (nativeCommandNames.has(command)) {
    return runChild(dependencies.paths.nativeExecutablePath, argv, dependencies);
  }

  dependencies.stderr.write(`Unknown command: ${command}\n`);
  dependencies.stdout.write(helpText());
  return 2;
}

function runChild(command, args, dependencies, env) {
  const options = env ? { stdio: "inherit", env } : { stdio: "inherit" };
  const result = dependencies.spawn(command, args, options);
  if (typeof result.status === "number") {
    return result.status;
  }
  const detail = result.error instanceof Error ? result.error.message : "unknown error";
  dependencies.stderr.write(`Failed to start subprocess: ${detail}\n`);
  return 1;
}

function helpText() {
  return `Usage:
  astrolabe install --client <codex|opencode|claude-code>
  astrolabe uninstall --client <codex|opencode|claude-code>
  astrolabe check --client <codex|opencode|claude-code>
  astrolabe doctor [--verbose [--json]]
  astrolabe mcp
  astrolabe <inspection-command> [arguments]
`;
}

function defaultDependencies() {
  const launcherPath = realpathSync(fileURLToPath(import.meta.url));
  const distributionRoot = resolve(dirname(launcherPath), "..");
  const paths = distributionPaths(distributionRoot);
  const manifest = readDistributionManifest(distributionRoot);
  const publicLauncherPath = invokedPublicLauncherPath(paths);
  return {
    paths,
    manifest,
    spawn: spawnSync,
    stdout: process.stdout,
    stderr: process.stderr,
    async runManagement(command, args) {
      const module = await import("../installation/install-command.mjs");
      return module.runInstalledClientCommand(command, args, {
        distributionRoot,
        publicLauncherPath,
        publicDistributionRoot: invokedPublicDistributionRoot(
          distributionRoot,
          publicLauncherPath,
          manifest.channel
        )
      });
    },
    async runDoctor(args) {
      const module = await import("../installation/doctor/doctor-command.mjs");
      return module.runDoctor(args, {
        distributionRoot,
        publicLauncherPath,
        publicDistributionRoot: invokedPublicDistributionRoot(
          distributionRoot,
          publicLauncherPath,
          manifest.channel
        )
      });
    }
  };
}

function invokedPublicDistributionRoot(distributionRoot, publicLauncherPath, channel) {
  if (channel !== "homebrew") {
    return distributionRoot;
  }
  const homebrewPrefix = resolve(dirname(publicLauncherPath), "..");
  return resolve(homebrewPrefix, "opt", "astrolabe", "libexec");
}

function invokedPublicLauncherPath(paths) {
  const invocationPath = process.argv[1] ? resolve(process.argv[1]) : "";
  return invocationPath.endsWith("/astrolabe")
    ? invocationPath
    : paths.publicLauncherPath;
}

function isMainModule() {
  if (!process.argv[1]) {
    return false;
  }
  try {
    return realpathSync(process.argv[1]) === realpathSync(fileURLToPath(import.meta.url));
  } catch {
    return resolve(process.argv[1]) === resolve(fileURLToPath(import.meta.url));
  }
}

if (isMainModule()) {
  try {
    process.exitCode = await runLauncher(process.argv.slice(2));
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    process.stderr.write(`Command failed: ${detail}\n`);
    process.exitCode = 1;
  }
}
