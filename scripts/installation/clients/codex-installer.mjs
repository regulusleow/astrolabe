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
    packagePaths,
    skillDirectories,
    dryRun
  }) {
    this.id = "codex";
    this.configPath = configPath;
    this.serverName = serverName;
    this.packagePaths = packagePaths;
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
    if (!hasCodexServerConfig(configText, this.serverName)) {
      problems.push(`Codex configuration is missing [mcp_servers.${this.serverName}]`);
    }
    if (!configText.includes(this.packagePaths.mcpEntryPath)) {
      problems.push(`Codex configuration does not point to the MCP adapter: ${this.packagePaths.mcpEntryPath}`);
    }
    if (!configText.includes(this.packagePaths.inspectorBinPath)) {
      problems.push(`Codex configuration does not point to the CLI binary: ${this.packagePaths.inspectorBinPath}`);
    }
    const skillPaths = [
      this.packagePaths.skillPath,
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
    let result = removeCodexSkillConfig(configText, this.packagePaths.skillPath);
    for (const skillDirectory of this.skillDirectories) {
      result = removeCodexSkillConfig(result, join(skillDirectory, "SKILL.md"));
    }
    return result;
  }

  #serverConfig() {
    return {
      serverName: this.serverName,
      mcpEntryPath: this.packagePaths.mcpEntryPath,
      inspectorBinPath: this.packagePaths.inspectorBinPath
    };
  }
}

export function renderCodexServerConfig({
  serverName,
  mcpEntryPath,
  inspectorBinPath
}) {
  validateServerName(serverName);
  return [
    `[mcp_servers.${serverName}]`,
    `command = "node"`,
    `args = [${tomlString(mcpEntryPath)}]`,
    `startup_timeout_sec = 30`,
    `tool_timeout_sec = 120`,
    ``,
    `[mcp_servers.${serverName}.env]`,
    `ASTROLABE_BIN = ${tomlString(inspectorBinPath)}`,
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
  const escapedName = serverName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`^\\s*\\[mcp_servers\\.${escapedName}]\\s*$`, "m").test(configText);
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
