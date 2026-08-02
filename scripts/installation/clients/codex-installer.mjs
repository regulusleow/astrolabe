import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import { validateServerName } from "../install-options.mjs";
import { writeManagedConfig } from "../managed-config-file.mjs";

export function defaultCodexConfigPath() {
  return process.env.CODEX_HOME
    ? join(process.env.CODEX_HOME, "config.toml")
    : join(homedir(), ".codex", "config.toml");
}

export class CodexInstaller {
  constructor({
    configPath,
    serverName,
    distributionPaths,
    skillDirectories,
    dryRun
  }) {
    this.id = "codex";
    this.configPath = configPath;
    this.serverName = serverName;
    this.distributionPaths = distributionPaths;
    this.skillDirectories = skillDirectories;
    this.dryRun = dryRun;
  }

  install() {
    const currentText = existsSync(this.configPath) ? readFileSync(this.configPath, "utf8") : "";
    const nextText = this.#removeLegacySkillEntries(upsertCodexServerConfig(
      currentText,
      this.#serverConfig()
    ));
    if (this.dryRun || currentText === nextText) {
      return;
    }
    writeManagedConfig(this.configPath, nextText);
  }

  uninstall() {
    if (!existsSync(this.configPath)) {
      return;
    }
    const currentText = readFileSync(this.configPath, "utf8");
    const nextText = this.#removeLegacySkillEntries(
      removeCodexServerConfig(currentText, this.serverName)
    );
    if (this.dryRun || currentText === nextText) {
      return;
    }
    writeManagedConfig(this.configPath, nextText);
  }

  check() {
    if (!existsSync(this.configPath)) {
      return [`Codex configuration not found: ${this.configPath}`];
    }
    const configText = readFileSync(this.configPath, "utf8");
    const problems = [];
    const serverSection = codexServerSection(configText, this.serverName);
    if (!serverSection) {
      problems.push(`Codex configuration is missing [mcp_servers.${this.serverName}]`);
    } else if (!codexSectionUsesLauncher(
      serverSection,
      this.distributionPaths.publicLauncherPath
    )) {
      problems.push(`Codex configuration does not use the managed MCP launcher: ${this.distributionPaths.publicLauncherPath}`);
    }
    const skillPaths = [
      this.distributionPaths.skillPath,
      ...this.skillDirectories.map((directory) => join(directory, "SKILL.md"))
    ];
    if (skillPaths.some((skillPath) => configText.includes(skillPath))) {
      problems.push("Codex configuration still contains legacy skills.config entries");
    }
    return problems;
  }

  isConfigured() {
    if (!existsSync(this.configPath)) {
      return false;
    }
    return hasCodexServerConfig(readFileSync(this.configPath, "utf8"), this.serverName);
  }

  #removeLegacySkillEntries(configText) {
    let result = removeCodexSkillConfig(configText, this.distributionPaths.skillPath);
    for (const skillDirectory of this.skillDirectories) {
      result = removeCodexSkillConfig(result, join(skillDirectory, "SKILL.md"));
    }
    return result;
  }

  #serverConfig() {
    return {
      serverName: this.serverName,
      launcherPath: this.distributionPaths.publicLauncherPath
    };
  }
}

export function renderCodexServerConfig({
  serverName,
  launcherPath
}) {
  validateServerName(serverName);
  return [
    `[mcp_servers.${serverName}]`,
    `command = ${tomlString(launcherPath)}`,
    `args = ["mcp"]`,
    `startup_timeout_sec = 30`,
    `tool_timeout_sec = 120`,
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

function hasCodexServerConfig(configText, serverName) {
  return codexServerSection(configText, serverName) !== null;
}

function codexServerSection(configText, serverName) {
  const escapedName = serverName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const headingPattern = new RegExp(`^\\s*\\[mcp_servers\\.${escapedName}]\\s*$`);
  const lines = configText.split(/\r?\n/);
  const startIndex = lines.findIndex((line) => headingPattern.test(line));
  if (startIndex < 0) {
    return null;
  }
  const endOffset = lines.slice(startIndex + 1).findIndex((line) => /^\s*\[/.test(line));
  const endIndex = endOffset < 0 ? lines.length : startIndex + 1 + endOffset;
  return lines.slice(startIndex + 1, endIndex);
}

function codexSectionUsesLauncher(lines, launcherPath) {
  const commandLine = lines.find((line) => /^\s*command\s*=/.test(line));
  const argsLine = lines.find((line) => /^\s*args\s*=/.test(line));
  try {
    const command = JSON.parse(commandLine?.split("=").slice(1).join("=").trim() ?? "null");
    const args = JSON.parse(argsLine?.split("=").slice(1).join("=").trim() ?? "null");
    return command === launcherPath
      && Array.isArray(args)
      && args.length === 1
      && args[0] === "mcp";
  } catch {
    return false;
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
