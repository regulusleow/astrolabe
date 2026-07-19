#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { chmodSync, copyFileSync, cpSync, existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, renameSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const defaultProjectRoot = resolve(dirname(scriptPath), "..");
const defaultServerName = "astrolabe";
const packageMarkerName = ".astrolabe-package";

export function parseInstallArgs(argv, defaults = {}) {
  const options = {
    projectRoot: defaults.projectRoot ?? defaultProjectRoot,
    configPath: defaults.configPath ?? defaultCodexConfigPath(),
    serverName: defaults.serverName ?? defaultServerName,
    packageDir: defaults.packageDir ?? defaultPackageDir(),
    userSkillDir: defaults.userSkillDir ?? defaultUserSkillDir(),
    repoUrl: "",
    installDir: "",
    dryRun: false,
    check: false,
    uninstall: false,
    help: false
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--repo":
      case "--git":
        options.repoUrl = readOptionValue(argv, index, arg);
        index += 1;
        break;
      case "--install-dir":
        options.installDir = expandHome(readOptionValue(argv, index, arg));
        index += 1;
        break;
      case "--package-dir":
        options.packageDir = expandHome(readOptionValue(argv, index, arg));
        index += 1;
        break;
      case "--skill-dir":
      case "--user-skill-dir":
        options.userSkillDir = expandHome(readOptionValue(argv, index, arg));
        index += 1;
        break;
      case "--config":
      case "--codex-config":
        options.configPath = expandHome(readOptionValue(argv, index, arg));
        index += 1;
        break;
      case "--server-name":
        options.serverName = readOptionValue(argv, index, arg);
        index += 1;
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--check":
        options.check = true;
        break;
      case "--uninstall":
        options.uninstall = true;
        break;
      case "--help":
      case "-h":
        options.help = true;
        break;
      default:
        throw new Error(`Failed: unknown option: ${arg}`);
    }
  }

  validateServerName(options.serverName);
  if (options.check && options.uninstall) {
    throw new Error("Failed: --check and --uninstall cannot be used together");
  }
  if (options.repoUrl && !options.installDir) {
    options.installDir = join(homedir(), ".astrolabe", "source");
  }
  if (options.repoUrl) {
    options.projectRoot = options.installDir;
  }
  return options;
}

export function renderCodexServerConfig({
  serverName,
  mcpEntryPath,
  inspectorBinPath
}) {
  validateServerName(serverName);
  const environment = [
    `ASTROLABE_BIN = ${tomlString(inspectorBinPath)}`
  ];
  return [
    `[mcp_servers.${serverName}]`,
    `command = "node"`,
    `args = [${tomlString(mcpEntryPath)}]`,
    `startup_timeout_sec = 30`,
    `tool_timeout_sec = 120`,
    ``,
    `[mcp_servers.${serverName}.env]`,
    ...environment,
    ``
  ].join("\n");
}

export function upsertCodexServerConfig(configText, serverConfig) {
  const cleanedText = removeCodexServerConfig(configText, serverConfig.serverName).trimEnd();
  const block = renderCodexServerConfig(serverConfig).trimEnd();
  return `${cleanedText ? `${cleanedText}\n\n` : ""}${block}\n`;
}

export function removeCodexServerConfig(configText, serverName) {
  validateServerName(serverName);
  const removedSections = new Set([
    `mcp_servers.${serverName}`,
    `mcp_servers.${serverName}.env`
  ]);
  const lines = configText.split(/\r?\n/);
  const keptLines = [];
  let isSkipping = false;

  for (const line of lines) {
    const heading = line.match(/^\s*\[([^\]]+)]\s*$/);
    if (heading) {
      isSkipping = removedSections.has(heading[1].trim());
      if (!isSkipping) {
        keptLines.push(line);
      }
      continue;
    }
    if (!isSkipping) {
      keptLines.push(line);
    }
  }

  return normalizeTrailingNewline(keptLines.join("\n").replace(/\n{3,}/g, "\n\n"));
}

