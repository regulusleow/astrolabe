#!/usr/bin/env node

import { realpathSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { runCommand } from "./installation/command-runner.mjs";

const scriptPath = fileURLToPath(import.meta.url);
const projectRoot = resolve(dirname(scriptPath), "..");
const require = createRequire(import.meta.url);

export function ensureInstallerDependencies(dependencies = {}) {
  const resolveDependency = dependencies.resolveDependency ?? (() => require.resolve("jsonc-parser"));
  const commandRunner = dependencies.runCommand ?? runCommand;
  try {
    resolveDependency();
    return;
  } catch (error) {
    if (error?.code !== "MODULE_NOT_FOUND" && error?.code !== "ERR_MODULE_NOT_FOUND") {
      throw error;
    }
  }

  commandRunner("npm", ["ci", "--ignore-scripts"], { cwd: projectRoot });
  resolveDependency();
}

async function main() {
  try {
    ensureInstallerDependencies();
    const [{ parseInstallArgs }, { executeInstallation }] = await Promise.all([
      import("./installation/install-options.mjs"),
      import("./installation/install-command.mjs")
    ]);
    executeInstallation(parseInstallArgs(process.argv.slice(2)));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`${message.startsWith("Failed:") ? message : `Failed: ${message}`}\n`);
    process.exitCode = 1;
  }
}

function isMainModule() {
  if (!process.argv[1]) {
    return false;
  }
  try {
    return realpathSync(process.argv[1]) === realpathSync(scriptPath);
  } catch {
    return resolve(process.argv[1]) === scriptPath;
  }
}

if (isMainModule()) {
  await main();
}
