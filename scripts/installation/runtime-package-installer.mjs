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
  writeFileSync
} from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";

import { runCommand } from "./command-runner.mjs";
import { packageArtifactPaths, sourceArtifactPaths } from "./package-layout.mjs";

const packageMarkerName = ".astrolabe-package";

export function ensureGitSource(options, commandRunner = runCommand) {
  if (!options.repoUrl) {
    return;
  }

  const installDir = resolve(options.installDir);
  if (options.dryRun && !existsSync(installDir)) {
    commandRunner("git", ["clone", options.repoUrl, installDir], { dryRun: true });
    return;
  }
  if (existsSync(installDir)) {
    if (!existsSync(join(installDir, ".git"))) {
      throw new Error(`Failed: installation directory exists but is not a Git repository: ${installDir}`);
    }
    commandRunner("git", ["-C", installDir, "pull", "--ff-only"], { dryRun: options.dryRun });
    return;
  }

  mkdirSync(dirname(installDir), { recursive: true });
  commandRunner("git", ["clone", options.repoUrl, installDir], { dryRun: options.dryRun });
}

export function buildProject(options, commandRunner = runCommand) {
  const projectRoot = resolve(options.projectRoot);
  if (!options.dryRun) {
    assertProjectRoot(projectRoot);
  }
  commandRunner("npm", ["--prefix", "mcp-adapter", "ci"], {
    cwd: projectRoot,
    dryRun: options.dryRun
  });
  commandRunner("npm", ["--prefix", "mcp-adapter", "run", "build"], {
    cwd: projectRoot,
    dryRun: options.dryRun
  });
  commandRunner("swift", ["build", "-c", "release", "--product", "astrolabe"], {
    cwd: projectRoot,
    dryRun: options.dryRun
  });
}

export function installRuntimePackage(options, commandRunner = runCommand) {
  const projectRoot = resolve(options.projectRoot);
  const packageDir = resolve(options.packageDir);
  const sourcePaths = sourceArtifactPaths(projectRoot);
  const packagePaths = packageArtifactPaths(packageDir);

  assertSafePackageDir(packageDir, projectRoot);

  if (options.dryRun) {
    commandRunner("npm", ["ci", "--omit=dev"], {
      cwd: packagePaths.mcpAdapterDir,
      dryRun: true
    });
    return;
  }

  assertFileExists(sourcePaths.inspectorBuildPath, "Swift CLI release artifact not found");
  assertFileExists(sourcePaths.mcpEntryPath, "MCP adapter build artifact not found");
  assertFileExists(sourcePaths.mcpPackageJsonPath, "MCP adapter package.json not found");
  assertFileExists(sourcePaths.mcpPackageLockPath, "MCP adapter package-lock.json not found");
  assertFileExists(sourcePaths.skillPath, "Astrolabe skill not found");
  assertSkillMetadata(sourcePaths.skillPath);

  const stagingDir = `${packageDir}.staging-${process.pid}-${Date.now()}`;
  const stagingPaths = packageArtifactPaths(stagingDir);
  try {
    mkdirSync(dirname(stagingPaths.inspectorBinPath), { recursive: true });
    mkdirSync(stagingPaths.mcpAdapterDir, { recursive: true });
    copyFileSync(sourcePaths.inspectorBuildPath, stagingPaths.inspectorBinPath);
    chmodSync(stagingPaths.inspectorBinPath, 0o755);
    cpSync(sourcePaths.mcpDistDir, stagingPaths.mcpDistDir, { recursive: true });
    copyFileSync(sourcePaths.mcpPackageJsonPath, stagingPaths.mcpPackageJsonPath);
    copyFileSync(sourcePaths.mcpPackageLockPath, stagingPaths.mcpPackageLockPath);
    cpSync(sourcePaths.skillDir, stagingPaths.skillDir, { recursive: true });
    writeFileSync(join(stagingDir, packageMarkerName), "astrolabe managed package\n");
    commandRunner("npm", ["ci", "--omit=dev"], { cwd: stagingPaths.mcpAdapterDir });
    replaceRuntimePackage(stagingDir, packageDir);
  } catch (error) {
    rmSync(stagingDir, { recursive: true, force: true });
    throw error;
  }
}

