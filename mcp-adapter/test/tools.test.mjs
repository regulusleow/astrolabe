import test from "node:test";
import assert from "node:assert/strict";
import { registerInspectorTools } from "../dist/tools.js";

const expectedToolNames = [
  "list_apps",
  "capture_hierarchy",
  "query_ui_graph",
  "capture_screenshot",
  "list_patchable_attributes",
  "apply_attribute_patch",
  "list_attribute_patches",
  "revert_attribute_patch",
  "clear_attribute_patches",
  "compare_screenshot",
  "inspect_diff",
  "record_baseline",
  "compare_baseline",
  "node_detail",
  "summarize_node_detail",
  "check_node_detail",
  "check_style",
  "summarize_hierarchy",
  "inspect_screen",
  "find_nodes",
  "inspect_node",
  "check_node",
  "check_layout"
].sort();

test("MCP keeps the 23 platform-neutral tool names and advertises output envelopes", () => {
  const server = new FakeServer();
  registerInspectorTools(server, "/tmp/astrolabe", async () => successResult({}));

  assert.deepEqual([...server.configs.keys()].sort(), expectedToolNames);
  for (const [toolName, config] of server.configs) {
    assert.ok(config.outputSchema, `${toolName} is missing outputSchema`);
    assert.equal(config.outputSchema.success.parse(true), true);
    assert.equal(config.outputSchema.schemaVersion.parse(4), 4);
  }
  assert.equal([...server.configs.keys()].some((name) => name.startsWith("ios_")), false);
  assert.equal([...server.configs.keys()].some((name) => name.startsWith("android_")), false);
});

test("MCP tool descriptions expose discovery, snapshot, coordinate, and source contracts", () => {
  const server = new FakeServer();
  registerInspectorTools(server, "/tmp/astrolabe", async () => successResult({}));

  assert.match(server.configs.get("list_apps").description, /platform/);
  assert.match(server.configs.get("list_apps").description, /capabilities/);
  assert.match(server.configs.get("inspect_screen").description, /snapshotId/);
  assert.match(server.configs.get("inspect_screen").description, /logical/);
  assert.match(server.configs.get("capture_screenshot").description, /pixel/);
  assert.match(server.configs.get("capture_screenshot").description, /source/);
});

test("registerInspectorTools wires list_apps to the list-apps CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ ok: true });
  });

  const response = await server.handlers.get("list_apps")({});

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: ["list-apps", "--json"]
    }
  ]);
  assert.equal(response.isError, false);
});

test("hierarchy and node tools forward the explicit page snapshot id", async () => {
  const server = new FakeServer();
  const calls = [];
  const snapshotId = "11111111-1111-1111-1111-111111111111";

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({});
  });

  await server.handlers.get("capture_hierarchy")({ appId: "app-1", snapshotId });
  await server.handlers.get("node_detail")({ appId: "app-1", snapshotId, oid: "2" });
  await server.handlers.get("summarize_node_detail")({ appId: "app-1", snapshotId, oid: "2" });
  await server.handlers.get("check_node_detail")({
    appId: "app-1",
    snapshotId,
    oid: "2",
    attribute: "fontSize"
  });
  await server.handlers.get("check_style")({
    appId: "app-1",
    snapshotId,
    oid: "2",
    expectations: [{ attribute: "fontSize", expectedValue: "12" }]
  });
  await server.handlers.get("summarize_hierarchy")({ appId: "app-1", snapshotId });
  await server.handlers.get("inspect_screen")({ appId: "app-1", snapshotId });
  await server.handlers.get("find_nodes")({ appId: "app-1", snapshotId, oid: "2" });
  await server.handlers.get("inspect_node")({ appId: "app-1", snapshotId, oid: "2" });
  await server.handlers.get("check_node")({
    appId: "app-1",
    snapshotId,
    oid: "2",
    expectedVisible: true
  });
  await server.handlers.get("check_layout")({
    appId: "app-1",
    snapshotId,
    from: { oid: "2" },
    to: { oid: "3" },
    relation: "vertical-spacing",
    expectedValue: 10
  });

  assert.equal(calls.length, 11);
  for (const call of calls) {
    const snapshotFlagIndex = call.args.indexOf("--snapshot-id");
    assert.notEqual(snapshotFlagIndex, -1, `${call.args[0]} is missing --snapshot-id`);
    assert.equal(call.args[snapshotFlagIndex + 1], snapshotId);
  }
});

