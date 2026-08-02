import { accessSync, constants, existsSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";

import { defaultOpenCodeConfigPath } from "./clients/opencode-installer.mjs";

/**
 * @typedef {Object} AIClientDetectionInput
 * @property {string} homeDirectory - User home directory used for documented default paths.
 * @property {NodeJS.ProcessEnv} environment - Environment used for PATH and client overrides.
 * @property {(name: string) => boolean} commandExists - Executable lookup function.
 * @property {(path: string) => boolean} pathExists - Filesystem existence function.
 */

/**
 * @param {Partial<AIClientDetectionInput>} [input]
 * @returns {string[]}
 */
export function detectAIClients(input = {}) {
  const homeDirectory = input.homeDirectory ?? homedir();
  const environment = input.environment ?? process.env;
  const pathExists = input.pathExists ?? existsSync;
  const commandExists = input.commandExists ?? ((name) => executableExists(name, environment));
  const detected = [];

  if (commandExists("codex")
      || pathExists(environment.CODEX_HOME ?? join(homeDirectory, ".codex"))) {
    detected.push("codex");
  }
  if (commandExists("opencode")
      || pathExists(defaultOpenCodeConfigPath(environment, homeDirectory))
      || pathExists(join(homeDirectory, ".config", "opencode"))) {
    detected.push("opencode");
  }
  const claudeDirectory = environment.CLAUDE_CONFIG_DIR
    ?? join(homeDirectory, ".claude");
  if (commandExists("claude")
      || pathExists(claudeDirectory)
      || pathExists(join(homeDirectory, ".claude.json"))) {
    detected.push("claude-code");
  }
  return detected;
}

function executableExists(name, environment) {
  const pathValue = environment.PATH ?? "";
  for (const directory of pathValue.split(delimiter).filter(Boolean)) {
    try {
      accessSync(join(directory, name), constants.X_OK);
      return true;
    } catch {
      continue;
    }
  }
  return false;
}
