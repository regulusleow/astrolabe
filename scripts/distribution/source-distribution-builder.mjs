import { spawnSync } from "node:child_process";

import { assembleDistribution } from "./distribution-assembler.mjs";

/**
 * @typedef {Object} SourceDistributionBuildOptions
 * @property {string} projectRoot - Astrolabe source root to build.
 * @property {string} outputRoot - Final Distribution output directory.
 * @property {string} version - Stable Astrolabe semantic version.
 * @property {"source"|"homebrew"} channel - Distribution owner channel.
 * @property {"darwin"} platform - Distribution operating-system platform.
 * @property {"arm64"|"x86_64"} architecture - Required native executable architecture.
 */

/**
 * @typedef {Object} SourceBuildDependencies
 * @property {(command: string, args: string[], options: {cwd: string}) => void} runBuildCommand - Runs one required source-build command.
 * @property {typeof assembleDistribution} assemble - Assembles validated source outputs.
 */

/**
 * @param {SourceDistributionBuildOptions} options
 * @param {Partial<SourceBuildDependencies>} [dependencyOverrides]
 * @returns {import("./distribution-assembler.mjs").AssemblyResult}
 */
export function buildSourceDistribution(options, dependencyOverrides = {}) {
  const dependencies = {
    runBuildCommand,
    assemble: assembleDistribution,
    ...dependencyOverrides
  };
  dependencies.runBuildCommand("npm", ["--prefix", "mcp-adapter", "ci"], {
    cwd: options.projectRoot
  });
  dependencies.runBuildCommand("npm", ["--prefix", "mcp-adapter", "run", "build"], {
    cwd: options.projectRoot
  });
  dependencies.runBuildCommand("swift", ["build", "-c", "release", "--product", "astrolabe"], {
    cwd: options.projectRoot
  });
  return dependencies.assemble(options);
}

function runBuildCommand(command, args, options) {
  const result = spawnSync(command, args, { cwd: options.cwd, stdio: "inherit" });
  if (result.status !== 0) {
    const detail = result.error instanceof Error ? result.error.message : `exit code ${result.status ?? "unknown"}`;
    throw new Error(`Failed: build command failed (${command}): ${detail}`);
  }
}
