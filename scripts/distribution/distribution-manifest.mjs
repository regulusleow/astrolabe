import { mkdirSync, readFileSync, writeFileSync } from "node:fs";

import { distributionPaths } from "./distribution-layout.mjs";

const schemaVersion = 1;
const stableVersionPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const allowedChannels = new Set(["homebrew", "source"]);
const allowedArchitectures = new Set(["arm64", "x86_64"]);
const allowedFields = new Set([
  "schemaVersion",
  "version",
  "channel",
  "platform",
  "architecture",
  "nativeExecutable",
  "mcpEntry"
]);

/**
 * @typedef {Object} DistributionManifestRuntimePaths
 * @property {"libexec/astrolabe-native"} nativeExecutable - Relative native CLI path.
 * @property {"libexec/mcp-adapter/dist/index.js"} mcpEntry - Relative MCP Adapter entry path.
 */

/** @type {DistributionManifestRuntimePaths} */
export const distributionManifestRuntimePaths = Object.freeze({
  nativeExecutable: "libexec/astrolabe-native",
  mcpEntry: "libexec/mcp-adapter/dist/index.js"
});

/**
 * @typedef {Object} DistributionManifestInput
 * @property {string} version - Stable Astrolabe Host semantic version.
 * @property {"homebrew"|"source"} channel - Package channel that owns the Distribution.
 * @property {"darwin"} platform - Supported operating-system platform.
 * @property {"arm64"|"x86_64"} architecture - Native executable architecture.
 * @property {"libexec/astrolabe-native"} nativeExecutable - Relative native CLI path.
 * @property {"libexec/mcp-adapter/dist/index.js"} mcpEntry - Relative MCP Adapter entry path.
 */

/**
 * @typedef {Object} DistributionManifest
 * @property {1} schemaVersion - Distribution manifest schema version.
 * @property {string} version - Stable Astrolabe Host semantic version.
 * @property {"homebrew"|"source"} channel - Package channel that owns the Distribution.
 * @property {"darwin"} platform - Supported operating-system platform.
 * @property {"arm64"|"x86_64"} architecture - Native executable architecture.
 */

/**
 * @param {DistributionManifestInput} input
 * @returns {DistributionManifest}
 */
export function createDistributionManifest(input) {
  return validateDistributionManifest({
    schemaVersion,
    ...input,
    ...distributionManifestRuntimePaths
  });
}

/**
 * @param {string} root
 * @param {DistributionManifest} manifest
 */
export function writeDistributionManifest(root, manifest) {
  const validated = validateDistributionManifest(manifest);
  const paths = distributionPaths(root);
  mkdirSync(paths.root, { recursive: true });
  writeFileSync(paths.manifestPath, `${JSON.stringify(validated, null, 2)}\n`, {
    mode: 0o644
  });
}

/**
 * @param {string} root
 * @returns {DistributionManifest}
 */
export function readDistributionManifest(root) {
  const path = distributionPaths(root).manifestPath;
  let value;
  try {
    value = JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    throw new Error(`Failed: unable to read distribution manifest: ${detail}`);
  }
  return validateDistributionManifest(value);
}

/**
 * @param {unknown} value
 * @returns {DistributionManifest}
 */
function validateDistributionManifest(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Failed: distribution manifest must be an object");
  }

  for (const field of Object.keys(value)) {
    if (!allowedFields.has(field)) {
      throw new Error(`Failed: unknown distribution manifest field: ${field}`);
    }
  }

  if (value.schemaVersion !== schemaVersion) {
    throw new Error(`Failed: unsupported distribution manifest schema: ${value.schemaVersion ?? "missing"}`);
  }
  if (typeof value.version !== "string" || !stableVersionPattern.test(value.version)) {
    throw new Error(`Failed: invalid distribution version: ${value.version ?? "missing"}`);
  }
  if (!allowedChannels.has(value.channel)) {
    throw new Error(`Failed: unsupported distribution channel: ${value.channel ?? "missing"}`);
  }
  if (value.platform !== "darwin") {
    throw new Error(`Failed: unsupported distribution platform: ${value.platform ?? "missing"}`);
  }
  if (!allowedArchitectures.has(value.architecture)) {
    throw new Error(`Failed: unsupported distribution architecture: ${value.architecture ?? "missing"}`);
  }
  if (value.nativeExecutable !== distributionManifestRuntimePaths.nativeExecutable) {
    throw new Error(`Failed: invalid native executable path: ${value.nativeExecutable ?? "missing"}`);
  }
  if (value.mcpEntry !== distributionManifestRuntimePaths.mcpEntry) {
    throw new Error(`Failed: invalid MCP entry path: ${value.mcpEntry ?? "missing"}`);
  }

  return Object.freeze({
    schemaVersion,
    version: value.version,
    channel: value.channel,
    platform: value.platform,
    architecture: value.architecture,
    nativeExecutable: value.nativeExecutable,
    mcpEntry: value.mcpEntry
  });
}
