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

import {
  assertReleaseVersion,
  compareReleaseVersions,
  synchronizeRepositoryVersion,
  versionConsistencyIssues
} from "../scripts/versioning.mjs";
import {
  parseReleaseArgs,
  prepareRelease
} from "../scripts/release-prepare.mjs";

test("release versions use strict major.minor.patch syntax", () => {
  assert.equal(assertReleaseVersion("1.2.3"), "1.2.3");
  assert.throws(() => assertReleaseVersion("v1.2.3"), /Invalid version format/);
  assert.throws(() => assertReleaseVersion("1.2.3-beta.1"), /Invalid version format/);
});

test("release version comparison uses numeric semantic components", () => {
  assert.equal(compareReleaseVersions("0.1.10", "0.1.9"), 1);
  assert.equal(compareReleaseVersions("0.2.0", "0.10.0"), -1);
  assert.equal(compareReleaseVersions("1.0.0", "1.0.0"), 0);
});

test("version synchronization updates every derived version artifact", () => {
  const fixture = makeVersionFixture();
  try {
    const updatedPaths = synchronizeRepositoryVersion(fixture.root, "0.2.0");

    assert.deepEqual(updatedPaths, fixture.expectedVersionedPaths);
    assert.equal(readJSON(join(fixture.root, "package.json")).version, "0.2.0");
    assert.equal(readJSON(join(fixture.root, "package-lock.json")).version, "0.2.0");
    assert.equal(
      readJSON(join(fixture.root, "package-lock.json")).packages[""].version,
      "0.2.0"
    );
    assert.equal(
      readJSON(join(fixture.root, "mcp-adapter/package.json")).version,
      "0.2.0"
    );
    assert.equal(
      readJSON(join(fixture.root, "mcp-adapter/package-lock.json")).packages[""].version,
      "0.2.0"
    );
    assert.match(
      readFileSync(join(fixture.root, fixture.swiftPath), "utf8"),
      /static let version = "0\.2\.0"/
    );
    assert.match(
      readFileSync(join(fixture.root, fixture.documentationPath), "utf8"),
      /`astrolabe 0\.2\.0`/
    );
    assert.deepEqual(versionConsistencyIssues(fixture.root), []);
  } finally {
    fixture.cleanup();
  }
});

test("version consistency reports each drifted artifact", () => {
  const fixture = makeVersionFixture();
  try {
    const adapterPackagePath = join(fixture.root, "mcp-adapter/package.json");
    const adapterPackage = readJSON(adapterPackagePath);
    adapterPackage.version = "0.0.9";
    writeJSON(adapterPackagePath, adapterPackage);

    assert.deepEqual(
      versionConsistencyIssues(fixture.root),
      ["mcp-adapter/package.json: expected 0.1.2, found 0.0.9"]
    );
  } finally {
    fixture.cleanup();
  }
});

test("version synchronization validates every artifact before writing", () => {
  const fixture = makeVersionFixture();
  try {
    writeFileSync(
      join(fixture.root, fixture.documentationPath),
      "missing product version\n"
    );

    assert.throws(
      () => synchronizeRepositoryVersion(fixture.root, "0.2.0"),
      /Unexpected version field count/
    );
    assert.equal(readJSON(join(fixture.root, "package.json")).version, "0.1.2");
    assert.equal(
      readJSON(join(fixture.root, "mcp-adapter/package.json")).version,
      "0.1.2"
    );
  } finally {
    fixture.cleanup();
  }
});

test("release argument parser requires one target version", () => {
  assert.deepEqual(parseReleaseArgs(["0.1.3"]), { version: "0.1.3" });
  assert.throws(() => parseReleaseArgs([]), /Usage/);
  assert.throws(() => parseReleaseArgs(["0.1.3", "--push"]), /Usage/);
});