export function checkRuntimePackage(packageDir) {
  const paths = packageArtifactPaths(resolve(packageDir));
  const problems = [];
  if (!existsSync(paths.inspectorBinPath)) {
    problems.push(`CLI binary not found: ${paths.inspectorBinPath}`);
  }
  if (!existsSync(paths.mcpEntryPath)) {
    problems.push(`MCP adapter not found: ${paths.mcpEntryPath}`);
  }
  if (!existsSync(paths.skillPath)) {
    problems.push(`Astrolabe skill not found: ${paths.skillPath}`);
  } else {
    try {
      assertSkillMetadata(paths.skillPath);
    } catch (error) {
      problems.push(error instanceof Error ? error.message.replace(/^Failed:\s*/, "") : String(error));
    }
  }
  return problems;
}

export function assertSkillMetadata(skillPath) {
  const source = readFileSync(skillPath, "utf8");
  const frontmatter = source.match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/)?.[1];
  if (!frontmatter) {
    throw new Error(`Failed: Astrolabe skill metadata is missing YAML frontmatter: ${skillPath}`);
  }
  const metadata = new Map();
  for (const line of frontmatter.split(/\r?\n/)) {
    const separator = line.indexOf(":");
    if (separator <= 0) {
      continue;
    }
    metadata.set(line.slice(0, separator).trim(), line.slice(separator + 1).trim());
  }
  if (metadata.get("name") !== "astrolabe") {
    throw new Error(`Failed: Astrolabe skill metadata name must be astrolabe: ${skillPath}`);
  }
  const description = metadata.get("description") ?? "";
  if (!description.startsWith("Use when ")) {
    throw new Error(`Failed: Astrolabe skill metadata description must start with Use when: ${skillPath}`);
  }
}

export function assertSafePackageDir(packageDir, projectRoot) {
  const resolvedPackageDir = resolve(packageDir);
  if (resolvedPackageDir === "/" || resolvedPackageDir === homedir()) {
    throw new Error(`Failed: unsafe local runtime package directory: ${resolvedPackageDir}`);
  }
  const projectRelativePath = relative(resolvedPackageDir, resolve(projectRoot));
  if (!projectRelativePath.startsWith("..") && !isAbsolute(projectRelativePath)) {
    throw new Error(`Failed: local runtime package directory cannot contain the source directory: ${resolvedPackageDir}`);
  }
  const packageRelativePath = relative(resolve(projectRoot), resolvedPackageDir);
  if (!packageRelativePath.startsWith("..") && !isAbsolute(packageRelativePath)) {
    throw new Error(`Failed: local runtime package directory cannot be inside the source directory: ${resolvedPackageDir}`);
  }
  if (!existsSync(resolvedPackageDir)) {
    return;
  }
  const stat = lstatSync(resolvedPackageDir);
  if (stat.isSymbolicLink() || !stat.isDirectory()) {
    throw new Error(`Failed: local runtime package path must be a regular directory: ${resolvedPackageDir}`);
  }
  const isDefaultPackageDir = resolvedPackageDir === resolve(homedir(), ".astrolabe", "package");
  if (!isDefaultPackageDir && !existsSync(join(resolvedPackageDir, packageMarkerName))) {
    throw new Error(`Failed: refusing to overwrite a directory not managed by Astrolabe: ${resolvedPackageDir}`);
  }
}

export function replaceRuntimePackage(stagingDir, packageDir) {
  const resolvedStagingDir = resolve(stagingDir);
  const resolvedPackageDir = resolve(packageDir);
  const backupDir = `${resolvedPackageDir}.backup-${process.pid}-${Date.now()}`;
  const hadExistingPackage = existsSync(resolvedPackageDir);

  if (hadExistingPackage) {
    renameSync(resolvedPackageDir, backupDir);
  }
  try {
    renameSync(resolvedStagingDir, resolvedPackageDir);
  } catch (error) {
    if (hadExistingPackage && existsSync(backupDir)) {
      renameSync(backupDir, resolvedPackageDir);
    }
    throw error;
  }
  rmSync(backupDir, { recursive: true, force: true });
}

function assertProjectRoot(projectRoot) {
  if (!existsSync(join(projectRoot, "Package.swift")) || !existsSync(join(projectRoot, "mcp-adapter/package.json"))) {
    throw new Error(`Failed: not an Astrolabe project directory: ${projectRoot}`);
  }
}

function assertFileExists(path, label) {
  if (!existsSync(path)) {
    throw new Error(`Failed: ${label}: ${path}`);
  }
}
