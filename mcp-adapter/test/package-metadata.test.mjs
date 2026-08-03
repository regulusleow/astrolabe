import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  mkdtempSync,
  rmSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import { readPackageVersion } from "../dist/package-metadata.js";

test("MCP doctor probe loads the runtime and exits with its version", () => {
  const result = spawnSync(process.execPath, ["dist/index.js", "--doctor-probe"], {
    cwd: new URL("..", import.meta.url),
    encoding: "utf8",
    timeout: 2000
  });

  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(JSON.parse(result.stdout), { version: "2.0.0" });
});

test("readPackageVersion reads a strict package release version", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-mcp-version-test-"));
  const packagePath = join(root, "package.json");
  try {
    writeFileSync(packagePath, '{"name":"test","version":"1.2.3"}\n');
    assert.equal(readPackageVersion(pathToFileURL(packagePath)), "1.2.3");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("readPackageVersion rejects missing or invalid versions", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-mcp-version-test-"));
  const packagePath = join(root, "package.json");
  try {
    writeFileSync(packagePath, '{"name":"test","version":"v1.2.3"}\n');
    assert.throws(
      () => readPackageVersion(pathToFileURL(packagePath)),
      /Invalid MCP package version/
    );
    writeFileSync(packagePath, "not json\n");
    assert.throws(
      () => readPackageVersion(pathToFileURL(packagePath)),
      /Unable to read the MCP package version/
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
