import test from "node:test";
import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { distributionPaths } from "../scripts/distribution/distribution-layout.mjs";
import {
  createDistributionManifest,
  readDistributionManifest,
  writeDistributionManifest
} from "../scripts/distribution/distribution-manifest.mjs";

test("distribution layout resolves every runtime artifact from one root", () => {
  const paths = distributionPaths("/tmp/astrolabe-distribution");

  assert.deepEqual(paths, {
    root: "/tmp/astrolabe-distribution",
    publicLauncherPath: "/tmp/astrolabe-distribution/bin/astrolabe",
    launcherModulePath: "/tmp/astrolabe-distribution/libexec/astrolabe-launcher.mjs",
    nativeExecutablePath: "/tmp/astrolabe-distribution/libexec/astrolabe-native",
    mcpAdapterDirectory: "/tmp/astrolabe-distribution/libexec/mcp-adapter",
    mcpEntryPath: "/tmp/astrolabe-distribution/libexec/mcp-adapter/dist/index.js",
    installationDirectory: "/tmp/astrolabe-distribution/installation",
    skillDirectory: "/tmp/astrolabe-distribution/skills/astrolabe",
    skillPath: "/tmp/astrolabe-distribution/skills/astrolabe/SKILL.md",
    manifestPath: "/tmp/astrolabe-distribution/distribution-manifest.json",
    licensePath: "/tmp/astrolabe-distribution/LICENSE",
    thirdPartyNoticesPath: "/tmp/astrolabe-distribution/THIRD_PARTY_NOTICES",
    noticePath: "/tmp/astrolabe-distribution/NOTICE"
  });
  assert.equal(Object.isFrozen(paths), true);
});

test("distribution manifest round-trips schema 1", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-manifest-"));
  try {
    const manifest = createDistributionManifest({
      version: "2.0.0",
      channel: "source",
      platform: "darwin",
      architecture: "arm64"
    });

    assert.equal(manifest.nativeExecutable, "libexec/astrolabe-native");
    assert.equal(manifest.mcpEntry, "libexec/mcp-adapter/dist/index.js");

    writeDistributionManifest(root, manifest);

    assert.deepEqual(readDistributionManifest(root), manifest);
    assert.equal(
      readFileSync(distributionPaths(root).manifestPath, "utf8").endsWith("\n"),
      true
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("distribution manifest rejects an unsupported schema", () => {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-manifest-"));
  try {
    mkdirSync(root, { recursive: true });
    writeFileSync(distributionPaths(root).manifestPath, JSON.stringify({
      schemaVersion: 2,
      version: "2.0.0",
      channel: "source",
      platform: "darwin",
      architecture: "arm64"
    }));

    assert.throws(
      () => readDistributionManifest(root),
      /unsupported distribution manifest schema: 2/
    );
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("distribution manifest rejects invalid stable fields", () => {
  const valid = {
    version: "2.0.0",
    channel: "source",
    platform: "darwin",
    architecture: "arm64"
  };

  assert.throws(
    () => createDistributionManifest({ ...valid, version: "2.0.0-rc.1" }),
    /invalid distribution version/
  );
  assert.throws(
    () => createDistributionManifest({ ...valid, channel: "npm" }),
    /unsupported distribution channel/
  );
  assert.throws(
    () => createDistributionManifest({ ...valid, platform: "linux" }),
    /unsupported distribution platform/
  );
  assert.throws(
    () => createDistributionManifest({ ...valid, architecture: "universal" }),
    /unsupported distribution architecture/
  );
});

test("distribution manifest rejects unknown fields", () => {
  assert.throws(
    () => createDistributionManifest({
      version: "2.0.0",
      channel: "source",
      platform: "darwin",
      architecture: "arm64",
      extra: true
    }),
    /unknown distribution manifest field: extra/
  );
});

test("distribution manifest rejects runtime paths that differ from the schema", () => {
  const valid = createDistributionManifest({
    version: "2.0.0",
    channel: "source",
    platform: "darwin",
    architecture: "arm64"
  });

  assert.throws(
    () => writeDistributionManifest("/tmp/astrolabe-invalid-manifest", {
      ...valid,
      nativeExecutable: "/tmp/astrolabe-native"
    }),
    /invalid native executable path/
  );
  assert.throws(
    () => writeDistributionManifest("/tmp/astrolabe-invalid-manifest", {
      ...valid,
      mcpEntry: "../index.js"
    }),
    /invalid MCP entry path/
  );
});
