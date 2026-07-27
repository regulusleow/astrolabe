import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

import {
  parseJSONCObject,
  removeJSONCEntry,
  upsertJSONCEntry
} from "../jsonc-config-editor.mjs";
import { writeManagedConfig } from "../managed-config-file.mjs";

export function defaultOpenCodeConfigPath() {
  return process.env.OPENCODE_CONFIG
    ? expandHome(process.env.OPENCODE_CONFIG)
    : join(homedir(), ".config", "opencode", "opencode.json");
}

const configurationName = "OpenCode";
const containerKey = "mcp";

export class OpenCodeInstaller {
  constructor({
    configPath,
    serverName,
    packagePaths,
    skillDirectories,
    dryRun
  }) {
    this.id = "opencode";
    this.configPath = configPath;
    this.serverName = serverName;
    this.packagePaths = packagePaths;
    this.skillDirectories = skillDirectories;
    this.dryRun = dryRun;
  }

  install() {
    const currentText = existsSync(this.configPath) ? readFileSync(this.configPath, "utf8") : "";
    const nextText = upsertOpenCodeServerConfig(currentText, this.#serverConfig());
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
    const nextText = removeOpenCodeServerConfig(currentText, this.serverName);
    if (this.dryRun || currentText === nextText) {
      return;
    }
    writeManagedConfig(this.configPath, nextText);
  }

  check() {
    if (!existsSync(this.configPath)) {
      return [`OpenCode configuration not found: ${this.configPath}`];
    }
    let config;
    try {
      config = parseJSONCObject(readFileSync(this.configPath, "utf8"), configurationName);
    } catch (error) {
      return [error instanceof Error ? error.message.replace(/^Failed:\s*/, "") : String(error)];
    }
    const entry = config[containerKey]?.[this.serverName];
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      return [`OpenCode configuration is missing mcp.${this.serverName}`];
    }

    const problems = [];
    if (entry.type !== "local") {
      problems.push(`OpenCode MCP server must use local transport: ${this.serverName}`);
    }
    if (
      !Array.isArray(entry.command)
      || entry.command.length !== 2
      || entry.command[0] !== "node"
      || entry.command[1] !== this.packagePaths.mcpEntryPath
    ) {
      problems.push(`OpenCode configuration does not point to the MCP adapter: ${this.packagePaths.mcpEntryPath}`);
    }
    if (entry.environment?.ASTROLABE_BIN !== this.packagePaths.inspectorBinPath) {
      problems.push(`OpenCode configuration does not point to the CLI binary: ${this.packagePaths.inspectorBinPath}`);
    }
    if (entry.enabled !== true) {
      problems.push(`OpenCode MCP server must be enabled: ${this.serverName}`);
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
      mcpEntryPath: this.packagePaths.mcpEntryPath,
      inspectorBinPath: this.packagePaths.inspectorBinPath
    };
  }
}

export function renderOpenCodeServerConfig({
  mcpEntryPath,
  inspectorBinPath
}) {
  return {
    type: "local",
    command: ["node", mcpEntryPath],
    enabled: true,
    environment: {
      ASTROLABE_BIN: inspectorBinPath
    },
    timeout: 120000
  };
}

export function upsertOpenCodeServerConfig(configText, serverConfig) {
  return upsertJSONCEntry(configText, {
    configurationName,
    containerKey,
    entryKey: serverConfig.serverName,
    value: renderOpenCodeServerConfig(serverConfig)
  });
}

export function removeOpenCodeServerConfig(configText, serverName) {
  return removeJSONCEntry(configText, {
    configurationName,
    containerKey,
    entryKey: serverName
  });
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
