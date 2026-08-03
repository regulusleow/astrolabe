import { spawnSync } from "node:child_process";
import {
  chmodSync,
  copyFileSync,
  cpSync,
  existsSync,
  lstatSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  symlinkSync
} from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";

import { distributionPaths } from "./distribution-layout.mjs";
import {
  createDistributionManifest,
  readDistributionManifest,
  writeDistributionManifest
} from "./distribution-manifest.mjs";

export const runtimeInstallationPaths = Object.freeze([
  "ai-client-detector.mjs",
  "ai-client-registry.mjs",
  "clients",
  "command-runner.mjs",
  "doctor",
  "install-command.mjs",
  "install-options.mjs",
  "installation-orchestrator.mjs",
  "jsonc-config-editor.mjs",
  "managed-config-file.mjs",
  "managed-skill-link.mjs"
]);

const runtimeDistributionPaths = Object.freeze([
  "distribution-layout.mjs",
  "distribution-manifest.mjs",
  "distribution-verifier.mjs"
]);

/**
 * @typedef {Object} SourcePaths
 * @property {string} root - Absolute Astrolabe source root.
 * @property {string} nativeExecutablePath - Built release Swift executable.
 * @property {string} mcpDistDirectory - Compiled MCP Adapter directory.
 * @property {string} mcpEntryPath - Compiled MCP Adapter entry point.
 * @property {string} mcpPackageJsonPath - MCP Adapter package manifest.
 * @property {string} mcpPackageLockPath - MCP Adapter dependency lock file.
 * @property {string} launcherPath - Stable launcher source module.
 * @property {string} distributionModulesDirectory - Runtime Distribution module source directory.
 * @property {string} installationDirectory - Runtime client-management source directory.
 * @property {string} jsoncParserDirectory - Root JSONC parser production dependency.
 * @property {string} skillDirectory - Astrolabe Skill source directory.
 * @property {string} skillPath - Astrolabe SKILL.md source path.
 * @property {string} licensePath - Apache-2.0 LICENSE source path.
 * @property {string} thirdPartyNoticesPath - Required third-party attribution source path.
 * @property {string} noticePath - Optional Apache NOTICE source path.
 */

/**
 * @typedef {Object} AssemblyOptions
 * @property {string} projectRoot - Astrolabe source root containing completed build outputs.
 * @property {string} outputRoot - Final Distribution output directory.
 * @property {string} version - Stable Astrolabe semantic version.
 * @property {"source"|"homebrew"} channel - Distribution owner channel.
 * @property {"darwin"} platform - Distribution operating-system platform.
 * @property {"arm64"|"x86_64"} architecture - Required native executable architecture.
 */

/**
 * @typedef {Object} AssemblyDependencies
 * @property {(binaryPath: string) => string[]} readArchitectures - Reads native architectures from a built executable.
 * @property {(mcpAdapterDirectory: string) => void} installProductionDependencies - Installs locked MCP production dependencies.
 */

/**
 * @typedef {Object} AssemblyResult
 * @property {string} root - Absolute assembled Distribution root.
 * @property {import("./distribution-manifest.mjs").DistributionManifest} manifest - Validated Distribution manifest.
 */

/**
 * @param {AssemblyOptions} options
 * @param {Partial<AssemblyDependencies>} [dependencyOverrides]
 * @returns {AssemblyResult}
 */
