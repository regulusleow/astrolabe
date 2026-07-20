import { resolve } from "node:path";

/**
 * @typedef {Object} SourceArtifactPaths
 * @property {string} inspectorBuildPath - Release Swift CLI produced by the source build.
 * @property {string} mcpDistDir - Compiled MCP adapter output directory.
 * @property {string} mcpEntryPath - Compiled MCP stdio server entry point.
 * @property {string} mcpPackageJsonPath - MCP adapter runtime package manifest.
 * @property {string} mcpPackageLockPath - MCP adapter locked runtime dependencies.
 * @property {string} skillDir - Source Astrolabe skill directory.
 * @property {string} skillPath - Source Astrolabe SKILL.md path.
 */

/**
 * @typedef {Object} PackageArtifactPaths
 * @property {string} inspectorBinPath - Installed Swift CLI executable.
 * @property {string} mcpAdapterDir - Installed MCP adapter package directory.
 * @property {string} mcpDistDir - Installed compiled MCP adapter directory.
 * @property {string} mcpEntryPath - Installed MCP stdio server entry point.
 * @property {string} mcpPackageJsonPath - Installed MCP package manifest.
 * @property {string} mcpPackageLockPath - Installed MCP dependency lock file.
 * @property {string} skillDir - Installed shared Astrolabe skill directory.
 * @property {string} skillPath - Installed shared Astrolabe SKILL.md path.
 */

/** @returns {SourceArtifactPaths} */
export function sourceArtifactPaths(projectRoot) {
  return {
    inspectorBuildPath: resolve(projectRoot, ".build/release/astrolabe"),
    mcpDistDir: resolve(projectRoot, "mcp-adapter/dist"),
    mcpEntryPath: resolve(projectRoot, "mcp-adapter/dist/index.js"),
    mcpPackageJsonPath: resolve(projectRoot, "mcp-adapter/package.json"),
    mcpPackageLockPath: resolve(projectRoot, "mcp-adapter/package-lock.json"),
    skillDir: resolve(projectRoot, "skills/astrolabe"),
    skillPath: resolve(projectRoot, "skills/astrolabe/SKILL.md")
  };
}

/** @returns {PackageArtifactPaths} */
export function packageArtifactPaths(packageDir) {
  return {
    inspectorBinPath: resolve(packageDir, "bin/astrolabe"),
    mcpAdapterDir: resolve(packageDir, "mcp-adapter"),
    mcpDistDir: resolve(packageDir, "mcp-adapter/dist"),
    mcpEntryPath: resolve(packageDir, "mcp-adapter/dist/index.js"),
    mcpPackageJsonPath: resolve(packageDir, "mcp-adapter/package.json"),
    mcpPackageLockPath: resolve(packageDir, "mcp-adapter/package-lock.json"),
    skillDir: resolve(packageDir, "skills/astrolabe"),
    skillPath: resolve(packageDir, "skills/astrolabe/SKILL.md")
  };
}