test("release preparation synchronizes, verifies, commits, and tags without pushing", () => {
  const fixture = makeVersionFixture();
  const calls = [];
  const commandRunner = (command, args) => {
    calls.push([command, ...args]);
    const key = [command, ...args].join(" ");
    if (key === "git status --porcelain") {
      return { stdout: "", stderr: "", status: 0 };
    }
    if (key === "git branch --show-current") {
      return { stdout: "develop\n", stderr: "", status: 0 };
    }
    if (key === "git rev-parse HEAD") {
      return { stdout: "abc123\n", stderr: "", status: 0 };
    }
    if (key === "git ls-remote --heads origin refs/heads/develop") {
      return {
        stdout: "abc123\trefs/heads/develop\n",
        stderr: "",
        status: 0
      };
    }
    if (key === "git tag --list 0.1.3") {
      return { stdout: "", stderr: "", status: 0 };
    }
    if (key === "git ls-remote --tags origin refs/tags/0.1.3") {
      return { stdout: "", stderr: "", status: 0 };
    }
    if (key === "git diff HEAD --name-only") {
      return {
        stdout: `${fixture.expectedVersionedPaths.join("\n")}\n`,
        stderr: "",
        status: 0
      };
    }
    if (key === "git ls-files --others --exclude-standard") {
      return { stdout: "", stderr: "", status: 0 };
    }
    return { stdout: "", stderr: "", status: 0 };
  };

  try {
    const result = prepareRelease({
      projectRoot: fixture.root,
      version: "0.1.3",
      commandRunner
    });

    assert.deepEqual(result, {
      branch: "develop",
      previousVersion: "0.1.2",
      version: "0.1.3",
      tag: "0.1.3"
    });
    assert.deepEqual(versionConsistencyIssues(fixture.root), []);
    assert.deepEqual(calls, [
      ["git", "status", "--porcelain"],
      ["git", "branch", "--show-current"],
      ["git", "rev-parse", "HEAD"],
      ["git", "ls-remote", "--heads", "origin", "refs/heads/develop"],
      ["git", "tag", "--list", "0.1.3"],
      ["git", "ls-remote", "--tags", "origin", "refs/tags/0.1.3"],
      ["npm", "test"],
      ["swift", "test", "--parallel"],
      ["swift", "build", "-c", "release", "--product", "astrolabe"],
      ["git", "diff", "HEAD", "--name-only"],
      ["git", "ls-files", "--others", "--exclude-standard"],
      ["git", "diff", "--check"],
      ["git", "add", "--", ...fixture.expectedVersionedPaths],
      ["git", "diff", "--staged", "--check"],
      ["git", "commit", "-m", "chore: release 0.1.3"],
      ["git", "tag", "-a", "0.1.3", "-m", "Astrolabe 0.1.3"]
    ]);
    assert.equal(calls.some((call) => call.includes("push")), false);
  } finally {
    fixture.cleanup();
  }
});

test("release preparation rejects unexpected files created by verification", () => {
  const fixture = makeVersionFixture();
  const commandRunner = (command, args) => {
    const key = [command, ...args].join(" ");
    if (key === "git branch --show-current") {
      return { stdout: "develop\n", stderr: "", status: 0 };
    }
    if (key === "git rev-parse HEAD") {
      return { stdout: "abc123\n", stderr: "", status: 0 };
    }
    if (key === "git ls-remote --heads origin refs/heads/develop") {
      return {
        stdout: "abc123\trefs/heads/develop\n",
        stderr: "",
        status: 0
      };
    }
    if (key === "git diff HEAD --name-only") {
      return {
        stdout: `${fixture.expectedVersionedPaths.join("\n")}\nREADME.md\n`,
        stderr: "",
        status: 0
      };
    }
    return { stdout: "", stderr: "", status: 0 };
  };

  try {
    assert.throws(
      () => prepareRelease({
        projectRoot: fixture.root,
        version: "0.1.3",
        commandRunner
      }),
      /Unexpected non-version file changes: README\.md/
    );
  } finally {
    fixture.cleanup();
  }
});

test("release preparation rejects untracked files created by verification", () => {
  const fixture = makeVersionFixture();
  const commandRunner = (command, args) => {
    const key = [command, ...args].join(" ");
    if (key === "git branch --show-current") {
      return { stdout: "develop\n", stderr: "", status: 0 };
    }
    if (key === "git rev-parse HEAD") {
      return { stdout: "abc123\n", stderr: "", status: 0 };
    }
    if (key === "git ls-remote --heads origin refs/heads/develop") {
      return {
        stdout: "abc123\trefs/heads/develop\n",
        stderr: "",
        status: 0
      };
    }
    if (key === "git diff HEAD --name-only") {
      return {
        stdout: `${fixture.expectedVersionedPaths.join("\n")}\n`,
        stderr: "",
        status: 0
      };
    }
    if (key === "git ls-files --others --exclude-standard") {
      return { stdout: "generated.txt\n", stderr: "", status: 0 };
    }
    return { stdout: "", stderr: "", status: 0 };
  };

  try {
    assert.throws(
      () => prepareRelease({
        projectRoot: fixture.root,
        version: "0.1.3",
        commandRunner
      }),
      /Untracked files found: generated\.txt/
    );
  } finally {
    fixture.cleanup();
  }
});

test("release preparation rejects a branch that differs from its remote", () => {
  const fixture = makeVersionFixture();
  const commandRunner = (command, args) => {
    const key = [command, ...args].join(" ");
    if (key === "git branch --show-current") {
      return { stdout: "develop\n", stderr: "", status: 0 };
    }
    if (key === "git rev-parse HEAD") {
      return { stdout: "local123\n", stderr: "", status: 0 };
    }
    if (key === "git ls-remote --heads origin refs/heads/develop") {
      return {
        stdout: "remote456\trefs/heads/develop\n",
        stderr: "",
        status: 0
      };
    }
    return { stdout: "", stderr: "", status: 0 };
  };

  try {
    assert.throws(
      () => prepareRelease({
        projectRoot: fixture.root,
        version: "0.1.3",
        commandRunner
      }),
      /does not match remote branch/
    );
    assert.equal(readJSON(join(fixture.root, "package.json")).version, "0.1.2");
  } finally {
    fixture.cleanup();
  }
});

