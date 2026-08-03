import { spawnSync } from "node:child_process";
import { accessSync, constants, existsSync } from "node:fs";
import { homedir } from "node:os";
import { delimiter, join } from "node:path";

import { distributionPaths } from "../../distribution/distribution-layout.mjs";
import { readDistributionManifest } from "../../distribution/distribution-manifest.mjs";
import { createAIClientRegistry } from "../install-command.mjs";
import {
  buildDiagnosticReport,
  renderHumanReport,
  renderJSONReport
} from "./report.mjs";
import { sanitizeDiagnosticReport } from "./redactor.mjs";

export async function runDoctor(argv, suppliedContext = {}) {
  const options = parseDoctorArgs(argv, suppliedContext.stderr ?? process.stderr);
  if (!options) {
    return 2;
  }
  let report;
  try {
    const context = completeContext(suppliedContext);
    report = await buildDiagnosticReport(context);
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    report = sanitizeDiagnosticReport({
      schemaVersion: 1,
      success: false,
      checks: [{
        id: "doctor",
        label: "Doctor initialization",
        status: "FAIL",
        detail
      }],
      environment: suppliedContext.environment ?? {},
      pathEntries: []
    }, {
      homeDirectory: suppliedContext.homeDirectory ?? homedir()
    });
  }
  const stdout = suppliedContext.stdout ?? process.stdout;
  stdout.write(options.json
    ? renderJSONReport(report)
    : renderHumanReport(report, { verbose: options.verbose }));
  return report.success ? 0 : 1;
}

function parseDoctorArgs(argv, stderr) {
  const unknown = argv.find((arg) => arg !== "--verbose" && arg !== "--json");
  if (unknown) {
    stderr.write(`Unknown doctor argument: ${unknown}\n`);
    return null;
  }
  const verbose = argv.includes("--verbose");
  const json = argv.includes("--json");
  if (json && !verbose) {
    stderr.write("--json requires --verbose\n");
    return null;
  }
  return { verbose, json };
}

function completeContext(context) {
  if (context.paths && context.manifest) {
    return context;
  }
  const distributionRoot = context.distributionRoot;
  const paths = distributionPaths(distributionRoot);
  const environment = context.environment ?? process.env;
  const publicLauncherPath = context.publicLauncherPath ?? paths.publicLauncherPath;
  const publicDistributionRoot = context.publicDistributionRoot ?? distributionRoot;
  const registry = createAIClientRegistry({
    action: "check",
    clientSelection: "configured",
    clientIDs: [],
    packageDir: distributionRoot,
    launcherPath: publicLauncherPath,
    publicDistributionRoot,
    userSkillDir: join(context.homeDirectory ?? homedir(), ".agents", "skills", "astrolabe"),
    serverName: "astrolabe",
    dryRun: false,
    help: false,
    clientConfigPaths: {}
  }, { validateSelection: false });
  return {
    distributionRoot,
    paths,
    manifest: readDistributionManifest(distributionRoot),
    hostPlatform: process.platform,
    hostArchitecture: process.arch === "x64" ? "x86_64" : process.arch,
    homeDirectory: context.homeDirectory ?? homedir(),
    environment,
    pathExists: existsSync,
    isExecutable(path) {
      try {
        accessSync(path, constants.X_OK);
        return true;
      } catch {
        return false;
      }
    },
    nativeProbe: () => spawnSync(paths.nativeExecutablePath, ["version"], {
      encoding: "utf8",
      timeout: 10000
    }),
    mcpProbe: () => spawnSync(process.execPath, [paths.mcpEntryPath, "--doctor-probe"], {
      encoding: "utf8",
      timeout: 10000
    }),
    clientFacts: context.clientFacts ?? collectAIClientFacts(registry),
    pathEntries: findLaunchers(environment.PATH ?? ""),
    stdout: context.stdout ?? process.stdout,
    stderr: context.stderr ?? process.stderr
  };
}

export function collectAIClientFacts(registry) {
  return registry.all().map((client) => {
    try {
      if (!client.isConfigured()) {
        return { id: client.id, status: "NOT CONFIGURED", detail: "Not configured" };
      }
      const problems = client.check();
      return problems.length === 0
        ? { id: client.id, status: "PASS", detail: "Configured" }
        : { id: client.id, status: "FAIL", detail: problems.join("; ") };
    } catch (error) {
      return {
        id: client.id,
        status: "FAIL",
        detail: error instanceof Error ? error.message : String(error)
      };
    }
  });
}

function findLaunchers(pathValue) {
  return pathValue
    .split(delimiter)
    .filter(Boolean)
    .map((directory) => join(directory, "astrolabe"))
    .filter((path) => existsSync(path));
}
