/**
 * @typedef {Object} DiagnosticCheck
 * @property {string} id - Stable machine-readable check identifier.
 * @property {string} label - Human-readable check label.
 * @property {"PASS"|"WARN"|"FAIL"|"NOT CONFIGURED"} status - Check outcome.
 * @property {string} detail - Diagnostic detail safe only after sanitization.
 */

/**
 * @param {Object} context
 * @returns {Promise<Record<string, unknown>>}
 */
export async function collectDiagnosticFacts(context) {
  const checks = [];
  const installationProblems = distributionValidationProblems(context);
  checks.push(check(
    "installation",
    "Astrolabe installation",
    installationProblems.length === 0 ? "PASS" : "FAIL",
    installationProblems.length === 0
      ? `Distribution ${context.manifest.version} (${context.manifest.channel})`
      : installationProblems.join("; ")
  ));

  const hostPlatform = context.hostPlatform ?? context.manifest.platform;
  const hostArchitecture = context.hostArchitecture ?? context.manifest.architecture;
  const matchesHost = hostPlatform === context.manifest.platform
    && hostArchitecture === context.manifest.architecture;
  checks.push(check(
    "host",
    "Host compatibility",
    matchesHost ? "PASS" : "FAIL",
    matchesHost
      ? `${hostPlatform} ${hostArchitecture}`
      : `Distribution requires ${context.manifest.platform} ${context.manifest.architecture}; host is ${hostPlatform} ${hostArchitecture}`
  ));

  checks.push(probeNative(context));
  checks.push(probeMCP(context));
  checks.push(...context.clientFacts.map((fact) => check(
    `client:${fact.id}`,
    `${fact.id} integration`,
    fact.status,
    fact.detail
  )));

  const launcherCount = context.pathEntries.length;
  checks.push(check(
    "path",
    "PATH launcher",
    launcherCount <= 1 ? "PASS" : "WARN",
    launcherCount <= 1
      ? (context.pathEntries[0] ?? "No additional Launcher found in PATH")
      : `Multiple Launchers found: ${context.pathEntries.join(", ")}`
  ));

  return {
    schemaVersion: 1,
    success: !checks.some((item) => item.status === "FAIL"),
    checks,
    environment: context.environment,
    pathEntries: context.pathEntries
  };
}

function probeNative(context) {
  const id = "native";
  const label = "Native CLI";
  const path = context.paths.nativeExecutablePath;
  if (!context.pathExists(path)) {
    return check(id, label, "FAIL", `File does not exist: ${path}`);
  }
  if (!context.isExecutable(path)) {
    return check(id, label, "FAIL", `File is not executable: ${path}`);
  }
  const result = context.nativeProbe();
  if (result.status !== 0) {
    return check(id, label, "FAIL", result.stderr || `Exit code: ${result.status}`);
  }
  const version = parseProbeVersion(result.stdout, "native");
  if (!version) {
    return check(id, label, "FAIL", "Native executable did not return a valid version");
  }
  return version === context.manifest.version
    ? check(id, label, "PASS", `${path} (${version})`)
    : check(id, label, "FAIL", `Native version ${version} does not match Distribution ${context.manifest.version}`);
}

function probeMCP(context) {
  const path = context.paths.mcpEntryPath;
  if (!context.pathExists(path)) {
    return check("mcp", "MCP Adapter", "FAIL", `File does not exist: ${path}`);
  }
  const result = context.mcpProbe();
  if (result.status !== 0) {
    return check("mcp", "MCP Adapter", "FAIL", result.stderr || `Exit code: ${result.status}`);
  }
  const version = parseProbeVersion(result.stdout, "mcp");
  if (!version) {
    return check("mcp", "MCP Adapter", "FAIL", "MCP Adapter did not return a valid version");
  }
  return version === context.manifest.version
    ? check("mcp", "MCP Adapter", "PASS", `${path} (${version})`)
    : check("mcp", "MCP Adapter", "FAIL", `MCP version ${version} does not match Distribution ${context.manifest.version}`);
}

function parseProbeVersion(stdout, kind) {
  try {
    const value = JSON.parse(stdout);
    return kind === "native" ? value.data?.version : value.version;
  } catch {
    return null;
  }
}

/** @returns {DiagnosticCheck} */
function check(id, label, status, detail) {
  return { id, label, status, detail };
}
import { distributionValidationProblems } from "../../distribution/distribution-verifier.mjs";
