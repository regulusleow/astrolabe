import { AIClientRegistry } from "./ai-client-registry.mjs";
import { CodexInstaller, defaultCodexConfigPath } from "./clients/codex-installer.mjs";
import { OpenCodeInstaller, defaultOpenCodeConfigPath } from "./clients/opencode-installer.mjs";
import { runInstallation } from "./installation-orchestrator.mjs";
import {
  checkManagedSkillLink,
  installManagedSkillLink,
  removeManagedSkillLink
} from "./managed-skill-link.mjs";
import { packageArtifactPaths } from "./package-layout.mjs";
import {
  buildProject,
  checkRuntimePackage,
  ensureGitSource,
  installRuntimePackage
} from "./runtime-package-installer.mjs";

export function createAIClientRegistry(options) {
  const packagePaths = packageArtifactPaths(options.packageDir);
  const sharedClientOptions = {
    serverName: options.serverName,
    packagePaths,
    skillDirectories: [options.userSkillDir],
    dryRun: options.dryRun
  };
  const registry = new AIClientRegistry([
    new CodexInstaller({
      ...sharedClientOptions,
      configPath: options.clientConfigPaths.codex ?? defaultCodexConfigPath()
    }),
    new OpenCodeInstaller({
      ...sharedClientOptions,
      configPath: options.clientConfigPaths.opencode ?? defaultOpenCodeConfigPath()
    })
  ]);
  validateClientConfigOverrides(options, registry);
  return registry;
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
  process.stdout.write(`Usage:
  astrolabe-install --client <codex|opencode> [--client <client>]
  npm run install:codex
  npm run install:opencode

Options:
  --client <name>             AI client to configure; repeat to install multiple clients
  --repo, --git <url>         Clone or update a Git repository before installation
  --install-dir <path>        Source checkout directory used with --repo
  --package-dir <path>        Shared runtime package directory
  --user-skill-dir <path>     Shared agent-compatible Astrolabe skill link
  --client-config <id>=<path> Override one AI client's global configuration path
  --server-name <name>        MCP server name; defaults to astrolabe
  --check                     Verify shared artifacts and selected client configurations
  --uninstall                 Remove selected client configurations and unused skill links
  --dry-run                   Validate and print external commands without changing files
`);
}

export function executeInstallation(options) {
  if (options.help) {
    printHelp();
    return;
  }

  const packagePaths = packageArtifactPaths(options.packageDir);
  const registry = createAIClientRegistry(options);
  runInstallation(options, {
    registry,
    preparePackage() {
      ensureGitSource(options);
      buildProject(options);
      installRuntimePackage(options);
    },
    installSkillLink(skillDirectory) {
      installManagedSkillLink(skillDirectory, packagePaths.skillDir, options.dryRun);
    },
    removeSkillLink(skillDirectory) {
      removeManagedSkillLink(skillDirectory, packagePaths.skillDir, options.dryRun);
    },
    checkSharedInstallation() {
      return [
        ...checkRuntimePackage(options.packageDir),
        ...checkManagedSkillLink(options.userSkillDir, packagePaths.skillDir)
      ];
    }
  });

  if (options.dryRun) {
    process.stdout.write("Dry run completed without changing files.\n");
    return;
  }
  process.stdout.write(`${completionMessage(options.action)}: ${options.clientIDs.join(", ")}\n`);
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
