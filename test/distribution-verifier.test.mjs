import assert from "node:assert/strict";
import test from "node:test";

import { distributionPaths } from "../scripts/distribution/distribution-layout.mjs";
import { createDistributionManifest } from "../scripts/distribution/distribution-manifest.mjs";
import { distributionValidationProblems } from "../scripts/distribution/distribution-verifier.mjs";

test("distribution verifier shares required structure checks across commands", () => {
  const paths = distributionPaths("/pkg");
  const manifest = createDistributionManifest({
    version: "2.0.0",
    channel: "homebrew",
    platform: "darwin",
    architecture: "arm64"
  });
  const existingPaths = new Set([
    paths.manifestPath,
    paths.publicLauncherPath,
    paths.nativeExecutablePath,
    paths.mcpEntryPath,
    paths.skillPath,
    paths.licensePath,
    paths.thirdPartyNoticesPath
  ]);

  assert.deepEqual(distributionValidationProblems({
    paths,
    manifest,
    pathExists: (path) => existingPaths.has(path),
    isExecutable: (path) => path === paths.publicLauncherPath || path === paths.nativeExecutablePath
  }), []);

  existingPaths.delete(paths.thirdPartyNoticesPath);
  assert.deepEqual(distributionValidationProblems({
    paths,
    manifest,
    pathExists: (path) => existingPaths.has(path),
    isExecutable: () => true
  }), [`THIRD_PARTY_NOTICES not found: ${paths.thirdPartyNoticesPath}`]);
});

test("distribution verifier rejects non-executable launchers and manifest path drift", () => {
  const paths = distributionPaths("/pkg");
  const manifest = {
    ...createDistributionManifest({
      version: "2.0.0",
      channel: "source",
      platform: "darwin",
      architecture: "x86_64"
    }),
    nativeExecutable: "libexec/other-native"
  };

  assert.deepEqual(distributionValidationProblems({
    paths,
    manifest,
    pathExists: () => true,
    isExecutable: () => false
  }), [
    `Launcher is not executable: ${paths.publicLauncherPath}`,
    `Native CLI is not executable: ${paths.nativeExecutablePath}`,
    "Native executable path does not match the Distribution layout"
  ]);
});