test("node identifiers remain opaque strings across MCP tool schemas", () => {
  const server = new FakeServer();
  registerInspectorTools(server, "/tmp/astrolabe", async () => successResult({}));

  for (const toolName of [
    "apply_attribute_patch",
    "node_detail",
    "summarize_node_detail",
    "check_node_detail",
    "check_style",
    "find_nodes",
    "inspect_node",
    "check_node"
  ]) {
    const oidSchema = server.configs.get(toolName).inputSchema.oid;
    assert.equal(oidSchema.parse("node-A"), "node-A");
    assert.throws(() => oidSchema.parse(42));
  }

  const comparisonSchema = server.configs.get("compare_screenshot").inputSchema;
  assert.deepEqual(comparisonSchema.ignoreNodeOids.parse(["node-A"]), ["node-A"]);
  assert.deepEqual(
    comparisonSchema.ignoreNodeQueries.parse([{ oid: "node-A" }]),
    [{ oid: "node-A" }]
  );
  const layoutSchema = server.configs.get("check_layout").inputSchema;
  assert.deepEqual(layoutSchema.from.parse({ oid: "node-A" }), { oid: "node-A" });
  assert.equal(
    server.configs.get("revert_attribute_patch").inputSchema.patchId.parse("patch-A"),
    "patch-A"
  );
});

test("registerInspectorTools bounds capture_hierarchy output by default", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ root: { className: "UIView" } });
  });

  const response = await server.handlers.get("capture_hierarchy")({
    appId: "app-1",
    maxDepth: 8
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: ["capture-hierarchy", "app-1", "--node-limit", "25", "--max-depth", "8", "--json"]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { root: { className: "UIView" } });
});

test("registerInspectorTools delegates required UI graph input without duplicating native defaults", async () => {
  const server = new FakeServer();
  const calls = [];
  const snapshotId = "11111111-1111-1111-1111-111111111111";

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ nodes: [{ oid: "view-A" }], relations: [] });
  });

  const response = await server.handlers.get("query_ui_graph")({
    appId: "app-1",
    snapshotId,
    rootOid: "view-A",
    relationTypes: ["ios.view.backingLayer"]
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "query-ui-graph",
        "app-1",
        "--snapshot-id",
        snapshotId,
        "--root-oid",
        "view-A",
        "--relation",
        "ios.view.backingLayer",
        "--json"
      ]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, {
    nodes: [{ oid: "view-A" }],
    relations: []
  });
});

test("registerInspectorTools forwards every supplied UI graph bound in stable order", async () => {
  const server = new FakeServer();
  const calls = [];
  const snapshotId = "11111111-1111-1111-1111-111111111111";

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ truncated: true, truncationReasons: ["nodeLimit"] });
  });

  await server.handlers.get("query_ui_graph")({
    appId: "app-1",
    snapshotId,
    rootOid: "layer-A",
    relationTypes: ["ios.view.backingLayer", "tree.layerChild"],
    direction: "both",
    maxDepth: 4,
    nodeLimit: 100,
    relationLimit: 200,
    byteLimit: 262144
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "query-ui-graph",
        "app-1",
        "--snapshot-id",
        snapshotId,
        "--root-oid",
        "layer-A",
        "--relation",
        "ios.view.backingLayer",
        "--relation",
        "tree.layerChild",
        "--direction",
        "both",
        "--max-depth",
        "4",
        "--node-limit",
        "100",
        "--relation-limit",
        "200",
        "--byte-limit",
        "262144",
        "--json"
      ]
    }
  ]);
});