export function assembleDistribution(options, dependencyOverrides = {}) {
  const dependencies = {
    readArchitectures: readArchitecturesWithLipo,
    installProductionDependencies,
    ...dependencyOverrides
  };
  const projectRoot = resolve(options.projectRoot);
  const outputRoot = resolve(options.outputRoot);
  const source = sourcePaths(projectRoot);
  assertSafeOutputRoot(outputRoot, projectRoot);
  const manifest = createDistributionManifest({
    version: options.version,
    channel: options.channel,
    platform: options.platform,
    architecture: options.architecture
  });

  validateSourceArtifacts(source);
  assertSkillMetadata(source.skillPath);
  const architectures = dependencies.readArchitectures(source.nativeExecutablePath);
  if (architectures.length !== 1 || architectures[0] !== options.architecture) {
    throw new Error(
      `Failed: native architecture mismatch: expected ${options.architecture}, found ${architectures.join(", ") || "none"}`
    );
  }
  assertReplaceableOutput(outputRoot);

  const stagingRoot = `${outputRoot}.staging-${process.pid}-${Date.now()}`;
  const staging = distributionPaths(stagingRoot);
  try {
    copyRuntimeFiles(source, staging);
    dependencies.installProductionDependencies(staging.mcpAdapterDirectory);
    writeDistributionManifest(staging.root, manifest);
    replaceDistribution(staging.root, outputRoot);
    return Object.freeze({ root: outputRoot, manifest });
  } catch (error) {
    rmSync(staging.root, { recursive: true, force: true });
    throw error;
  }
}

function assertSafeOutputRoot(outputRoot, projectRoot) {
  const projectRelativePath = relative(outputRoot, projectRoot);
  const containsProject = !projectRelativePath.startsWith("..") && !isAbsolute(projectRelativePath);
  if (outputRoot === "/" || outputRoot === resolve(homedir()) || containsProject) {
    throw new Error(`Failed: unsafe Distribution output directory: ${outputRoot}`);
  }
}

function assertReplaceableOutput(outputRoot) {
  if (!existsSync(outputRoot)) {
    return;
  }
  const stat = lstatSync(outputRoot);
  if (stat.isSymbolicLink() || !stat.isDirectory()) {
    throw new Error(`Failed: Distribution output must be a regular directory: ${outputRoot}`);
  }
  try {
    readDistributionManifest(outputRoot);
  } catch {
    throw new Error(`Failed: Distribution output directory is not managed by Astrolabe: ${outputRoot}`);
  }
}

/** @returns {SourcePaths} */
function sourcePaths(projectRoot) {
  return Object.freeze({
    root: projectRoot,
    nativeExecutablePath: join(projectRoot, ".build", "release", "astrolabe"),
    mcpDistDirectory: join(projectRoot, "mcp-adapter", "dist"),
    mcpEntryPath: join(projectRoot, "mcp-adapter", "dist", "index.js"),
    mcpPackageJsonPath: join(projectRoot, "mcp-adapter", "package.json"),
    mcpPackageLockPath: join(projectRoot, "mcp-adapter", "package-lock.json"),
    launcherPath: join(projectRoot, "scripts", "distribution", "launcher.mjs"),
    distributionModulesDirectory: join(projectRoot, "scripts", "distribution"),
    installationDirectory: join(projectRoot, "scripts", "installation"),
    jsoncParserDirectory: join(projectRoot, "node_modules", "jsonc-parser"),
    skillDirectory: join(projectRoot, "skills", "astrolabe"),
    skillPath: join(projectRoot, "skills", "astrolabe", "SKILL.md"),
    licensePath: join(projectRoot, "LICENSE"),
    thirdPartyNoticesPath: join(projectRoot, "THIRD_PARTY_NOTICES"),
    noticePath: join(projectRoot, "NOTICE")
  });
}

function validateSourceArtifacts(source) {
  const requiredPaths = [
    source.nativeExecutablePath,
    source.mcpDistDirectory,
    source.mcpEntryPath,
    source.mcpPackageJsonPath,
    source.mcpPackageLockPath,
    source.launcherPath,
    source.skillDirectory,
    source.skillPath,
    source.licensePath,
    source.thirdPartyNoticesPath,
    source.jsoncParserDirectory,
    ...runtimeDistributionPaths.map((path) => join(source.distributionModulesDirectory, path)),
    ...runtimeInstallationPaths.map((path) => join(source.installationDirectory, path))
  ];
  for (const path of requiredPaths) {
    if (!existsSync(path)) {
      throw new Error(`Failed: required Distribution artifact not found: ${path}`);
    }
  }
}

