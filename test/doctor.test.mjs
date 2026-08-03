import test from "node:test";
import assert from "node:assert/strict";

import {
  redactText,
  sanitizeDiagnosticReport
} from "../scripts/installation/doctor/redactor.mjs";
import {
  buildDiagnosticReport,
  renderHumanReport,
  renderJSONReport
} from "../scripts/installation/doctor/report.mjs";
import {
  collectAIClientFacts,
  runDoctor
} from "../scripts/installation/doctor/doctor-command.mjs";

function fakeDoctorContext(overrides = {}) {
  const requiredPaths = [
    "/pkg/distribution-manifest.json",
    "/pkg/bin/astrolabe",
    "/pkg/libexec/astrolabe-native",
    "/pkg/libexec/mcp-adapter/dist/index.js",
    "/pkg/skills/astrolabe/SKILL.md",
    "/pkg/LICENSE",
    "/pkg/THIRD_PARTY_NOTICES"
  ];
  return {
    distributionRoot: "/pkg",
    manifest: {
      schemaVersion: 1,
      version: "2.0.0",
      channel: "source",
      platform: "darwin",
      architecture: "arm64",
      nativeExecutable: "libexec/astrolabe-native",
      mcpEntry: "libexec/mcp-adapter/dist/index.js"
    },
    paths: {
      manifestPath: requiredPaths[0],
      publicLauncherPath: requiredPaths[1],
      nativeExecutablePath: requiredPaths[2],
      mcpEntryPath: requiredPaths[3],
      skillPath: requiredPaths[4],
      licensePath: requiredPaths[5],
      thirdPartyNoticesPath: requiredPaths[6]
    },
    homeDirectory: "/Users/alice",
    environment: { SHELL: "/bin/zsh" },
    pathExists: (path) => requiredPaths.includes(path),
    isExecutable: (path) => path === requiredPaths[1] || path === requiredPaths[2],
    nativeProbe: () => ({
      status: 0,
      stdout: '{"success":true,"data":{"version":"2.0.0"}}\n',
      stderr: ""
    }),
    mcpProbe: () => ({ status: 0, stdout: '{"version":"2.0.0"}\n', stderr: "" }),
    clientFacts: [
      { id: "codex", status: "NOT CONFIGURED", detail: "Not configured" }
    ],
    pathEntries: [requiredPaths[1]],
    stdout: { write() {} },
    stderr: { write() {} },
    ...overrides
  };
}

test("doctor redacts credentials paths identifiers and nested error text", () => {
  const raw = {
    environment: {
      NPM_TOKEN: "npm_secret_value",
      PATH: "/Users/alice/bin:/usr/bin"
    },
    urls: ["https://user:pass@example.com/path?token=query-secret"],
    deviceIdentifiers: ["00008110-001234567890001E"],
    error: "Bearer ghp_example at /Users/alice/project"
  };

  const sanitized = sanitizeDiagnosticReport(raw, {
    homeDirectory: "/Users/alice"
  });
  const text = JSON.stringify(sanitized);

  assert.doesNotMatch(
    text,
    /npm_secret_value|query-secret|ghp_example|001234567890001E|\/Users\/alice/
  );
  assert.match(text, /<redacted>/);
  assert.match(text, /<home-path>/);
  assert.match(text, /<device:[a-f0-9]{8}>/);
});

test("doctor defaults unknown environment values to redacted", () => {
  const sanitized = sanitizeDiagnosticReport({
    environment: {
      UNKNOWN_VALUE: "private-value",
      SHELL: "/bin/zsh"
    }
  }, { homeDirectory: "/Users/alice" });

  assert.deepEqual(sanitized.environment, {
    UNKNOWN_VALUE: "<redacted>",
    SHELL: "<path>"
  });
});

test("doctor redacts every absolute PATH entry", () => {
  const sanitized = sanitizeDiagnosticReport({
    environment: {
      PATH: "/Users/alice/bin:/opt/homebrew/bin:/usr/bin"
    }
  }, { homeDirectory: "/Users/alice" });

  assert.equal(sanitized.environment.PATH, "<home-path>:<path>:<path>");
});

test("doctor redacts values stored under secret-shaped object fields", () => {
  const sanitized = sanitizeDiagnosticReport({
    nested: {
      accessToken: "raw-access-token",
      api_key: "raw-api-key",
      safe: "visible"
    }
  }, { homeDirectory: "/Users/alice" });

  assert.deepEqual(sanitized, {
    nested: {
      accessToken: "<redacted>",
      api_key: "<redacted>",
      safe: "visible"
    }
  });
});

