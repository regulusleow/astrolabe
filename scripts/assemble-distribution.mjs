#!/usr/bin/env node

import { realpathSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { buildSourceDistribution } from "./distribution/source-distribution-builder.mjs";

const scriptPath = fileURLToPath(import.meta.url);

/**
 * @typedef {Object} ParsedAssemblyArgs
 * @property {string} outputRoot - Absolute Distribution output directory.
 * @property {"source"|"homebrew"} channel - Distribution owner channel.
 * @property {"arm64"|"x86_64"} architecture - Required native executable architecture.
 */

/**
 * @param {string[]} argv
 * @returns {ParsedAssemblyArgs}
 */
export function parseAssemblyArgs(argv) {
  const values = new Map();
  for (let index = 0; index < argv.length; index += 2) {
    const flag = argv[index];
    const value = argv[index + 1];
    if (!["--output", "--channel", "--architecture"].includes(flag) || !value) {
      throw new Error(`Failed: invalid distribution assembly argument: ${flag ?? "missing"}`);
    }
    if (values.has(flag)) {
      throw new Error(`Failed: duplicate distribution assembly argument: ${flag}`);
    }
    values.set(flag, value);
  }
  for (const flag of ["--output", "--channel", "--architecture"]) {
    if (!values.has(flag)) {
      throw new Error(`Failed: missing distribution assembly argument: ${flag}`);
    }
  }
  if (!["source", "homebrew"].includes(values.get("--channel"))) {
    throw new Error(`Failed: unsupported distribution channel: ${values.get("--channel")}`);
  }
  if (!["arm64", "x86_64"].includes(values.get("--architecture"))) {
    throw new Error(`Failed: unsupported distribution architecture: ${values.get("--architecture")}`);
  }
  return Object.freeze({
    outputRoot: resolve(values.get("--output")),
    channel: values.get("--channel"),
    architecture: values.get("--architecture")
  });
}

export function runAssemblyCLI(argv) {
  const projectRoot = resolve(dirname(scriptPath), "..");
  const parsed = parseAssemblyArgs(argv);
  const packageJson = JSON.parse(readFileSync(resolve(projectRoot, "package.json"), "utf8"));
  return buildSourceDistribution({
    projectRoot,
    outputRoot: parsed.outputRoot,
    version: packageJson.version,
    channel: parsed.channel,
    platform: "darwin",
    architecture: parsed.architecture
  });
}

function isMainModule() {
  if (!process.argv[1]) {
    return false;
  }
  try {
    return realpathSync(process.argv[1]) === realpathSync(scriptPath);
  } catch {
    return resolve(process.argv[1]) === resolve(scriptPath);
  }
}

if (isMainModule()) {
  try {
    runAssemblyCLI(process.argv.slice(2));
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    process.stderr.write(`${detail.startsWith("Failed:") ? detail : `Failed: ${detail}`}\n`);
    process.exitCode = 1;
  }
}