test("query_ui_graph schema enforces frozen snapshot and native public bounds", () => {
  const server = new FakeServer();
  registerInspectorTools(server, "/tmp/astrolabe", async () => successResult({}));
  const schema = server.configs.get("query_ui_graph").inputSchema;
  const snapshotId = "11111111-1111-1111-1111-111111111111";

  assert.equal(schema.snapshotId.parse(snapshotId), snapshotId);
  assert.throws(() => schema.snapshotId.parse("latest"));
  assert.equal(schema.rootOid.parse("node-A"), "node-A");
  assert.throws(() => schema.rootOid.parse(""));
  assert.deepEqual(
    schema.relationTypes.parse(["ios.view.backingLayer"]),
    ["ios.view.backingLayer"]
  );
  assert.throws(() => schema.relationTypes.parse([]));
  assert.equal(schema.direction.parse("incoming"), "incoming");
  assert.throws(() => schema.direction.parse("sideways"));

  for (const [name, lowerOverflow, upperOverflow] of [
    ["maxDepth", 0, 5],
    ["nodeLimit", 0, 101],
    ["relationLimit", 0, 201],
    ["byteLimit", 1023, 262145]
  ]) {
    assert.throws(() => schema[name].parse(lowerOverflow));
    assert.throws(() => schema[name].parse(upperOverflow));
  }
});

test("registerInspectorTools wires capture_screenshot to the CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ screenshot: { outputPath: "/tmp/screen.png", format: "png" } });
  });

  const response = await server.handlers.get("capture_screenshot")({
    appId: "app-1",
    outputPath: "/tmp/screen.png"
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: ["capture-screenshot", "app-1", "--output", "/tmp/screen.png", "--json"]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { screenshot: { outputPath: "/tmp/screen.png", format: "png" } });
});

test("registerInspectorTools forwards screenshot source options", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ screenshot: { outputPath: "/tmp/screen.png", source: "simulator" } });
  });

  await server.handlers.get("capture_screenshot")({
    appId: "app-1",
    outputPath: "/tmp/screen.png",
    source: "physical",
    targetIdentifier: "DEVICE-1"
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "capture-screenshot",
        "app-1",
        "--output",
        "/tmp/screen.png",
        "--source",
        "physical",
        "--target-id",
        "DEVICE-1",
        "--json"
      ]
    }
  ]);
});

test("registerInspectorTools forwards platform-neutral screenshot target", async () => {
  const calls = [];
  const server = new FakeServer();
  registerInspectorTools(server, "/tmp/astrolabe", async (_bin, args) => {
    calls.push(args);
    return successResult({ screenshot: { outputPath: "/tmp/screen.png", source: "emulator" } });
  });

  await server.handlers.get("capture_screenshot")({
    appId: "android:app-1",
    outputPath: "/tmp/screen.png",
    source: "virtual",
    targetIdentifier: "EMULATOR-1"
  });

  assert.deepEqual(calls[0], [
    "capture-screenshot",
    "android:app-1",
    "--output",
    "/tmp/screen.png",
    "--source",
    "virtual",
    "--target-id",
    "EMULATOR-1",
    "--json"
  ]);
});

test("registerInspectorTools wires temporary attribute patch lifecycle", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ ok: true });
  });

  await server.handlers.get("list_patchable_attributes")({ appId: "app-1" });
  await server.handlers.get("apply_attribute_patch")({
    appId: "app-1",
    oid: "17",
    attribute: "label.fontSize",
    value: "8"
  });
  await server.handlers.get("list_attribute_patches")({ appId: "app-1" });
  await server.handlers.get("revert_attribute_patch")({
    appId: "app-1",
    patchId: "7b9c9e62-73de-4baa-8819-6dcfcebf6e30"
  });
  await server.handlers.get("clear_attribute_patches")({ appId: "app-1" });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: ["list-patchable-attributes", "app-1", "--json"]
    },
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "apply-attribute-patch",
        "app-1",
        "17",
        "--attribute",
        "label.fontSize",
        "--value",
        "8",
        "--json"
      ]
    },
    {
      inspectorBin: "/tmp/astrolabe",
      args: ["list-attribute-patches", "app-1", "--json"]
    },
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "revert-attribute-patch",
        "app-1",
        "7b9c9e62-73de-4baa-8819-6dcfcebf6e30",
        "--json"
      ]
    },
    {
      inspectorBin: "/tmp/astrolabe",
      args: ["clear-attribute-patches", "app-1", "--json"]
    }
  ]);
});

