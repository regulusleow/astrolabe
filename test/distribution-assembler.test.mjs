import assert from "node:assert/strict";
import {
  chmodSync,
  existsSync,
  lstatSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  readlinkSync,
  rmSync,
  writeFileSync
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import test from "node:test";

import { parseAssemblyArgs } from "../scripts/assemble-distribution.mjs";
import { assembleDistribution } from "../scripts/distribution/distribution-assembler.mjs";
import { distributionPaths } from "../scripts/distribution/distribution-layout.mjs";
import { readDistributionManifest } from "../scripts/distribution/distribution-manifest.mjs";
import { buildSourceDistribution } from "../scripts/distribution/source-distribution-builder.mjs";

test("assembly CLI accepts only supported channels and architectures", () => {
  assert.deepEqual(parseAssemblyArgs([
    "--output",
    "/tmp/output",
    "--channel",
    "homebrew",
    "--architecture",
    "arm64"
  ]), {
    outputRoot: "/tmp/output",
    channel: "homebrew",
    architecture: "arm64"
  });
  assert.throws(() => parseAssemblyArgs([
    "--output", "/tmp/output", "--channel", "npm", "--architecture", "arm64"
  ]), /unsupported distribution channel/);
  assert.throws(() => parseAssemblyArgs([
    "--output", "/tmp/output", "--channel", "source", "--architecture", "x64"
  ]), /unsupported distribution architecture/);
});

test("source builder runs only the declared build commands before assembly", () => {
  const calls = [];
  const options = {
    projectRoot: "/tmp/project",
    outputRoot: "/tmp/output",
    version: "2.0.0",
    channel: "source",
    platform: "darwin",
    architecture: "arm64"
  };
  const result = buildSourceDistribution(options, {
    runBuildCommand: (command, args, commandOptions) => {
      calls.push({ command, args, options: commandOptions });
    },
    assemble: (assemblyOptions) => {
      assert.equal(assemblyOptions, options);
      return { root: options.outputRoot, manifest: {} };
    }
  });

  assert.equal(result.root, "/tmp/output");
  assert.deepEqual(calls, [
    {
      command: "npm",
      args: ["--prefix", "mcp-adapter", "ci"],
      options: { cwd: "/tmp/project" }
    },
    {
      command: "npm",
      args: ["--prefix", "mcp-adapter", "run", "build"],
      options: { cwd: "/tmp/project" }
    },
    {
      command: "swift",
      args: ["build", "-c", "release", "--product", "astrolabe"],
      options: { cwd: "/tmp/project" }
    }
  ]);
});

test("assembler creates the exact runtime layout without inventing NOTICE", () => {
  const fixture = createDistributionFixture();
  try {
    const result = assembleFixture(fixture);
    const paths = distributionPaths(result.root);

    assert.deepEqual(readDistributionManifest(result.root), {
      schemaVersion: 1,
      version: "2.0.0",
      channel: "source",
      platform: "darwin",
      architecture: "arm64",
      nativeExecutable: "libexec/astrolabe-native",
      mcpEntry: "libexec/mcp-adapter/dist/index.js"
    });
    assert.equal(lstatSync(paths.publicLauncherPath).isSymbolicLink(), true);
    assert.equal(readlinkSync(paths.publicLauncherPath), "../libexec/astrolabe-launcher.mjs");
    assert.equal(existsSync(paths.nativeExecutablePath), true);
    assert.equal(existsSync(paths.mcpEntryPath), true);
    assert.equal(existsSync(paths.skillPath), true);
    assert.equal(
      existsSync(join(result.root, "installation", "node_modules", "jsonc-parser", "package.json")),
      true
    );
    assert.equal(readFileSync(paths.licensePath, "utf8"), "Apache-2.0 fixture\n");
    assert.equal(readFileSync(paths.thirdPartyNoticesPath, "utf8"), "Third-party fixture\n");
    assert.equal(existsSync(paths.noticePath), false);
    assert.equal(fixture.installCalls.length, 1);
    assert.match(fixture.installCalls[0], /\.staging-\d+-\d+\/libexec\/mcp-adapter$/);
  } finally {
    fixture.cleanup();
  }
});

test("assembler preserves an existing NOTICE verbatim", () => {
  const fixture = createDistributionFixture({ notice: "Required attribution\nDo not rewrite\n" });
  try {
    const result = assembleFixture(fixture);
    assert.equal(
      readFileSync(distributionPaths(result.root).noticePath, "utf8"),
      "Required attribution\nDo not rewrite\n"
    );
  } finally {
    fixture.cleanup();
  }
});

test("assembler rejects a mismatched native architecture before replacement", () => {
  const fixture = createDistributionFixture();
  try {
    mkdirSync(fixture.outputRoot, { recursive: true });
    writeFileSync(join(fixture.outputRoot, "sentinel"), "existing\n");
    writeManagedOutputMarker(fixture.outputRoot);

    assert.throws(() => assembleFixture(fixture, {
      readArchitectures: () => ["x86_64"]
    }), /native architecture mismatch/);
    assert.equal(readFileSync(join(fixture.outputRoot, "sentinel"), "utf8"), "existing\n");
  } finally {
    fixture.cleanup();
  }
});

test("assembler removes staging and preserves existing output after dependency failure", () => {
  const fixture = createDistributionFixture();
  try {
    mkdirSync(fixture.outputRoot, { recursive: true });
    writeFileSync(join(fixture.outputRoot, "sentinel"), "existing\n");
    writeManagedOutputMarker(fixture.outputRoot);

    assert.throws(() => assembleFixture(fixture, {
      installProductionDependencies: () => {
        throw new Error("dependency failure");
      }
    }), /dependency failure/);
    assert.equal(readFileSync(join(fixture.outputRoot, "sentinel"), "utf8"), "existing\n");
    assert.deepEqual(
      readdirSync(dirname(fixture.outputRoot)).filter((name) => name.includes(".staging-")),
      []
    );
  } finally {
    fixture.cleanup();
  }
});

test("assembler rejects an output directory that contains the source root", () => {
  const fixture = createDistributionFixture();
  try {
    assert.throws(() => assembleDistribution({
      projectRoot: fixture.projectRoot,
      outputRoot: dirname(fixture.projectRoot),
      version: "2.0.0",
      channel: "source",
      platform: "darwin",
      architecture: "arm64"
    }, {
      readArchitectures: () => ["arm64"],
      installProductionDependencies: () => {}
    }), /unsafe Distribution output directory/);
  } finally {
    fixture.cleanup();
  }
});

test("assembler refuses to replace an unmanaged existing directory", () => {
  const fixture = createDistributionFixture();
  try {
    mkdirSync(fixture.outputRoot, { recursive: true });
    writeFileSync(join(fixture.outputRoot, "user-file"), "keep\n");

    assert.throws(() => assembleFixture(fixture), /not managed by Astrolabe/);
    assert.equal(readFileSync(join(fixture.outputRoot, "user-file"), "utf8"), "keep\n");
  } finally {
    fixture.cleanup();
  }
});

function assembleFixture(fixture, dependencyOverrides = {}) {
  return assembleDistribution({
    projectRoot: fixture.projectRoot,
    outputRoot: fixture.outputRoot,
    version: "2.0.0",
    channel: "source",
    platform: "darwin",
    architecture: "arm64"
  }, {
    readArchitectures: () => ["arm64"],
    installProductionDependencies: (directory) => fixture.installCalls.push(directory),
    ...dependencyOverrides
  });
}

function writeManagedOutputMarker(outputRoot) {
  writeFileSync(join(outputRoot, "distribution-manifest.json"), `${JSON.stringify({
    schemaVersion: 1,
    version: "2.0.0",
    channel: "source",
    platform: "darwin",
    architecture: "arm64",
    nativeExecutable: "libexec/astrolabe-native",
    mcpEntry: "libexec/mcp-adapter/dist/index.js"
  })}\n`);
}

function createDistributionFixture(options = {}) {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-distribution-"));
  const projectRoot = join(root, "project");
  const outputRoot = join(root, "output", "astrolabe");
  const files = new Map([
    [".build/release/astrolabe", "native fixture\n"],
    ["mcp-adapter/dist/index.js", "console.log('mcp fixture');\n"],
    ["mcp-adapter/package.json", "{\"type\":\"module\"}\n"],
    ["mcp-adapter/package-lock.json", "{\"lockfileVersion\":3}\n"],
    ["scripts/distribution/launcher.mjs", "#!/usr/bin/env node\n"],
    ["scripts/distribution/distribution-layout.mjs", "export {};\n"],
    ["scripts/distribution/distribution-manifest.mjs", "export {};\n"],
    ["scripts/distribution/distribution-verifier.mjs", "export {};\n"],
    ["scripts/installation/ai-client-detector.mjs", "export {};\n"],
    ["scripts/installation/ai-client-registry.mjs", "export {};\n"],
    ["scripts/installation/clients/client.mjs", "export {};\n"],
    ["scripts/installation/command-runner.mjs", "export {};\n"],
    ["scripts/installation/doctor/doctor.mjs", "export {};\n"],
    ["scripts/installation/install-command.mjs", "export {};\n"],
    ["scripts/installation/install-options.mjs", "export {};\n"],
    ["scripts/installation/installation-orchestrator.mjs", "export {};\n"],
    ["scripts/installation/jsonc-config-editor.mjs", "export {};\n"],
    ["scripts/installation/managed-config-file.mjs", "export {};\n"],
    ["scripts/installation/managed-skill-link.mjs", "export {};\n"],
    ["node_modules/jsonc-parser/package.json", "{\"type\":\"module\"}\n"],
    ["skills/astrolabe/SKILL.md", "---\nname: astrolabe\ndescription: Use when testing.\n---\n"],
    ["LICENSE", "Apache-2.0 fixture\n"],
    ["THIRD_PARTY_NOTICES", "Third-party fixture\n"]
  ]);
  if (options.notice !== undefined) {
    files.set("NOTICE", options.notice);
  }
  for (const [relativePath, contents] of files) {
    const path = join(projectRoot, relativePath);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, contents);
  }
  chmodSync(join(projectRoot, ".build/release/astrolabe"), 0o755);

  return {
    projectRoot,
    outputRoot,
    installCalls: [],
    cleanup() {
      rmSync(root, { recursive: true, force: true });
    }
  };
}
