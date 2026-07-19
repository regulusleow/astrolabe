#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  assertReleaseVersion,
  canonicalRepositoryVersion,
  compareReleaseVersions,
  synchronizeRepositoryVersion
} from "./versioning.mjs";

const scriptPath = fileURLToPath(import.meta.url);
const defaultProjectRoot = resolve(dirname(scriptPath), "..");

export function parseReleaseArgs(args) {
  if (args.length !== 1) {
    throw new Error("Usage: release-prepare.mjs <major.minor.patch>");
  }
  return { version: assertReleaseVersion(args[0]) };
}

export function prepareRelease({
  projectRoot,
  version,
  commandRunner = makeCommandRunner(projectRoot)
}) {
  assertReleaseVersion(version);

  const status = runRequired(commandRunner, "git", ["status", "--porcelain"]);
  if (status.stdout.trim()) {
    throw new Error("Working tree is not clean; commit or remove existing changes first");
  }

  const branch = runRequired(
    commandRunner,
    "git",
    ["branch", "--show-current"]
  ).stdout.trim();
  if (!branch) {
    throw new Error("Cannot prepare a release from a detached HEAD");
  }

  const localHead = runRequired(
    commandRunner,
    "git",
    ["rev-parse", "HEAD"]
  ).stdout.trim();
  const remoteBranchLine = runRequired(
    commandRunner,
    "git",
    ["ls-remote", "--heads", "origin", `refs/heads/${branch}`]
  ).stdout.trim();
  const remoteHead = remoteBranchLine.split(/\s+/)[0] ?? "";
  if (!remoteHead || localHead !== remoteHead) {
    throw new Error(`Current HEAD does not match remote branch origin/${branch}`);
  }

  const localTag = runRequired(
    commandRunner,
    "git",
    ["tag", "--list", version]
  ).stdout.trim();
  if (localTag) {
    throw new Error(`Local tag already exists: ${version}`);
  }

  const remoteTag = runRequired(
    commandRunner,
    "git",
    ["ls-remote", "--tags", "origin", `refs/tags/${version}`]
  ).stdout.trim();
  if (remoteTag) {
    throw new Error(`Remote tag already exists: ${version}`);
  }

  const previousVersion = canonicalRepositoryVersion(projectRoot);
  if (compareReleaseVersions(version, previousVersion) <= 0) {
    throw new Error(
      `Release version must be greater than the current version: current=${previousVersion}, target=${version}`
    );
  }

  requireStableProtocolDependency(projectRoot, version);

  const updatedPaths = synchronizeRepositoryVersion(projectRoot, version);

  runRequired(commandRunner, "npm", ["test"]);
  runRequired(commandRunner, "swift", ["test", "--parallel"]);
  runRequired(
    commandRunner,
    "swift",
    ["build", "-c", "release", "--product", "astrolabe"]
  );

  const changedPaths = outputLines(
    runRequired(commandRunner, "git", ["diff", "HEAD", "--name-only"]).stdout
  );
  const expectedPaths = [...updatedPaths].sort();
  const unexpectedPaths = changedPaths.filter(
    (path) => !expectedPaths.includes(path)
  );
  if (unexpectedPaths.length > 0) {
    throw new Error(`Unexpected non-version file changes: ${unexpectedPaths.join(", ")}`);
  }

  const missingPaths = expectedPaths.filter(
    (path) => !changedPaths.includes(path)
  );
  if (missingPaths.length > 0) {
    throw new Error(`Version files did not produce expected changes: ${missingPaths.join(", ")}`);
  }

  const untrackedPaths = outputLines(
    runRequired(
      commandRunner,
      "git",
      ["ls-files", "--others", "--exclude-standard"]
    ).stdout
  );
  if (untrackedPaths.length > 0) {
    throw new Error(`Untracked files found: ${untrackedPaths.join(", ")}`);
  }

  runRequired(commandRunner, "git", ["diff", "--check"]);
  runRequired(commandRunner, "git", ["add", "--", ...updatedPaths]);
  runRequired(commandRunner, "git", ["diff", "--staged", "--check"]);
  runRequired(
    commandRunner,
    "git",
    ["commit", "-m", `chore: release ${version}`]
  );
  runRequired(
    commandRunner,
    "git",
    ["tag", "-a", version, "-m", `Astrolabe ${version}`]
  );

  return {
    branch,
    previousVersion,
    version,
    tag: version
  };
}

function requireStableProtocolDependency(projectRoot, releaseVersion) {
  const packageManifest = readFileSync(join(projectRoot, "Package.swift"), "utf8");
  const dependencyMatch = packageManifest.match(
    /url:\s*"[^"]*astrolabe-protocol(?:\.git)?",\s*exact:\s*"([^"]+)"/
  );
  const dependencyVersion = dependencyMatch?.[1];
  if (!dependencyVersion || !/^\d+\.\d+\.\d+$/.test(dependencyVersion)) {
    throw new Error(
      "A release must use an exact stable Astrolabe Protocol version, not an RC, branch, or revision"
    );
  }
  const releaseMajor = releaseVersion.split(".")[0];
  const protocolMajor = dependencyVersion.split(".")[0];
  if (releaseMajor !== protocolMajor) {
    throw new Error(
      `Astrolabe ${releaseVersion} must depend on a Protocol release with the same major version; current dependency is ${dependencyVersion}`
    );
  }
}

function makeCommandRunner(projectRoot) {
  return (command, args) => {
    const result = spawnSync(command, args, {
      cwd: projectRoot,
      encoding: "utf8",
      stdio: ["inherit", "pipe", "pipe"]
    });
    return {
      status: result.status,
      stdout: result.stdout ?? "",
      stderr: result.stderr ?? "",
      error: result.error
    };
  };
}

function runRequired(commandRunner, command, args) {
  const result = commandRunner(command, args);
  if (result.error || result.status !== 0) {
    const detail = result.stderr?.trim() || result.error?.message || "Unknown error";
    throw new Error(`Command failed: ${command} ${args.join(" ")}\n${detail}`);
  }
  return result;
}

function outputLines(output) {
  return output
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .sort();
}

if (resolve(process.argv[1] ?? "") === scriptPath) {
  try {
    const options = parseReleaseArgs(process.argv.slice(2));
    const result = prepareRelease({
      projectRoot: defaultProjectRoot,
      version: options.version
    });
    process.stdout.write(
      `Prepared Astrolabe ${result.version}: commit and tag created but not pushed\n`
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`Failed: ${message}`);
    process.exit(1);
  }
}