test("registerInspectorTools wires compare_screenshot to the CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ passed: true, mismatchRatio: 0 });
  });

  const response = await server.handlers.get("compare_screenshot")({
    appId: "app-1",
    expectedPath: "/tmp/expected.png",
    actualOutputPath: "/tmp/actual.png",
    diffOutputPath: "/tmp/diff.png",
    threshold: 0.01,
    pixelTolerance: 2,
    regionLimit: 5,
    ignoreRegions: [
      {
        x: 0,
        y: 0,
        width: 10,
        height: 20
      }
    ],
    ignoreNodeOids: ["42"],
    ignoreMasks: ["statusBar"],
    ignoreNodeQueries: [{ className: "UILabel", text: "Timer", semanticRole: "timer", visibleOnly: true, limit: 1 }],
    includeNodes: true,
    nodeLimit: 3,
    source: "virtual",
    targetIdentifier: "SIM-1",
    allowLowResolution: true
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "compare-screenshot",
        "app-1",
        "--expected",
        "/tmp/expected.png",
        "--source",
        "virtual",
        "--target-id",
        "SIM-1",
        "--actual-output",
        "/tmp/actual.png",
        "--diff-output",
        "/tmp/diff.png",
        "--threshold",
        "0.01",
        "--pixel-tolerance",
        "2",
        "--region-limit",
        "5",
        "--ignore-region",
        "0",
        "0",
        "10",
        "20",
        "--ignore-node-oid",
        "42",
        "--ignore-mask",
        "statusBar",
        "--ignore-node-query",
        "--query-class",
        "UILabel",
        "--query-text",
        "Timer",
        "--query-role",
        "timer",
        "--query-visible-only",
        "--query-limit",
        "1",
        "--include-nodes",
        "--node-limit",
        "3",
        "--allow-low-resolution",
        "--json"
      ]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { passed: true, mismatchRatio: 0 });
});

test("registerInspectorTools wires inspect_diff to the CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ passed: false, likelyCauses: [{ oid: "42" }] });
  });

  const response = await server.handlers.get("inspect_diff")({
    appId: "app-1",
    expectedPath: "/tmp/expected.png",
    diffOutputPath: "/tmp/diff.png",
    ignoreNodeOids: ["42"],
    ignoreMasks: ["homeIndicator"],
    ignoreNodeQueries: [{ text: "Timer", limit: 1 }],
    nodeLimit: 4,
    source: "virtual",
    targetIdentifier: "SIM-1"
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "inspect-diff",
        "app-1",
        "--expected",
        "/tmp/expected.png",
        "--source",
        "virtual",
        "--target-id",
        "SIM-1",
        "--diff-output",
        "/tmp/diff.png",
        "--ignore-node-oid",
        "42",
        "--ignore-mask",
        "homeIndicator",
        "--ignore-node-query",
        "--query-text",
        "Timer",
        "--query-limit",
        "1",
        "--include-nodes",
        "--node-limit",
        "4",
        "--json"
      ]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { passed: false, likelyCauses: [{ oid: "42" }] });
});

test("registerInspectorTools wires inspect_diff baseline to the CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ passed: false, likelyCauses: [{ oid: "42", baselineChangeCount: 2 }] });
  });

  const response = await server.handlers.get("inspect_diff")({
    appId: "app-1",
    baselinePath: "/tmp/home.baseline.json",
    nodeLimit: 4
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "inspect-diff",
        "app-1",
        "--baseline",
        "/tmp/home.baseline.json",
        "--include-nodes",
        "--node-limit",
        "4",
        "--json"
      ]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { passed: false, likelyCauses: [{ oid: "42", baselineChangeCount: 2 }] });
});

