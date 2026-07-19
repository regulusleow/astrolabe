import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const hostMetadataPath = "Sources/AstrolabeCLI/CommandLine/AstrolabeHostMetadata.swift";

export const versionedPaths = Object.freeze([
  hostMetadataPath,
  "docs/protocol-architecture.md",
  "mcp-adapter/package-lock.json",
  "mcp-adapter/package.json",
  "package-lock.json",
  "package.json"
]);

const strictReleaseVersionPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const swiftVersionPattern = /static let version = "(\d+\.\d+\.\d+)"/g;
const documentationVersionPattern = /`astrolabe (\d+\.\d+\.\d+)`/g;

export function assertReleaseVersion(version) {
  if (!strictReleaseVersionPattern.test(version)) {
    throw new Error(`Invalid version format: ${version}; expected major.minor.patch`);
  }
  return version;
}

export function compareReleaseVersions(left, right) {
  const leftComponents = versionComponents(left);
  const rightComponents = versionComponents(right);
  for (let index = 0; index < leftComponents.length; index += 1) {
    if (leftComponents[index] !== rightComponents[index]) {
      return leftComponents[index] > rightComponents[index] ? 1 : -1;
    }
  }
  return 0;
}

export function canonicalRepositoryVersion(projectRoot) {
  const rootPackage = readJSON(join(projectRoot, "package.json"));
  return assertReleaseVersion(rootPackage.version);
}

export function synchronizeRepositoryVersion(projectRoot, version) {
  assertReleaseVersion(version);

  const updates = [
    packageVersionUpdate(join(projectRoot, "package.json"), version),
    packageLockVersionUpdate(join(projectRoot, "package-lock.json"), version),
    packageVersionUpdate(
      join(projectRoot, "mcp-adapter/package.json"),
      version
    ),
    packageLockVersionUpdate(
      join(projectRoot, "mcp-adapter/package-lock.json"),
      version
    ),
    textVersionUpdate(
      join(projectRoot, hostMetadataPath),
      swiftVersionPattern,
      `static let version = "${version}"`
    ),
    textVersionUpdate(
      join(projectRoot, "docs/protocol-architecture.md"),
      documentationVersionPattern,
      `\`astrolabe ${version}\``
    )
  ];

  updates.forEach(({ path, content }) => writeFileSync(path, content));

  const issues = versionConsistencyIssues(projectRoot);
  if (issues.length > 0) {
    throw new Error(`Version mismatch remains after synchronization:\n${issues.join("\n")}`);
  }
  return [...versionedPaths];
}

export function versionConsistencyIssues(projectRoot) {
  const expectedVersion = canonicalRepositoryVersion(projectRoot);
  const issues = [];

  inspectJSONVersion(
    join(projectRoot, "package-lock.json"),
    "package-lock.json",
    expectedVersion,
    issues
  );
  inspectJSONVersion(
    join(projectRoot, "mcp-adapter/package.json"),
    "mcp-adapter/package.json",
    expectedVersion,
    issues
  );
  inspectJSONVersion(
    join(projectRoot, "mcp-adapter/package-lock.json"),
    "mcp-adapter/package-lock.json",
    expectedVersion,
    issues
  );
  inspectTextVersion(
    join(projectRoot, hostMetadataPath),
    hostMetadataPath,
    swiftVersionPattern,
    expectedVersion,
    issues
  );
  inspectTextVersion(
    join(projectRoot, "docs/protocol-architecture.md"),
    "docs/protocol-architecture.md",
    documentationVersionPattern,
    expectedVersion,
    issues
  );

  return issues;
}

function versionComponents(version) {
  return assertReleaseVersion(version).split(".").map(Number);
}

function packageVersionUpdate(path, version) {
  const packageJSON = readJSON(path);
  packageJSON.version = version;
  return { path, content: jsonString(packageJSON) };
}

function packageLockVersionUpdate(path, version) {
  const packageLock = readJSON(path);
  if (!packageLock.packages?.[""]) {
    throw new Error(`Missing root package metadata in npm lockfile: ${path}`);
  }
  packageLock.version = version;
  packageLock.packages[""].version = version;
  return { path, content: jsonString(packageLock) };
}

function textVersionUpdate(path, pattern, replacement) {
  const source = readFileSync(path, "utf8");
  const matches = [...source.matchAll(pattern)];
  if (matches.length !== 1) {
    throw new Error(`Unexpected version field count in ${path}: expected 1, found ${matches.length}`);
  }
  return { path, content: source.replace(pattern, replacement) };
}

function inspectJSONVersion(path, displayPath, expectedVersion, issues) {
  const value = readJSON(path);
  appendVersionIssue(displayPath, value.version, expectedVersion, issues);
  if (displayPath.endsWith("package-lock.json")) {
    appendVersionIssue(
      `${displayPath}#packages[\"\"]`,
      value.packages?.[""]?.version,
      expectedVersion,
      issues
    );
  }
}

function inspectTextVersion(
  path,
  displayPath,
  pattern,
  expectedVersion,
  issues
) {
  const matches = [...readFileSync(path, "utf8").matchAll(pattern)];
  if (matches.length !== 1) {
    issues.push(`${displayPath}: expected one version field, found ${matches.length}`);
    return;
  }
  appendVersionIssue(displayPath, matches[0][1], expectedVersion, issues);
}

function appendVersionIssue(path, actualVersion, expectedVersion, issues) {
  if (actualVersion !== expectedVersion) {
    issues.push(`${path}: expected ${expectedVersion}, found ${actualVersion ?? "missing"}`);
  }
}

function readJSON(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function jsonString(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}