export function removeCodexSkillConfig(configText, skillPath) {
  const lines = configText.split(/\r?\n/);
  const keptLines = [];
  let currentSkillBlock = null;

  const flushSkillBlock = () => {
    if (!currentSkillBlock) {
      return;
    }
    if (!skillBlockContainsPath(currentSkillBlock, skillPath)) {
      keptLines.push(...currentSkillBlock);
    }
    currentSkillBlock = null;
  };

  for (const line of lines) {
    if (/^\s*(?:\[\[[^\]]+]]|\[[^\]]+])\s*$/.test(line)) {
      flushSkillBlock();
      if (/^\s*\[\[skills\.config]]\s*$/.test(line)) {
        currentSkillBlock = [line];
      } else {
        keptLines.push(line);
      }
      continue;
    }
    if (currentSkillBlock) {
      currentSkillBlock.push(line);
    } else {
      keptLines.push(line);
    }
  }
  flushSkillBlock();

  return normalizeTrailingNewline(keptLines.join("\n").replace(/\n{3,}/g, "\n\n"));
}

export function artifactPaths(projectRoot) {
  return packageArtifactPaths(projectRoot);
}

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

export function userSkillPaths(userSkillDir = defaultUserSkillDir()) {
  return {
    skillDir: resolve(userSkillDir),
    skillPath: resolve(userSkillDir, "SKILL.md")
  };
}

function defaultCodexConfigPath() {
  return process.env.CODEX_HOME
    ? join(process.env.CODEX_HOME, "config.toml")
    : join(homedir(), ".codex", "config.toml");
}

function defaultPackageDir() {
  return join(homedir(), ".astrolabe", "package");
}

function defaultUserSkillDir() {
  return join(homedir(), ".agents", "skills", "astrolabe");
}

function readOptionValue(argv, index, optionName) {
  const value = argv[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`Failed: missing value for ${optionName}`);
  }
  return value;
}

function expandHome(value) {
  if (value === "~") {
    return homedir();
  }
  if (value.startsWith("~/")) {
    return join(homedir(), value.slice(2));
  }
  return value;
}

function validateServerName(serverName) {
  if (!/^[A-Za-z0-9_-]+$/.test(serverName)) {
    throw new Error(`Failed: invalid Codex MCP server name: ${serverName}`);
  }
}

function tomlString(value) {
  return JSON.stringify(value);
}

function skillBlockContainsPath(lines, skillPath) {
  return lines.some((line) => {
    const match = line.match(/^\s*path\s*=\s*(".*")\s*$/);
    if (!match) {
      return false;
    }
    try {
      return JSON.parse(match[1]) === skillPath;
    } catch {
      return false;
    }
  });
}

function normalizeTrailingNewline(text) {
  const trimmed = text.trimEnd();
  return trimmed ? `${trimmed}\n` : "";
}

function printHelp() {
  console.log(`Usage:
  npm run install:codex
  npm run install:codex -- --repo https://github.com/regulusleow/astrolabe.git
  astrolabe-codex-install
  astrolabe-codex-install --check
  astrolabe-codex-install --uninstall

Options:
  --repo, --git <url>          Clone or update the specified Git repository before installation
  --install-dir <path>         Source checkout directory for --repo; defaults to ~/.astrolabe/source
  --package-dir <path>         Local runtime package directory; defaults to ~/.astrolabe/package
  --skill-dir <path>           Codex user skill link; defaults to ~/.agents/skills/astrolabe
  --config <path>              Codex config.toml path; defaults to ~/.codex/config.toml
  --server-name <name>         Codex MCP server name; defaults to astrolabe
  --check                      Verify the binary, MCP adapter, skill link, and Codex configuration
  --uninstall                  Remove only Codex MCP configuration and the user skill link
  --dry-run                    Print planned actions without writing files or running commands
`);
}

function ensureGitSource(options) {
  if (!options.repoUrl) {
    return;
  }

  const installDir = resolve(options.installDir);
  if (options.dryRun && !existsSync(installDir)) {
    runCommand("git", ["clone", options.repoUrl, installDir], { dryRun: true });
    return;
  }
  if (existsSync(installDir)) {
    if (!existsSync(join(installDir, ".git"))) {
      throw new Error(`Failed: installation directory exists but is not a Git repository: ${installDir}`);
    }
    runCommand("git", ["-C", installDir, "pull", "--ff-only"], { dryRun: options.dryRun });
    return;
  }

  mkdirSync(dirname(installDir), { recursive: true });
  runCommand("git", ["clone", options.repoUrl, installDir], { dryRun: options.dryRun });
}