test("registerInspectorTools wires record_baseline to the CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ files: { manifestPath: "/tmp/home.baseline.json" } });
  });

  const response = await server.handlers.get("record_baseline")({
    appId: "app-1",
    outputDirectory: "/tmp/baselines",
    name: "home",
    ignoreRegions: [{ x: 1, y: 2, width: 3, height: 4 }],
    ignoreNodeOids: ["7"],
    ignoreMasks: ["navigationBar"],
    ignoreNodeQueries: [{ className: "UIImageView", semanticRole: "avatar", visibleOnly: true, limit: 2 }]
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "record-baseline",
        "app-1",
        "--output-dir",
        "/tmp/baselines",
        "--name",
        "home",
        "--ignore-region",
        "1",
        "2",
        "3",
        "4",
        "--ignore-node-oid",
        "7",
        "--ignore-mask",
        "navigationBar",
        "--ignore-node-query",
        "--query-class",
        "UIImageView",
        "--query-role",
        "avatar",
        "--query-visible-only",
        "--query-limit",
        "2",
        "--json"
      ]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { files: { manifestPath: "/tmp/home.baseline.json" } });
});

test("registerInspectorTools wires compare_baseline to the CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ passed: true, baselineName: "home" });
  });

  const response = await server.handlers.get("compare_baseline")({
    appId: "app-1",
    baselinePath: "/tmp/home.baseline.json",
    threshold: 0.01,
    pixelTolerance: 2,
    ignoreRegions: [{ x: 1, y: 2, width: 3, height: 4 }],
    ignoreNodeOids: ["7"],
    ignoreMasks: ["tabBar"],
    ignoreNodeQueries: [{ oid: "9" }],
    includeNodes: true
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "compare-baseline",
        "app-1",
        "--baseline",
        "/tmp/home.baseline.json",
        "--threshold",
        "0.01",
        "--pixel-tolerance",
        "2",
        "--ignore-region",
        "1",
        "2",
        "3",
        "4",
        "--ignore-node-oid",
        "7",
        "--ignore-mask",
        "tabBar",
        "--ignore-node-query",
        "--query-oid",
        "9",
        "--include-nodes",
        "--json"
      ]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { passed: true, baselineName: "home" });
});

test("registerInspectorTools wires node_detail to the positional CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ text: "Hello" });
  });

  const response = await server.handlers.get("node_detail")({ appId: "app-1", oid: "42" });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: ["node-detail", "app-1", "42", "--json"]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { text: "Hello" });
});

test("registerInspectorTools wires summarize_node_detail to the positional CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ attributeCount: 1, attributes: [{ path: "View.Frame.x" }] });
  });

  const response = await server.handlers.get("summarize_node_detail")({
    appId: "app-1",
    oid: "42",
    filter: "frame"
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: ["summarize-node-detail", "app-1", "42", "--filter", "frame", "--json"]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { attributeCount: 1, attributes: [{ path: "View.Frame.x" }] });
});

test("registerInspectorTools wires check_node_detail to the positional CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ passed: true, failures: [] });
  });

  const response = await server.handlers.get("check_node_detail")({
    appId: "app-1",
    oid: "42",
    attribute: "backgroundColor",
    expectedValue: "1,0,0,1",
    contains: true,
    tolerance: 0.5
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "check-node-detail",
        "app-1",
        "42",
        "--attribute",
        "backgroundColor",
        "--expect-value",
        "1,0,0,1",
        "--contains",
        "--tolerance",
        "0.5",
        "--json"
      ]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { passed: true, failures: [] });
});

test("registerInspectorTools wires check_style to the CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ passed: true, checkedCount: 2 });
  });

  const response = await server.handlers.get("check_style")({
    appId: "app-1",
    oid: "42",
    expectations: [
      { attribute: "fontSize", expectedValue: "12" },
      { attribute: "textColor", expectedValue: "#0080FF" }
    ],
    tolerance: 0.5
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "check-style",
        "app-1",
        "--oid",
        "42",
        "--expect",
        "fontSize",
        "12",
        "--expect",
        "textColor",
        "#0080FF",
        "--tolerance",
        "0.5",
        "--json"
      ]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { passed: true, checkedCount: 2 });
});

test("registerInspectorTools wires summarize_hierarchy to the positional CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ nodeCount: 3, textNodes: [] });
  });

  const response = await server.handlers.get("summarize_hierarchy")({ appId: "app-1" });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: ["summarize-hierarchy", "app-1", "--json"]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { nodeCount: 3, textNodes: [] });
});