test("doctor redacts common authorization and URL secret forms", () => {
  const source = [
    "Authorization: Basic dXNlcjpwYXNz",
    "password=hunter2",
    "https://name:pass@example.com/path?api_key=secret-value&safe=value",
    "//registry.npmjs.org/:_authToken=npm-token-value"
  ].join("\n");

  const sanitized = redactText(source, { homeDirectory: "/Users/alice" });

  assert.doesNotMatch(sanitized, /dXNlcjpwYXNz|hunter2|secret-value|npm-token-value|name:pass/);
  assert.match(sanitized, /safe=value/);
});

test("doctor redacts npm tokens and absolute paths from free-form failures", () => {
  const sanitized = redactText(
    "failure npm_abcdefghijklmnopqrstuvwxyz0123456789 at /private/tmp/customer/project",
    { homeDirectory: "/Users/alice" }
  );

  assert.doesNotMatch(sanitized, /npm_[A-Za-z0-9]+|\/private\/tmp\/customer/);
  assert.match(sanitized, /<redacted>|<path>/);
});

test("doctor recursively redacts Unicode home paths", () => {
  const sanitized = sanitizeDiagnosticReport({
    nested: [{ path: "/Users/example-user/project/file.log" }]
  }, { homeDirectory: "/Users/example-user" });

  assert.deepEqual(sanitized, {
    nested: [{ path: "<home-path>" }]
  });
});

test("doctor human and JSON renderers receive the same sanitized report", async () => {
  const report = await buildDiagnosticReport(fakeDoctorContext());

  assert.equal(report.success, true);
  assert.match(renderHumanReport(report), /Astrolabe installation\s+PASS/);
  assert.deepEqual(JSON.parse(renderJSONReport(report)), report);
});

test("doctor fails when the native executable is missing", async () => {
  const output = [];
  const context = fakeDoctorContext({
    pathExists(path) {
      return path !== "/pkg/libexec/astrolabe-native";
    },
    stdout: { write: (value) => output.push(value) }
  });

  const exitCode = await runDoctor(["--verbose", "--json"], context);

  assert.equal(exitCode, 1);
  assert.equal(JSON.parse(output.join("")).success, false);
});

test("doctor fails when native or MCP runtime versions differ from the manifest", async () => {
  const nativeReport = await buildDiagnosticReport(fakeDoctorContext({
    nativeProbe: () => ({
      status: 0,
      stdout: '{"success":true,"data":{"version":"1.9.0"}}\n',
      stderr: ""
    })
  }));
  const mcpReport = await buildDiagnosticReport(fakeDoctorContext({
    mcpProbe: () => ({ status: 0, stdout: '{"version":"1.9.0"}\n', stderr: "" })
  }));

  assert.equal(nativeReport.success, false);
  assert.equal(mcpReport.success, false);
});

test("doctor fails when the Distribution platform or architecture differs from the host", async () => {
  const report = await buildDiagnosticReport(fakeDoctorContext({
    hostPlatform: "linux",
    hostArchitecture: "x86_64"
  }));

  assert.equal(report.success, false);
  assert.equal(report.checks.find((item) => item.id === "host").status, "FAIL");
});

test("doctor fails when the MCP runtime cannot load production dependencies", async () => {
  const report = await buildDiagnosticReport(fakeDoctorContext({
    mcpProbe: () => ({ status: 1, stdout: "", stderr: "module not found" })
  }));

  assert.equal(report.success, false);
  assert.equal(report.checks.find((item) => item.id === "mcp").status, "FAIL");
});

test("doctor rejects JSON output without verbose mode", async () => {
  const errors = [];
  const exitCode = await runDoctor(["--json"], fakeDoctorContext({
    stderr: { write: (value) => errors.push(value) }
  }));

  assert.equal(exitCode, 2);
  assert.match(errors.join(""), /--json requires --verbose/);
});

test("doctor sanitizes a manifest initialization failure", async () => {
  const output = [];
  const exitCode = await runDoctor(["--verbose", "--json"], {
    distributionRoot: "/Users/alice/private-distribution",
    homeDirectory: "/Users/alice",
    environment: {},
    stdout: { write: (value) => output.push(value) },
    stderr: { write() {} }
  });
  const text = output.join("");

  assert.equal(exitCode, 1);
  assert.doesNotMatch(text, /\/Users\/alice|private-distribution/);
  assert.equal(JSON.parse(text).success, false);
});

test("doctor reports every supported AI client from its real configuration state", () => {
  const facts = collectAIClientFacts({
    all: () => [
      { id: "codex", isConfigured: () => false, check: () => [] },
      { id: "opencode", isConfigured: () => true, check: () => [] },
      {
        id: "claude-code",
        isConfigured: () => true,
        check: () => ["Managed launcher is stale"]
      }
    ]
  });

  assert.deepEqual(facts, [
    { id: "codex", status: "NOT CONFIGURED", detail: "Not configured" },
    { id: "opencode", status: "PASS", detail: "Configured" },
    { id: "claude-code", status: "FAIL", detail: "Managed launcher is stale" }
  ]);
});