test("release preparation rejects dirty worktrees before writing files", () => {
  const fixture = makeVersionFixture();
  const commandRunner = (command, args) => {
    if ([command, ...args].join(" ") === "git status --porcelain") {
      return { stdout: " M README.md\n", stderr: "", status: 0 };
    }
    return { stdout: "", stderr: "", status: 0 };
  };

  try {
    assert.throws(
      () => prepareRelease({
        projectRoot: fixture.root,
        version: "0.1.3",
        commandRunner
      }),
      /Working tree is not clean/
    );
    assert.equal(readJSON(join(fixture.root, "package.json")).version, "0.1.2");
  } finally {
    fixture.cleanup();
  }
});

test("release preparation rejects a prerelease protocol dependency", () => {
  const fixture = makeVersionFixture();
  const commandRunner = (command, args) => {
    const key = [command, ...args].join(" ");
    if (key === "git branch --show-current") {
      return { stdout: "develop\n", stderr: "", status: 0 };
    }
    if (key === "git rev-parse HEAD") {
      return { stdout: "abc123\n", stderr: "", status: 0 };
    }
    if (key === "git ls-remote --heads origin refs/heads/develop") {
      return {
        stdout: "abc123\trefs/heads/develop\n",
        stderr: "",
        status: 0
      };
    }
    return { stdout: "", stderr: "", status: 0 };
  };

  try {
    writeFileSync(
      join(fixture.root, "Package.swift"),
      '.package(url: "https://github.com/regulusleow/astrolabe-protocol.git", exact: "2.0.0-rc.1")\n'
    );

    assert.throws(
      () => prepareRelease({
        projectRoot: fixture.root,
        version: "2.0.0",
        commandRunner
      }),
      /stable Astrolabe Protocol version/
    );
    writeFileSync(
      join(fixture.root, "Package.swift"),
      '.package(url: "https://github.com/regulusleow/astrolabe-protocol.git", exact: "1.9.0")\n'
    );
    assert.throws(
      () => prepareRelease({
        projectRoot: fixture.root,
        version: "2.0.0",
        commandRunner
      }),
      /same major version/
    );
    assert.equal(readJSON(join(fixture.root, "package.json")).version, "0.1.2");
  } finally {
    fixture.cleanup();
  }
});

function makeVersionFixture() {
  const root = mkdtempSync(join(tmpdir(), "astrolabe-version-test-"));
  const swiftPath = "Sources/AstrolabeCLI/CommandLine/AstrolabeHostMetadata.swift";
  const documentationPath = "docs/protocol-architecture.md";
  const expectedVersionedPaths = [
    "Sources/AstrolabeCLI/CommandLine/AstrolabeHostMetadata.swift",
    "docs/protocol-architecture.md",
    "mcp-adapter/package-lock.json",
    "mcp-adapter/package.json",
    "package-lock.json",
    "package.json"
  ];

  mkdirSync(join(root, "Sources/AstrolabeCLI/CommandLine"), { recursive: true });
  mkdirSync(join(root, "docs"), { recursive: true });
  mkdirSync(join(root, "mcp-adapter"), { recursive: true });

  writeJSON(join(root, "package.json"), {
    name: "astrolabe",
    version: "0.1.2"
  });
  writeJSON(join(root, "package-lock.json"), {
    name: "astrolabe",
    version: "0.1.2",
    lockfileVersion: 3,
    packages: {
      "": { name: "astrolabe", version: "0.1.2" }
    }
  });
  writeJSON(join(root, "mcp-adapter/package.json"), {
    name: "@astrolabe/mcp-adapter",
    version: "0.1.2"
  });
  writeJSON(join(root, "mcp-adapter/package-lock.json"), {
    name: "@astrolabe/mcp-adapter",
    version: "0.1.2",
    lockfileVersion: 3,
    packages: {
      "": { name: "@astrolabe/mcp-adapter", version: "0.1.2" }
    }
  });
  writeFileSync(
    join(root, swiftPath),
    "enum AstrolabeHostMetadata {\n    static let version = \"0.1.2\"\n}\n"
  );
  writeFileSync(
    join(root, documentationPath),
    "| Product | `astrolabe 0.1.2` | Host release |\n"
  );
  writeFileSync(
    join(root, "Package.swift"),
    '.package(url: "https://github.com/regulusleow/astrolabe-protocol.git", exact: "0.1.5")\n'
  );

  return {
    root,
    swiftPath,
    documentationPath,
    expectedVersionedPaths,
    cleanup: () => rmSync(root, { recursive: true, force: true })
  };
}

function readJSON(path) {
  return JSON.parse(readFileSync(path, "utf8"));
}

function writeJSON(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}
