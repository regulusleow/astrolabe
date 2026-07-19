#!/usr/bin/env node

import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  canonicalRepositoryVersion,
  synchronizeRepositoryVersion,
  versionConsistencyIssues
} from "./versioning.mjs";

const scriptPath = fileURLToPath(import.meta.url);
const projectRoot = resolve(dirname(scriptPath), "..");

export function parseVersionSyncArgs(args) {
  if (args.length === 1 && args[0] === "--check") {
    return { mode: "check" };
  }
  if (args.length === 2 && args[0] === "--set") {
    return { mode: "set", version: args[1] };
  }
  throw new Error("Usage: version-sync.mjs --check | --set <major.minor.patch>");
}

export function runVersionSync(root, options) {
  if (options.mode === "set") {
    synchronizeRepositoryVersion(root, options.version);
  }
  const issues = versionConsistencyIssues(root);
  if (issues.length > 0) {
    throw new Error(`Version mismatch:\n${issues.join("\n")}`);
  }
  return canonicalRepositoryVersion(root);
}

if (resolve(process.argv[1] ?? "") === scriptPath) {
  try {
    const version = runVersionSync(
      projectRoot,
      parseVersionSyncArgs(process.argv.slice(2))
    );
    process.stdout.write(`${version}\n`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(`Failed: ${message}`);
    process.exit(1);
  }
}
