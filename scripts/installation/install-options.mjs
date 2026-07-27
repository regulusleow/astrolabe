import { homedir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const defaultProjectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

/**
 * @typedef {Object} InstallOptions
 * @property {"install"|"check"|"uninstall"} action - Requested installation lifecycle action.
 * @property {string[]} clientIDs - Ordered, unique AI client identifiers selected by the user.
 * @property {string} projectRoot - Astrolabe source directory used for builds.
 * @property {string} packageDir - Shared installed runtime package directory.
 * @property {string} userSkillDir - Shared agent-compatible Astrolabe skill link.
 * @property {string} serverName - MCP server identifier written to client configurations.
 * @property {string} repoUrl - Optional Git repository used to update the source checkout.
 * @property {string} installDir - Source checkout directory used with repoUrl.
 * @property {boolean} dryRun - Whether side effects and external commands are disabled.
 * @property {boolean} help - Whether command help should be printed.
 * @property {Record<string, string>} clientConfigPaths - Optional configuration path overrides keyed by AI client identifier.
 */

export function parseInstallArgs(argv, defaults = {}) {
  /** @type {InstallOptions} */
  const options = {
    action: "install",
    clientIDs: [],
    projectRoot: defaults.projectRoot ?? defaultProjectRoot,
    packageDir: defaults.packageDir ?? join(homedir(), ".astrolabe", "package"),
    userSkillDir: defaults.userSkillDir ?? join(homedir(), ".agents", "skills", "astrolabe"),
    serverName: defaults.serverName ?? "astrolabe",
    repoUrl: "",
    installDir: "",
    dryRun: false,
    help: false,
    clientConfigPaths: { ...(defaults.clientConfigPaths ?? {}) }
  };

  let requestedCheck = false;
  let requestedUninstall = false;
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    switch (arg) {
      case "--client":
        options.clientIDs.push(readOptionValue(argv, index, arg));
        index += 1;
        break;
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
      case "--check":
        requestedCheck = true;
        break;
      case "--uninstall":
        requestedUninstall = true;
        break;
      case "--help":
      case "-h":
        options.help = true;
        break;
      default:
        throw new Error(`Failed: unknown option: ${arg}`);
    }
  }

  if (requestedCheck && requestedUninstall) {
    throw new Error("Failed: --check and --uninstall cannot be used together");
  }
  options.action = requestedCheck ? "check" : requestedUninstall ? "uninstall" : "install";
  options.clientIDs = [...new Set(options.clientIDs)];
  if (!options.help && options.clientIDs.length === 0) {
    throw new Error("Failed: at least one --client is required");
  }
  validateServerName(options.serverName);

  if (options.repoUrl && !options.installDir) {
    options.installDir = join(homedir(), ".astrolabe", "source");
  }
  if (options.repoUrl) {
    options.projectRoot = options.installDir;
  }
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