function installProject(options) {
  const projectRoot = resolve(options.projectRoot);
  if (!options.dryRun) {
    assertProjectRoot(projectRoot);
  }
  runCommand("npm", ["--prefix", "mcp-adapter", "ci"], { cwd: projectRoot, dryRun: options.dryRun });
  runCommand("npm", ["--prefix", "mcp-adapter", "run", "build"], { cwd: projectRoot, dryRun: options.dryRun });
  runCommand("swift", ["build", "-c", "release", "--product", "astrolabe"], { cwd: projectRoot, dryRun: options.dryRun });
}

export function installRuntimePackage(options, commandRunner = runCommand) {
  const projectRoot = resolve(options.projectRoot);
  const packageDir = resolve(options.packageDir);
  const sourcePaths = sourceArtifactPaths(projectRoot);
  const packagePaths = packageArtifactPaths(packageDir);

  assertSafePackageDir(packageDir, projectRoot);

  if (options.dryRun) {
    console.log(`Would package: ${sourcePaths.inspectorBuildPath} -> ${packagePaths.inspectorBinPath}`);
    console.log(`Would package: ${sourcePaths.mcpDistDir} -> ${packagePaths.mcpDistDir}`);
    console.log(`Would package: ${sourcePaths.mcpPackageJsonPath} -> ${packagePaths.mcpPackageJsonPath}`);
    console.log(`Would package: ${sourcePaths.mcpPackageLockPath} -> ${packagePaths.mcpPackageLockPath}`);
    console.log(`Would package: ${sourcePaths.skillDir} -> ${packagePaths.skillDir}`);
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

function installUserSkillLink(options) {
  const packagePaths = packageArtifactPaths(resolve(options.packageDir));
  const userPaths = userSkillPaths(options.userSkillDir);

  if (options.dryRun) {
    console.log(`Would link skill: ${userPaths.skillDir} -> ${packagePaths.skillDir}`);
    return;
  }

  assertFileExists(packagePaths.skillPath, "Astrolabe skill not found in the local runtime package");
  mkdirSync(dirname(userPaths.skillDir), { recursive: true });
  replaceManagedSkillLink(userPaths.skillDir, packagePaths.skillDir);
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

function samePath(left, right) {
  return resolve(left) === resolve(right);
}

function replaceManagedSkillLink(linkPath, targetPath) {
  if (existsSync(linkPath)) {
    const stat = lstatSync(linkPath);
    if (!stat.isSymbolicLink()) {
      throw new Error(`Failed: Codex skill directory exists and is not a symbolic link: ${linkPath}`);
    }
    unlinkSync(linkPath);
  }
  symlinkSync(targetPath, linkPath, "dir");
}

function removeManagedSkillLink(userSkillDir, packageSkillDir) {
  if (!existsSync(userSkillDir)) {
    return false;
  }
  const stat = lstatSync(userSkillDir);
  if (!stat.isSymbolicLink()) {
    return false;
  }
  if (realpathSync(userSkillDir) !== realpathSync(packageSkillDir)) {
    return false;
  }
  unlinkSync(userSkillDir);
  return true;
}

export function assertSafePackageDir(packageDir, projectRoot = defaultProjectRoot) {
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
  const isDefaultPackageDir = samePath(resolvedPackageDir, defaultPackageDir());
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

function configureCodex(options) {
  const paths = packageArtifactPaths(resolve(options.packageDir));
  const userPaths = userSkillPaths(options.userSkillDir);
  const serverConfig = {
    serverName: options.serverName,
    mcpEntryPath: paths.mcpEntryPath,
    inspectorBinPath: paths.inspectorBinPath
  };
  const currentText = existsSync(options.configPath) ? readFileSync(options.configPath, "utf8") : "";
  const nextText = removeCodexSkillConfig(
    removeCodexSkillConfig(upsertCodexServerConfig(currentText, serverConfig), paths.skillPath),
    userPaths.skillPath
  );

  if (options.dryRun) {
    console.log(nextText);
    return;
  }
  if (currentText === nextText) {
    console.log(`Codex configuration is already up to date: ${options.configPath}`);
    return;
  }

  mkdirSync(dirname(options.configPath), { recursive: true });
  if (existsSync(options.configPath)) {
    copyFileSync(options.configPath, `${options.configPath}.astrolabe.bak`);
  }
  writeFileSync(options.configPath, nextText);
  console.log(`Updated Codex MCP configuration: ${options.configPath}`);
}

function uninstallCodexConfig(options) {
  const currentText = existsSync(options.configPath) ? readFileSync(options.configPath, "utf8") : "";
  const packagePaths = packageArtifactPaths(resolve(options.packageDir));
  const userPaths = userSkillPaths(options.userSkillDir);
  const nextText = removeCodexSkillConfig(
    removeCodexSkillConfig(removeCodexServerConfig(currentText, options.serverName), packagePaths.skillPath),
    userPaths.skillPath
  );
  if (options.dryRun) {
    console.log(nextText);
    return;
  }
  removeManagedSkillLink(userPaths.skillDir, packagePaths.skillDir);
  if (currentText === nextText) {
    console.log(`Codex configuration has no ${options.serverName} MCP entry: ${options.configPath}`);
    return;
  }
  copyFileSync(options.configPath, `${options.configPath}.astrolabe.bak`);
  writeFileSync(options.configPath, nextText);
  console.log(`Removed Codex MCP configuration and user skill link: ${options.configPath}`);
}

function checkInstallation(options) {
  const paths = packageArtifactPaths(resolve(options.packageDir));
  const userPaths = userSkillPaths(options.userSkillDir);
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
    appendSkillMetadataProblem(paths.skillPath, problems);
  }
  if (!existsSync(userPaths.skillPath)) {
    problems.push(`User-level Astrolabe skill not found: ${userPaths.skillPath}`);
  } else if (realpathSync(userPaths.skillDir) !== realpathSync(paths.skillDir)) {
    problems.push(`User-level Astrolabe skill does not point to the local runtime package: ${userPaths.skillDir}`);
  } else {
    appendSkillMetadataProblem(userPaths.skillPath, problems);
  }
  if (!existsSync(options.configPath)) {
    problems.push(`Codex configuration not found: ${options.configPath}`);
  } else {
    const configText = readFileSync(options.configPath, "utf8");
    if (!configText.includes(`[mcp_servers.${options.serverName}]`)) {
      problems.push(`Codex configuration is missing [mcp_servers.${options.serverName}]`);
    }
    if (!configText.includes(paths.mcpEntryPath)) {
      problems.push(`Codex configuration does not point to the MCP adapter: ${paths.mcpEntryPath}`);
    }
    if (!configText.includes(paths.inspectorBinPath)) {
      problems.push(`Codex configuration does not point to the CLI binary: ${paths.inspectorBinPath}`);
    }
    if (configText.includes(paths.skillPath) || configText.includes(userPaths.skillPath)) {
      problems.push("Codex configuration still contains legacy skills.config; skills must be discovered through ~/.agents/skills");
    }
  }

  if (problems.length > 0) {
    for (const problem of problems) {
      console.error(`Failed: ${problem}`);
    }
    process.exitCode = 1;
    return;
  }
  console.log("Codex local installation check passed");
}

function appendSkillMetadataProblem(skillPath, problems) {
  try {
    assertSkillMetadata(skillPath);
  } catch (error) {
    problems.push(error instanceof Error ? error.message.replace(/^Failed:\s*/, "") : String(error));
  }
}

function runCommand(command, args, options = {}) {
  const cwd = options.cwd ?? process.cwd();
  const displayCommand = [command, ...args].join(" ");
  if (options.dryRun) {
    console.log(`Would run: ${displayCommand}`);
    return;
  }
  const result = spawnSync(command, args, {
    cwd,
    stdio: "inherit",
    env: process.env
  });
  if (result.error) {
    throw new Error(`Failed: unable to start command: ${displayCommand}: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`Failed: command failed: ${displayCommand}`);
  }
}

async function main() {
  try {
    const options = parseInstallArgs(process.argv.slice(2));
    if (options.help) {
      printHelp();
      return;
    }
    if (options.uninstall) {
      uninstallCodexConfig(options);
      return;
    }
    if (options.check) {
      checkInstallation(options);
      return;
    }
    ensureGitSource(options);
    installProject(options);
    installRuntimePackage(options);
    installUserSkillLink(options);
    configureCodex(options);
    if (options.dryRun) {
      console.log("Dry run completed without installing or writing Codex configuration.");
    } else {
      console.log("Installation completed. Restart Codex or open a new Codex session before using the Astrolabe MCP server.");
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith("Failed:") ? message : `Failed: ${message}`);
    process.exitCode = 1;
  }
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
  await main();
}
