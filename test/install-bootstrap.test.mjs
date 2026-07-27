import test from "node:test";
import assert from "node:assert/strict";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { ensureInstallerDependencies } from "../scripts/install.mjs";

const projectRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..");

test("installer bootstrap skips npm ci when dependencies are available", () => {
  const commands = [];

  ensureInstallerDependencies({
    resolveDependency: () => "/tmp/node_modules/jsonc-parser/package.json",
    runCommand: (...args) => commands.push(args)
  });

  assert.deepEqual(commands, []);
});

test("installer bootstrap restores locked dependencies for a fresh clone", () => {
  const commands = [];
  let attempts = 0;

  ensureInstallerDependencies({
    resolveDependency() {
      attempts += 1;
      if (attempts === 1) {
        const error = new Error("missing dependency");
        error.code = "MODULE_NOT_FOUND";
        throw error;
      }
      return "/tmp/node_modules/jsonc-parser/package.json";
    },
    runCommand(command, args, options) {
      commands.push({ command, args, options });
    }
  });

  assert.deepEqual(commands, [{
    command: "npm",
    args: ["ci", "--ignore-scripts"],
    options: { cwd: projectRoot }
  }]);
  assert.equal(attempts, 2);
});

test("installer bootstrap does not hide dependency resolution failures", () => {
  assert.throws(
    () => ensureInstallerDependencies({
      resolveDependency() {
        const error = new Error("invalid package metadata");
        error.code = "ERR_INVALID_PACKAGE_CONFIG";
        throw error;
      },
      runCommand: () => assert.fail("npm ci must not run for unrelated failures")
    }),
    /invalid package metadata/
  );
});