test("registerInspectorTools wires inspect_screen to the CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ checkTargets: [{ oid: "42" }] });
  });

  const response = await server.handlers.get("inspect_screen")({
    appId: "app-1",
    targetLimit: 12,
    classLimit: 16
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: ["inspect-screen", "app-1", "--target-limit", "12", "--class-limit", "16", "--json"]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { checkTargets: [{ oid: "42" }] });
});

test("registerInspectorTools wires find_nodes to the positional CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ totalCount: 1, nodes: [{ oid: "42" }] });
  });

  const response = await server.handlers.get("find_nodes")({
    appId: "app-1",
    className: "UILabel",
    text: "Hello",
    semanticRole: "text",
    visibleOnly: true,
    limit: 5,
    cursor: "cursor-1"
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: ["find-nodes", "app-1", "--class", "UILabel", "--text", "Hello", "--role", "text", "--visible-only", "--limit", "5", "--cursor", "cursor-1", "--json"]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { totalCount: 1, nodes: [{ oid: "42" }] });
});

test("registerInspectorTools wires inspect_node to the positional CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ node: { oid: "42" }, detail: { attributeGroupCount: 2 } });
  });

  const response = await server.handlers.get("inspect_node")({
    appId: "app-1",
    className: "UILabel",
    text: "Hello",
    visibleOnly: true
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: ["inspect-node", "app-1", "--class", "UILabel", "--text", "Hello", "--visible-only", "--json"]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { node: { oid: "42" }, detail: { attributeGroupCount: 2 } });
});

test("registerInspectorTools wires check_node to the positional CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ passed: true, failures: [] });
  });

  const response = await server.handlers.get("check_node")({
    appId: "app-1",
    oid: "42",
    className: "UILabel",
    text: "Hello",
    visibleOnly: true,
    expectedClassName: "UILabel",
    expectedText: "Hello",
    expectedVisible: true,
    expectedFrame: {
      x: 16,
      y: 20,
      width: 80,
      height: 20
    },
    tolerance: 0.5
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "check-node",
        "app-1",
        "--oid",
        "42",
        "--class",
        "UILabel",
        "--text",
        "Hello",
        "--visible-only",
        "--expect-class",
        "UILabel",
        "--expect-text",
        "Hello",
        "--expect-visible",
        "true",
        "--expect-frame",
        "16",
        "20",
        "80",
        "20",
        "--tolerance",
        "0.5",
        "--json"
      ]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { passed: true, failures: [] });
});

test("registerInspectorTools wires check_layout to the CLI command", async () => {
  const server = new FakeServer();
  const calls = [];

  registerInspectorTools(server, "/tmp/astrolabe", async (inspectorBin, args) => {
    calls.push({ inspectorBin, args });
    return successResult({ passed: true, actual: 20 });
  });

  const response = await server.handlers.get("check_layout")({
    appId: "app-1",
    from: { oid: "2" },
    to: { text: "Save", visibleOnly: true },
    relation: "vertical-spacing",
    expectedValue: 20,
    tolerance: 0.5
  });

  assert.deepEqual(calls, [
    {
      inspectorBin: "/tmp/astrolabe",
      args: [
        "check-layout",
        "app-1",
        "--from-oid",
        "2",
        "--to-text",
        "Save",
        "--to-visible-only",
        "--relation",
        "vertical-spacing",
        "--expect",
        "20",
        "--tolerance",
        "0.5",
        "--json"
      ]
    }
  ]);
  assert.deepEqual(response.structuredContent.data, { passed: true, actual: 20 });
});

class FakeServer {
  constructor() {
    this.handlers = new Map();
    this.configs = new Map();
  }

  registerTool(name, config, handler) {
    this.handlers.set(name, handler);
    this.configs.set(name, config);
  }
}

function successResult(data) {
  const envelope = {
    success: true,
    data
  };

  return {
    exitedSuccessfully: true,
    envelope,
    stdout: JSON.stringify(envelope),
    stderr: ""
  };
}
