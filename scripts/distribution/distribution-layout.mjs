import { join, resolve } from "node:path";

/**
 * @typedef {Object} DistributionPaths
 * @property {string} root - Absolute Distribution root.
 * @property {string} publicLauncherPath - Stable public command path inside bin.
 * @property {string} launcherModulePath - Node.js launcher module inside libexec.
 * @property {string} nativeExecutablePath - Native Swift executable inside libexec.
 * @property {string} mcpAdapterDirectory - MCP Adapter runtime directory.
 * @property {string} mcpEntryPath - Compiled MCP Adapter entry point.
 * @property {string} installationDirectory - Runtime client-management modules.
 * @property {string} skillDirectory - Packaged Astrolabe Skill directory.
 * @property {string} skillPath - Packaged Astrolabe SKILL.md.
 * @property {string} manifestPath - Distribution manifest JSON path.
 * @property {string} licensePath - Packaged LICENSE path.
 * @property {string} thirdPartyNoticesPath - Packaged third-party attribution and license notices.
 * @property {string} noticePath - Packaged NOTICE path.
 */

/** @returns {DistributionPaths} */
export function distributionPaths(root) {
  const resolvedRoot = resolve(root);
  return Object.freeze({
    root: resolvedRoot,
    publicLauncherPath: join(resolvedRoot, "bin", "astrolabe"),
    launcherModulePath: join(resolvedRoot, "libexec", "astrolabe-launcher.mjs"),
    nativeExecutablePath: join(resolvedRoot, "libexec", "astrolabe-native"),
    mcpAdapterDirectory: join(resolvedRoot, "libexec", "mcp-adapter"),
    mcpEntryPath: join(resolvedRoot, "libexec", "mcp-adapter", "dist", "index.js"),
    installationDirectory: join(resolvedRoot, "installation"),
    skillDirectory: join(resolvedRoot, "skills", "astrolabe"),
    skillPath: join(resolvedRoot, "skills", "astrolabe", "SKILL.md"),
    manifestPath: join(resolvedRoot, "distribution-manifest.json"),
    licensePath: join(resolvedRoot, "LICENSE"),
    thirdPartyNoticesPath: join(resolvedRoot, "THIRD_PARTY_NOTICES"),
    noticePath: join(resolvedRoot, "NOTICE")
  });
}
