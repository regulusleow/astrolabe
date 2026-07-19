import test from "node:test";
import assert from "node:assert/strict";
import {
  mkdtempSync,
  rmSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

import { readPackageVersion } from "../dist/package-metadata.js";

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