function copyRuntimeFiles(source, staging) {
  mkdirSync(dirname(staging.publicLauncherPath), { recursive: true });
  mkdirSync(dirname(staging.launcherModulePath), { recursive: true });
  mkdirSync(staging.installationDirectory, { recursive: true });

  copyFileSync(source.launcherPath, staging.launcherModulePath);
  chmodSync(staging.launcherModulePath, 0o755);
  symlinkSync("../libexec/astrolabe-launcher.mjs", staging.publicLauncherPath);

  copyFileSync(source.nativeExecutablePath, staging.nativeExecutablePath);
  chmodSync(staging.nativeExecutablePath, 0o755);

  cpSync(source.mcpDistDirectory, join(staging.mcpAdapterDirectory, "dist"), { recursive: true });
  copyFileSync(source.mcpPackageJsonPath, join(staging.mcpAdapterDirectory, "package.json"));
  copyFileSync(source.mcpPackageLockPath, join(staging.mcpAdapterDirectory, "package-lock.json"));

  for (const path of runtimeDistributionPaths) {
    const destination = join(staging.root, "distribution", path);
    mkdirSync(dirname(destination), { recursive: true });
    copyFileSync(join(source.distributionModulesDirectory, path), destination);
  }
  for (const path of runtimeInstallationPaths) {
    cpSync(join(source.installationDirectory, path), join(staging.installationDirectory, path), {
      recursive: true
    });
  }
  cpSync(
    source.jsoncParserDirectory,
    join(staging.installationDirectory, "node_modules", "jsonc-parser"),
    { recursive: true }
  );

  cpSync(source.skillDirectory, staging.skillDirectory, { recursive: true });
  copyFileSync(source.licensePath, staging.licensePath);
  copyFileSync(source.thirdPartyNoticesPath, staging.thirdPartyNoticesPath);
  if (existsSync(source.noticePath)) {
    copyFileSync(source.noticePath, staging.noticePath);
  }
}

function assertSkillMetadata(skillPath) {
  const source = readFileSync(skillPath, "utf8");
  const frontmatter = source.match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/)?.[1];
  if (!frontmatter) {
    throw new Error(`Failed: Astrolabe skill metadata is missing YAML frontmatter: ${skillPath}`);
  }
  const metadata = new Map();
  for (const line of frontmatter.split(/\r?\n/)) {
    const separator = line.indexOf(":");
    if (separator > 0) {
      metadata.set(line.slice(0, separator).trim(), line.slice(separator + 1).trim());
    }
  }
  if (metadata.get("name") !== "astrolabe") {
    throw new Error(`Failed: Astrolabe skill metadata name must be astrolabe: ${skillPath}`);
  }
  if (!(metadata.get("description") ?? "").startsWith("Use when ")) {
    throw new Error(`Failed: Astrolabe skill metadata description must start with Use when: ${skillPath}`);
  }
}

function replaceDistribution(stagingRoot, outputRoot) {
  const backupRoot = `${outputRoot}.backup-${process.pid}-${Date.now()}`;
  const hadExistingOutput = existsSync(outputRoot);
  if (hadExistingOutput) {
    renameSync(outputRoot, backupRoot);
  }
  try {
    renameSync(stagingRoot, outputRoot);
  } catch (error) {
    if (hadExistingOutput && existsSync(backupRoot)) {
      renameSync(backupRoot, outputRoot);
    }
    throw error;
  }
  rmSync(backupRoot, { recursive: true, force: true });
}

function readArchitecturesWithLipo(binaryPath) {
  const result = spawnSync("/usr/bin/lipo", ["-archs", binaryPath], { encoding: "utf8" });
  if (result.status !== 0) {
    const detail = String(result.stderr || result.error?.message || "unknown error").trim();
    throw new Error(`Failed: could not read native executable architecture: ${detail}`);
  }
  return result.stdout.trim().split(/\s+/).filter(Boolean);
}

function installProductionDependencies(mcpAdapterDirectory) {
  const result = spawnSync("npm", ["ci", "--omit=dev"], {
    cwd: mcpAdapterDirectory,
    encoding: "utf8",
    stdio: ["ignore", "ignore", "pipe"]
  });
  if (result.status !== 0) {
    const detail = String(result.stderr || result.error?.message || "unknown error").trim();
    throw new Error(`Failed: MCP production dependency installation failed: ${detail}`);
  }
}
