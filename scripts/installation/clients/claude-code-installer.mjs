import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import {
  parseJSONCObject,
  removeJSONCEntry,
  upsertJSONCEntry
} from "../jsonc-config-editor.mjs";
import { writeManagedConfig } from "../managed-config-file.mjs";

const configurationName = "Claude Code";
const containerKey = "mcpServers";

export function defaultClaudeCodeConfigPath(environment = process.env, homeDirectory = homedir()) {
  const configDirectory = claudeCodeConfigDirectory(environment, homeDirectory);
  return environment.CLAUDE_CONFIG_DIR
    ? join(configDirectory, ".claude.json")
    : join(homeDirectory, ".claude.json");
}

export function defaultClaudeCodeSkillDirectory(environment = process.env, homeDirectory = homedir()) {
  return join(claudeCodeConfigDirectory(environment, homeDirectory), "skills", "astrolabe");
}

export class ClaudeCodeInstaller {
  constructor({
    configPath,
    serverName,
    distributionPaths,
    skillDirectories,
    dryRun
  }) {
    this.id = "claude-code";
    this.configPath = configPath;
    this.serverName = serverName;
    this.distributionPaths = distributionPaths;
    this.skillDirectories = skillDirectories;
    this.dryRun = dryRun;
  }

  install() {
    const currentText = existsSync(this.configPath) ? readFileSync(this.configPath, "utf8") : "";
    const nextText = upsertClaudeCodeServerConfig(currentText, this.#serverConfig());
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
    const nextText = removeClaudeCodeServerConfig(currentText, this.serverName);
    if (this.dryRun || currentText === nextText) {
      return;
    }
    writeManagedConfig(this.configPath, nextText);
  }

  check() {
    if (!existsSync(this.configPath)) {
      return [`Claude Code configuration not found: ${this.configPath}`];
    }
    let config;
    try {
      config = parseJSONCObject(readFileSync(this.configPath, "utf8"), configurationName);
    } catch (error) {
      return [error instanceof Error ? error.message.replace(/^Failed:\s*/, "") : String(error)];
    }
    const entry = config[containerKey]?.[this.serverName];
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      return [`Claude Code configuration is missing ${containerKey}.${this.serverName}`];
    }

    const problems = [];
    if (entry.type !== "stdio") {
      problems.push(`Claude Code MCP server must use stdio transport: ${this.serverName}`);
    }
    if (
      entry.command !== this.distributionPaths.publicLauncherPath
      || !Array.isArray(entry.args)
      || entry.args.length !== 1
      || entry.args[0] !== "mcp"
    ) {
      problems.push(`Claude Code configuration does not use the managed MCP command: ${this.serverName}`);
    }
    return problems;
  }

  isConfigured() {
    if (!existsSync(this.configPath)) {
      return false;
    }
    const config = parseJSONCObject(readFileSync(this.configPath, "utf8"), configurationName);
    return Boolean(config[containerKey]?.[this.serverName]);
  }

  #serverConfig() {
    return {
      serverName: this.serverName,
      launcherPath: this.distributionPaths.publicLauncherPath
    };
  }
}

export function renderClaudeCodeServerConfig({
  launcherPath
}) {
  return {
    type: "stdio",
    command: launcherPath,
    args: ["mcp"]
  };
}

export function upsertClaudeCodeServerConfig(configText, serverConfig) {
  return upsertJSONCEntry(configText, {
    configurationName,
    containerKey,
    entryKey: serverConfig.serverName,
    value: renderClaudeCodeServerConfig(serverConfig)
  });
}

export function removeClaudeCodeServerConfig(configText, serverName) {
  return removeJSONCEntry(configText, {
    configurationName,
    containerKey,
    entryKey: serverName
  });
}

function claudeCodeConfigDirectory(environment, homeDirectory) {
  const configuredDirectory = environment.CLAUDE_CONFIG_DIR;
  if (!configuredDirectory) {
    return join(homeDirectory, ".claude");
  }
  if (configuredDirectory === "~") {
    return homeDirectory;
  }
  if (configuredDirectory.startsWith("~/")) {
    return join(homeDirectory, configuredDirectory.slice(2));
  }
  return configuredDirectory;
}
