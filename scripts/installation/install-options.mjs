import { homedir } from "node:os";
import { join } from "node:path";

/**
 * @typedef {Object} InstallOptions
 * @property {"install"|"check"|"uninstall"} action - Requested installation lifecycle action.
 * @property {"explicit"|"detected"|"configured"} clientSelection - Client selection strategy.
 * @property {string[]} clientIDs - Ordered, unique AI client identifiers selected by the user.
 * @property {string} packageDir - Installed Distribution root injected by the launcher.
 * @property {string} launcherPath - Stable public launcher path written to client configuration.
 * @property {string} publicDistributionRoot - Stable Distribution root used for persistent Skill links.
 * @property {string} userSkillDir - Shared agent-compatible Astrolabe skill link.
 * @property {string} serverName - MCP server identifier written to client configurations.
 * @property {boolean} dryRun - Whether side effects and external commands are disabled.
 * @property {boolean} help - Whether command help should be printed.
 * @property {Record<string, string>} clientConfigPaths - Optional configuration path overrides keyed by AI client identifier.
 */

export function parseInstallArgs(argv, defaults = {}) {
  const packageDir = defaults.packageDir ?? join(homedir(), ".astrolabe", "distributions", "source");
  /** @type {InstallOptions} */
  const options = {
    action: defaults.action ?? "install",
    clientSelection: "explicit",
    clientIDs: [],
    packageDir,
    launcherPath: defaults.launcherPath ?? join(packageDir, "bin", "astrolabe"),
    publicDistributionRoot: defaults.publicDistributionRoot ?? packageDir,
    userSkillDir: defaults.userSkillDir ?? join(homedir(), ".agents", "skills", "astrolabe"),
    serverName: defaults.serverName ?? "astrolabe",
    dryRun: false,
    help: false,
    clientConfigPaths: { ...(defaults.clientConfigPaths ?? {}) }
  };

  let requestedAllDetected = false;
  let requestedAllConfigured = false;
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--client":
        options.clientIDs.push(readOptionValue(argv, index, arg));
        index += 1;
        break;
      case "--all-detected":
        requestedAllDetected = true;
        break;
      case "--all-configured":
        requestedAllConfigured = true;
        break;
      case "--user-skill-dir":
        options.userSkillDir = expandHome(readOptionValue(argv, index, arg));
        index += 1;
        break;
      case "--client-config": {
        const override = parseClientConfigOverride(readOptionValue(argv, index, arg));
        options.clientConfigPaths[override.clientID] = override.configPath;
        index += 1;
        break;
      }
      case "--server-name":
        options.serverName = readOptionValue(argv, index, arg);
        index += 1;
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--help":
      case "-h":
        options.help = true;
        break;
      default:
        throw new Error(`Failed: unknown option: ${arg}`);
    }
  }

  options.clientIDs = [...new Set(options.clientIDs)];
  const selectionCount = Number(options.clientIDs.length > 0)
    + Number(requestedAllDetected)
    + Number(requestedAllConfigured);
  if (!options.help && selectionCount !== 1) {
    if (selectionCount === 0) {
      throw new Error("Failed: at least one --client is required");
    }
    throw new Error("Failed: choose exactly one client selection mode");
  }
  options.clientSelection = requestedAllDetected
    ? "detected"
    : requestedAllConfigured
      ? "configured"
      : "explicit";
  if (options.clientSelection === "detected" && options.action === "uninstall") {
    throw new Error("Failed: --all-detected is available only for install or check");
  }
  if (options.clientSelection === "configured" && options.action === "install") {
    throw new Error("Failed: --all-configured is available only for check or uninstall");
  }
  validateServerName(options.serverName);

  return options;
}

export function validateServerName(serverName) {
  if (!/^[A-Za-z0-9_-]+$/.test(serverName)) {
    throw new Error(`Failed: invalid MCP server name: ${serverName}`);
  }
}

function readOptionValue(argv, index, optionName) {
  const value = argv[index + 1];
  if (!value || value.startsWith("--")) {
    throw new Error(`Failed: missing value for ${optionName}`);
  }
  return value;
}

function parseClientConfigOverride(value) {
  const separator = value.indexOf("=");
  const clientID = separator > 0 ? value.slice(0, separator) : "";
  const configPath = separator > 0 ? value.slice(separator + 1) : "";
  if (!clientID || !configPath) {
    throw new Error("Failed: client configuration override must use <client>=<path>");
  }
  return {
    clientID,
    configPath: expandHome(configPath)
  };
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
