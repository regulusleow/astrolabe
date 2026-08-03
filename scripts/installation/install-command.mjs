import { accessSync, constants, existsSync } from "node:fs";

import { AIClientRegistry } from "./ai-client-registry.mjs";
import { detectAIClients } from "./ai-client-detector.mjs";
import {
  ClaudeCodeInstaller,
  defaultClaudeCodeConfigPath,
  defaultClaudeCodeSkillDirectory
} from "./clients/claude-code-installer.mjs";
import { CodexInstaller, defaultCodexConfigPath } from "./clients/codex-installer.mjs";
import { OpenCodeInstaller, defaultOpenCodeConfigPath } from "./clients/opencode-installer.mjs";
import { runInstallation } from "./installation-orchestrator.mjs";
import {
  checkManagedSkillLink,
  installManagedSkillLink,
  removeManagedSkillLink
} from "./managed-skill-link.mjs";
import { distributionPaths } from "../distribution/distribution-layout.mjs";
import { readDistributionManifest } from "../distribution/distribution-manifest.mjs";
import { distributionValidationProblems } from "../distribution/distribution-verifier.mjs";
import { parseInstallArgs } from "./install-options.mjs";

export function createAIClientRegistry(options, { validateSelection = true } = {}) {
  const installedPaths = distributionPaths(options.packageDir);
  const publicPaths = distributionPaths(options.publicDistributionRoot);
  const clientDistributionPaths = Object.freeze({
    ...installedPaths,
    publicLauncherPath: options.launcherPath,
    skillDirectory: publicPaths.skillDirectory,
    skillPath: publicPaths.skillPath
  });
  const sharedClientOptions = {
    serverName: options.serverName,
    distributionPaths: clientDistributionPaths,
    dryRun: options.dryRun
  };
  const registry = new AIClientRegistry([
    new CodexInstaller({
      ...sharedClientOptions,
      skillDirectories: [options.userSkillDir],
      configPath: options.clientConfigPaths.codex ?? defaultCodexConfigPath()
    }),
    new OpenCodeInstaller({
      ...sharedClientOptions,
      skillDirectories: [options.userSkillDir],
      configPath: options.clientConfigPaths.opencode ?? defaultOpenCodeConfigPath()
    }),
    new ClaudeCodeInstaller({
      ...sharedClientOptions,
      skillDirectories: [defaultClaudeCodeSkillDirectory()],
      configPath: options.clientConfigPaths["claude-code"] ?? defaultClaudeCodeConfigPath()
    })
  ]);
  if (validateSelection) {
    validateClientConfigOverrides(options, registry);
  }
  return registry;
}

export function resolveLifecycleClientIDs(options, registry, detectedIDs) {
  if (options.clientSelection === "explicit") {
    return options.clientIDs;
  }
  if (options.clientSelection === "detected") {
    if (detectedIDs.length === 0) {
      throw new Error("Failed: no supported AI clients detected");
    }
    return detectedIDs;
  }
  const configuredIDs = registry.all()
    .filter((client) => client.isConfigured())
    .map((client) => client.id);
  if (configuredIDs.length === 0) {
    throw new Error("Failed: no configured AI clients found");
  }
  return configuredIDs;
}

function validateClientConfigOverrides(options, registry) {
  const overrideClientIDs = Object.keys(options.clientConfigPaths);
  registry.resolve(overrideClientIDs);
  const selectedClientIDs = new Set(options.clientIDs);
  const unusedClientID = overrideClientIDs.find((clientID) => !selectedClientIDs.has(clientID));
  if (unusedClientID) {
    throw new Error(`Failed: --client-config provided for unselected AI client: ${unusedClientID}`);
  }
}

export function printHelp() {
  process.stdout.write(installationHelpText());
}

export function installationHelpText() {
  return `Usage:
  astrolabe install (--client <client> [--client <client>] | --all-detected)
  astrolabe check (--client <client> [--client <client>] | --all-detected | --all-configured)
  astrolabe uninstall (--client <client> [--client <client>] | --all-configured)

Options:
  --client <name>             Client: codex, opencode, or claude-code; repeat as needed
  --all-detected              Select every detected client for install or check
  --all-configured            Select every configured client for check or uninstall
  --user-skill-dir <path>     Shared agent-compatible Astrolabe skill link
  --client-config <id>=<path> Override one AI client's global configuration path
  --server-name <name>        MCP server name; defaults to astrolabe
  --dry-run                   Validate and print external commands without changing files
  --help                      Show this help
`;
}

export function executeInstallation(options) {
  if (options.help) {
    printHelp();
    return 0;
  }

  const installedPaths = distributionPaths(options.packageDir);
  const publicPaths = distributionPaths(options.publicDistributionRoot);
  const registry = createAIClientRegistry(options, { validateSelection: false });
  const clientIDs = resolveLifecycleClientIDs(
    options,
    registry,
    options.clientSelection === "detected" ? detectAIClients() : []
  );
  const resolvedOptions = { ...options, clientIDs };
  validateClientConfigOverrides(resolvedOptions, registry);
  runInstallation(resolvedOptions, {
    registry,
    preparePackage() {
      const problems = distributionProblems(installedPaths);
      if (problems.length > 0) {
        throw new Error(`Failed: Distribution validation failed:\n${problems.join("\n")}`);
      }
    },
    installSkillLink(skillDirectory) {
      installManagedSkillLink(skillDirectory, publicPaths.skillDirectory, options.dryRun);
    },
    removeSkillLink(skillDirectory) {
      removeManagedSkillLink(skillDirectory, publicPaths.skillDirectory, options.dryRun);
    },
    checkSharedInstallation(skillDirectories) {
      return [
        ...distributionProblems(installedPaths),
        ...skillDirectories.flatMap((skillDirectory) => (
          checkManagedSkillLink(skillDirectory, publicPaths.skillDirectory)
        ))
      ];
    }
  });

  if (options.dryRun) {
    process.stdout.write("Dry run completed without changing files.\n");
    return;
  }
  process.stdout.write(`${completionMessage(options.action)}: ${clientIDs.join(", ")}\n`);
  return 0;
}

function distributionProblems(paths) {
  let manifest;
  try {
    manifest = readDistributionManifest(paths.root);
  } catch (error) {
    return [error instanceof Error ? error.message : String(error)];
  }
  return distributionValidationProblems({
    paths,
    manifest,
    pathExists: existsSync,
    isExecutable(path) {
      try {
        accessSync(path, constants.X_OK);
        return true;
      } catch {
        return false;
      }
    }
  });
}

export function runInstalledClientCommand(command, args, {
  distributionRoot,
  publicLauncherPath,
  publicDistributionRoot
}) {
  const options = parseInstallArgs(args, {
    action: command,
    packageDir: distributionRoot,
    launcherPath: publicLauncherPath,
    publicDistributionRoot
  });
  return executeInstallation(options);
}

function completionMessage(action) {
  switch (action) {
    case "install":
      return "Installation completed; restart the configured AI clients before use";
    case "check":
      return "Local installation check passed";
    case "uninstall":
      return "Client integration removed";
    default:
      throw new Error(`Failed: unsupported installation action: ${action}`);
  }
}
