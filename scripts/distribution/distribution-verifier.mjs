import { distributionManifestRuntimePaths } from "./distribution-manifest.mjs";

/**
 * @typedef {Object} DistributionVerificationContext
 * @property {import("./distribution-layout.mjs").DistributionPaths} paths - Resolved Distribution paths.
 * @property {import("./distribution-manifest.mjs").DistributionManifest} manifest - Parsed Distribution manifest.
 * @property {(path: string) => boolean} pathExists - File existence check.
 * @property {(path: string) => boolean} isExecutable - Executable permission check.
 */

/**
 * @param {DistributionVerificationContext} context
 * @returns {string[]}
 */
export function distributionValidationProblems(context) {
  const requiredFiles = [
    [context.paths.manifestPath, "Distribution manifest"],
    [context.paths.publicLauncherPath, "Launcher"],
    [context.paths.nativeExecutablePath, "Native CLI"],
    [context.paths.mcpEntryPath, "MCP adapter"],
    [context.paths.skillPath, "Astrolabe skill"],
    [context.paths.licensePath, "LICENSE"],
    [context.paths.thirdPartyNoticesPath, "THIRD_PARTY_NOTICES"]
  ];
  const problems = requiredFiles.flatMap(([path, label]) => (
    context.pathExists(path) ? [] : [`${label} not found: ${path}`]
  ));

  for (const [path, label] of [
    [context.paths.publicLauncherPath, "Launcher"],
    [context.paths.nativeExecutablePath, "Native CLI"]
  ]) {
    if (context.pathExists(path) && !context.isExecutable(path)) {
      problems.push(`${label} is not executable: ${path}`);
    }
  }
  if (context.manifest.nativeExecutable !== distributionManifestRuntimePaths.nativeExecutable) {
    problems.push("Native executable path does not match the Distribution layout");
  }
  if (context.manifest.mcpEntry !== distributionManifestRuntimePaths.mcpEntry) {
    problems.push("MCP entry path does not match the Distribution layout");
  }
  return problems;
}
