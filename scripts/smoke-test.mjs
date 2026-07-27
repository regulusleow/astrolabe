#!/usr/bin/env node

import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  collectObjects,
  findReversibleStringPatch,
  pickApp,
  pickInspectableClassName,
  retryUntilApps
} from "./smoke-utils.mjs";
import { canonicalRepositoryVersion } from "./versioning.mjs";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const projectRoot = resolve(scriptDir, "..");
const hostVersion = canonicalRepositoryVersion(projectRoot);
const inspectorBin = process.env.ASTROLABE_BIN ?? resolve(projectRoot, ".build/debug/astrolabe");
const mcpEntry = process.env.ASTROLABE_MCP_ENTRY ?? resolve(projectRoot, "mcp-adapter/dist/index.js");
const args = new Set(process.argv.slice(2));
const shouldRunCLI = !args.has("--mcp-only");
const shouldRunMCP = !args.has("--cli-only");
const selectedConnectionKind = process.env.ASTROLABE_CONNECTION_KIND
  ?? (
    args.has("--usb-only")
      ? "usb"
      : args.has("--emulator-only")
        ? "emulator"
        : args.has("--simulator-only")
          ? "simulator"
          : ""
  );
const selectedScreenshotSource = process.env.ASTROLABE_SCREENSHOT_SOURCE ?? "";
const selectedScreenshotTargetIdentifier = process.env.ASTROLABE_SCREENSHOT_TARGET_ID ?? "";
const expectedMCPToolNames = [
  "list_apps",
  "capture_hierarchy",
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

let selectedAppId = process.env.ASTROLABE_APP_ID ?? "";
let selectedOid = process.env.ASTROLABE_OID?.trim() ?? "";

async function main() {
  if (args.has("--help") || args.has("-h")) {
    printHelp();
    return;
  }

  if (shouldRunCLI) {
    await runCLISmokeTest();
  }

  if (shouldRunMCP) {
    await runMCPSmokeTest();
  }
}

function printHelp() {
  console.log(`Usage:
  npm test
  npm run test:cli
  npm run test:mcp
  npm run test:usb

Environment variables:
  ASTROLABE_BIN       Path to the astrolabe binary
  ASTROLABE_MCP_ENTRY Path to the MCP adapter entry point
  ASTROLABE_APP_ID    App to test
  ASTROLABE_OID       Node OID whose details should be read
  ASTROLABE_CONNECTION_KIND Connection kind: simulator or usb
  ASTROLABE_SCREENSHOT_SOURCE Screenshot source: auto, virtual, or physical
  ASTROLABE_SCREENSHOT_TARGET_ID Target identifier for the virtual or physical device

Options:
  --usb-only       Select only an App on a physical USB device
  --simulator-only Select only a simulator App
`);
}

function assertPagesDoNotOverlap(firstPage, secondPage, label) {
  assert(Array.isArray(secondPage), `${label} next page did not return a nodes array`);
  const firstOids = new Set(firstPage.map((node) => node.oid));
  assert(secondPage.every((node) => !firstOids.has(node.oid)), `${label} next page returned duplicate nodes`);
}

async function runCLISmokeTest() {
  assertFileExists(inspectorBin, `CLI binary not found: ${inspectorBin}\nRun this command first: swift build`);

  const apps = await retryUntilApps(async () => {
    const listApps = runInspector(["list-apps", "--json"]);
    const fetchedApps = listApps.data?.apps;
    assert(Array.isArray(fetchedApps), "list-apps did not return apps array");
    return fetchedApps;
  });

  const app = pickApp(apps, selectedAppId, { connectionKind: selectedConnectionKind });
  selectedAppId = app.appId;
  assert(typeof app.platform === "string" && app.platform.length > 0, "list-apps did not return platform");
  assert(Array.isArray(app.capabilities), "list-apps did not return capabilities");
  assert(typeof app.compatibility?.status === "string", "list-apps did not return compatibility.status");
  console.log(`CLI list-apps passed: ${app.displayName} (${app.applicationIdentifier}) connectionKind=${app.connectionKind}`);

  const hierarchy = runInspector([
    "capture-hierarchy",
    selectedAppId,
    "--node-limit",
    "200",
    "--json"
  ]);
  const hierarchyNodes = collectObjects(hierarchy.data, (item) => typeof item.className === "string");
  assert(hierarchyNodes.length > 0, "capture-hierarchy did not return UI nodes");
  const inspectClassName = pickInspectableClassName(hierarchyNodes);
  console.log(`CLI capture-hierarchy passed: ${hierarchyNodes.length} nodes`);

  const summary = runInspector(["summarize-hierarchy", selectedAppId, "--json"]);
  assert(Number(summary.data?.visibleNodeCount) > 0, "summarize-hierarchy did not return a visible-node count");
  assert(Array.isArray(summary.data?.visibleNodes), "summarize-hierarchy did not return visibleNodes array");
  console.log(`CLI summarize-hierarchy passed: ${summary.data.visibleNodeCount} visible nodes`);

  const screenInspection = runInspector(["inspect-screen", selectedAppId, "--target-limit", "5", "--json"]);
  assert(Array.isArray(screenInspection.data?.classHistogram), "inspect-screen did not return classHistogram array");
  assert(Array.isArray(screenInspection.data?.checkTargets), "inspect-screen did not return checkTargets array");
  assert(screenInspection.data?.visibleNodes === undefined, "inspect-screen must not repeat visibleNodes");
  assert(screenInspection.data?.textNodes === undefined, "inspect-screen must not repeat textNodes");
  assert(JSON.stringify(screenInspection.data).length < 20000, "inspect-screen output is still too large");
  assert(typeof screenInspection.data?.snapshotId === "string", "inspect-screen did not return snapshotId");
  assert(typeof screenInspection.data?.hierarchySource === "string", "inspect-screen did not return hierarchySource");
  assert(screenInspection.data?.checkTargets[0]?.frame?.unit === "logical", "inspect-screen did not declare the logical frame unit");
  console.log(`CLI inspect-screen passed: ${screenInspection.data.checkTargets.length} check targets`);

  const cliScreenshotDir = mkdtempSync(join(tmpdir(), "astrolabe-cli-"));
  try {
    const cliScreenshotPath = join(cliScreenshotDir, "screen.png");
    const cliActualPath = join(cliScreenshotDir, "actual.png");
    const cliDiffPath = join(cliScreenshotDir, "diff.png");
    const cliBaselineDir = join(cliScreenshotDir, "baseline");
    const screenshot = runInspector([
      "capture-screenshot",
      selectedAppId,
      "--output",
      cliScreenshotPath,
      ...buildScreenshotSourceArgs(),
      "--json"
    ]);
    assert(screenshot.data?.screenshot?.format === "png", "capture-screenshot did not return PNG metadata");
    assert(screenshot.data?.screenshot?.outputPath === cliScreenshotPath, "capture-screenshot did not return the output path");
    assert(Number(screenshot.data?.screenshot?.byteCount) > 0, "capture-screenshot did not return the screenshot byte count");
    assert(typeof screenshot.data?.screenshot?.source === "string", "capture-screenshot did not return the actual source");
    assert(Number(screenshot.data?.screenshot?.pixelWidth) > 0, "capture-screenshot did not return pixelWidth");
    assert(Number(screenshot.data?.screenshot?.pointWidth) > 0, "capture-screenshot did not return the logical width");
    assert(Number(screenshot.data?.screenshot?.scale) > 0, "capture-screenshot did not return logical-to-pixel scale");
    assert(existsSync(cliScreenshotPath), "capture-screenshot did not write a PNG file");
    console.log(`CLI capture-screenshot passed: ${screenshot.data.screenshot.byteCount} bytes`);

    const comparison = runInspector([
      "compare-screenshot",
      selectedAppId,
      "--expected",
      cliScreenshotPath,
      ...buildScreenshotComparisonSourceArgs(),
      "--actual-output",
      cliActualPath,
      "--diff-output",
      cliDiffPath,
      "--threshold",
      "0.01",
      "--pixel-tolerance",
      "2",
      "--region-limit",
      "10",
      "--include-nodes",
      "--node-limit",
      "5",
      "--json"
    ]);
    assert(comparison.data?.passed === true, `compare-screenshot failed: ${JSON.stringify(comparison.data)}`);
    assert(Number(comparison.data?.mismatchRatio) <= 0.01, "compare-screenshot mismatchRatio exceeds the threshold");
    assert(Array.isArray(comparison.data?.affectedNodes), "compare-screenshot did not return affectedNodes array");
    assert(existsSync(cliActualPath), "compare-screenshot did not write actual PNG");
    assert(existsSync(cliDiffPath), "compare-screenshot did not write diff PNG");
    console.log(`CLI compare-screenshot passed: mismatchRatio=${comparison.data.mismatchRatio}`);

    const baseline = runInspector([
      "record-baseline",
      selectedAppId,
      "--output-dir",
      cliBaselineDir,
      "--name",
      "smoke",
      ...buildScreenshotSourceArgs(),
      "--json"
    ]);
    assert(existsSync(baseline.data?.files?.manifestPath), "record-baseline did not write manifest");
    assert(existsSync(baseline.data?.files?.screenshotPath), "record-baseline did not write the screenshot");
    assert(existsSync(baseline.data?.files?.hierarchyPath), "record-baseline did not write hierarchy");
    console.log(`CLI record-baseline passed: ${baseline.data.files.manifestPath}`);

    const baselineComparison = runInspector([
      "compare-baseline",
      selectedAppId,
      "--baseline",
      baseline.data.files.manifestPath,
      "--threshold",
      "0.01",
      "--pixel-tolerance",
      "2",
      ...buildScreenshotComparisonSourceArgs(),
      "--json"
    ]);
    assert(baselineComparison.data?.passed === true, `compare-baseline failed: ${JSON.stringify(baselineComparison.data)}`);
    console.log(`CLI compare-baseline passed: baseline=${baselineComparison.data.baselineName}`);
  } finally {
    rmSync(cliScreenshotDir, { recursive: true, force: true });
  }

  const foundNodes = runInspector(["find-nodes", selectedAppId, "--class", inspectClassName, "--visible-only", "--limit", "5", "--json"]);
  assert(Number(foundNodes.data?.totalCount) > 0, "find-nodes found no visible inspectable nodes");
  assert(Array.isArray(foundNodes.data?.nodes), "find-nodes did not return nodes array");
  if (foundNodes.data.hasMore) {
    assert(typeof foundNodes.data.nextCursor === "string", "find-nodes did not return nextCursor");
    const nextPage = runInspector([
      "find-nodes",
      selectedAppId,
      "--class",
      inspectClassName,
      "--visible-only",
      "--limit",
      "5",
      "--cursor",
      foundNodes.data.nextCursor,
      "--json"
    ]);
    assert(nextPage.data?.paginationSnapshotId === foundNodes.data.paginationSnapshotId, "find-nodes next-page snapshot mismatch");
    assertPagesDoNotOverlap(foundNodes.data.nodes, nextPage.data?.nodes, "CLI find-nodes");
  }
  console.log(`CLI find-nodes passed: returned ${foundNodes.data.nodes.length} / ${foundNodes.data.totalCount} nodes`);

  const inspectedNode = runInspector(["inspect-node", selectedAppId, "--class", inspectClassName, "--visible-only", "--json"]);
  assert(inspectedNode.data?.node?.detailOid, "inspect-node did not return node.detailOid");
  const inspectedClassName = inspectedNode.data?.node?.className;
  assert(typeof inspectedClassName === "string" && inspectedClassName.length > 0, "inspect-node did not return node.className");
  assert(Array.isArray(inspectedNode.data?.detail?.attributeGroups), "inspect-node did not return detail.attributeGroups");
  console.log(`CLI inspect-node passed: class=${inspectedClassName}, detailOid=${inspectedNode.data.node.detailOid}`);

  const checkedNode = runInspector(buildCheckNodeArgs(selectedAppId, inspectedClassName));
  assert(checkedNode.data?.passed === true, `check-node check failed: ${JSON.stringify(checkedNode.data?.failures)}`);
  assert(Array.isArray(checkedNode.data?.failures), "check-node did not return failures array");
  console.log(`CLI check-node passed: class=${inspectedClassName}, checked=${checkedNode.data.checkedCount}`);

  if (!selectedOid) {
    selectedOid = inspectedNode.data.node.detailOid;
  }

  const detail = runInspector(["node-detail", selectedAppId, selectedOid, "--json"]);
  const groups = collectObjects(detail.data, (item) => Array.isArray(item.attributes) || Array.isArray(item.sections));
  assert(groups.length > 0, `node-detail did not return attribute groups, oid=${selectedOid}`);
  console.log(`CLI node-detail passed: oid=${selectedOid}, ${groups.length} attribute groups`);

  const detailSummary = runInspector(["summarize-node-detail", selectedAppId, selectedOid, "--json"]);
  assert(Array.isArray(detailSummary.data?.attributes), "summarize-node-detail did not return attributes array");
  assert(Number(detailSummary.data?.attributeCount) > 0, "summarize-node-detail did not return an attribute summary");
  console.log(`CLI summarize-node-detail passed: ${detailSummary.data.attributeCount} attributes`);

  const detailAttribute = pickCheckableDetailAttribute(detailSummary.data.attributes);
  const checkedDetail = runInspector(buildCheckNodeDetailArgs(selectedAppId, selectedOid, detailAttribute));
  assert(checkedDetail.data?.passed === true, `check-node-detail check failed: ${JSON.stringify(checkedDetail.data?.failures)}`);
  assert(Array.isArray(checkedDetail.data?.failures), "check-node-detail did not return failures array");
  console.log(`CLI check-node-detail passed: attribute=${detailAttributeName(detailAttribute)}`);

  runCLIPatchLifecycle(
    selectedAppId,
    selectedOid,
    detailSummary.data.attributes
  );
}

async function runMCPSmokeTest() {
  assertFileExists(mcpEntry, `MCP adapter not found: ${mcpEntry}\nRun this command first: cd mcp-adapter && npm run build`);
  assertFileExists(inspectorBin, `CLI binary not found: ${inspectorBin}\nRun this command first: swift build`);

  const client = new MCPTestClient(mcpEntry, {
    ...process.env,
    ASTROLABE_BIN: inspectorBin
  });

  try {
    await client.start();
    await client.request("initialize", {
      protocolVersion: "2025-06-18",
      capabilities: {},
      clientInfo: {
        name: "astrolabe-smoke-test",
        version: hostVersion
      }
    });
    client.notify("notifications/initialized", {});

    const listedTools = await client.request("tools/list", {});
    const tools = listedTools.tools ?? [];
    const toolNames = tools.map((item) => item.name).sort();
    assert(JSON.stringify(toolNames) === JSON.stringify(expectedMCPToolNames), `MCP Tool tool set changed: ${toolNames.join(", ")}`);
    for (const tool of tools) {
      assert(tool.outputSchema?.properties?.schemaVersion, `${tool.name} did not declare schemaVersion output`);
      assert(tool.outputSchema?.properties?.success, `${tool.name} did not declare success output`);
    }
    console.log(`MCP tools/list passed: ${toolNames.join(", ")}`);

    const apps = await retryUntilApps(async () => {
      const listApps = await client.callTool("list_apps", {});
      const fetchedApps = listApps.structuredContent?.data?.apps;
      assert(Array.isArray(fetchedApps), "MCP list_apps did not return apps array");
      return fetchedApps;
    });
    const app = pickApp(apps, selectedAppId, { connectionKind: selectedConnectionKind });
    selectedAppId = app.appId;
    assert(typeof app.platform === "string" && app.platform.length > 0, "MCP list_apps did not return platform");
    assert(Array.isArray(app.capabilities), "MCP list_apps did not return capabilities");
    assert(typeof app.compatibility?.status === "string", "MCP list_apps did not return compatibility.status");
    console.log(`MCP list_apps passed: ${app.displayName} (${app.applicationIdentifier}) connectionKind=${app.connectionKind}`);

    const hierarchy = await client.callTool("capture_hierarchy", { appId: selectedAppId });
    const hierarchyNodes = collectObjects(hierarchy.structuredContent?.data, (item) => typeof item.className === "string");
    assert(hierarchyNodes.length > 0, "MCP capture_hierarchy did not return UI nodes");
    const inspectClassName = pickInspectableClassName(hierarchyNodes);
    console.log(`MCP capture_hierarchy passed: ${hierarchyNodes.length} nodes`);

    const summary = await client.callTool("summarize_hierarchy", { appId: selectedAppId });
    assert(Number(summary.structuredContent?.data?.visibleNodeCount) > 0, "MCP summarize_hierarchy did not return a visible-node count");
    assert(Array.isArray(summary.structuredContent?.data?.visibleNodes), "MCP summarize_hierarchy did not return visibleNodes array");
    console.log(`MCP summarize_hierarchy passed: ${summary.structuredContent.data.visibleNodeCount} visible nodes`);

    const screenInspection = await client.callTool("inspect_screen", { appId: selectedAppId, targetLimit: 5 });
    assert(Array.isArray(screenInspection.structuredContent?.data?.classHistogram), "MCP inspect_screen did not return classHistogram array");
    assert(Array.isArray(screenInspection.structuredContent?.data?.checkTargets), "MCP inspect_screen did not return checkTargets array");
    assert(screenInspection.structuredContent?.data?.visibleNodes === undefined, "MCP inspect_screen must not repeat visibleNodes");
    assert(screenInspection.structuredContent?.data?.textNodes === undefined, "MCP inspect_screen must not repeat textNodes");
    assert(JSON.stringify(screenInspection.structuredContent?.data).length < 20000, "MCP inspect_screen output is still too large");
    assert(typeof screenInspection.structuredContent?.data?.snapshotId === "string", "MCP inspect_screen did not return snapshotId");
    assert(typeof screenInspection.structuredContent?.data?.hierarchySource === "string", "MCP inspect_screen did not return hierarchySource");
    assert(screenInspection.structuredContent?.data?.checkTargets[0]?.frame?.unit === "logical", "MCP inspect_screen did not declare the logical frame unit");
    console.log(`MCP inspect_screen passed: ${screenInspection.structuredContent.data.checkTargets.length} check targets`);

    const mcpScreenshotDir = mkdtempSync(join(tmpdir(), "astrolabe-mcp-"));
    try {
      const mcpScreenshotPath = join(mcpScreenshotDir, "screen.png");
      const mcpActualPath = join(mcpScreenshotDir, "actual.png");
      const mcpDiffPath = join(mcpScreenshotDir, "diff.png");
      const mcpBaselineDir = join(mcpScreenshotDir, "baseline");
      const screenshot = await client.callTool("capture_screenshot", {
        appId: selectedAppId,
        outputPath: mcpScreenshotPath,
        ...buildMCPScreenshotSourceInput()
      });
      assert(screenshot.structuredContent?.data?.screenshot?.format === "png", "MCP capture_screenshot did not return PNG metadata");
      assert(screenshot.structuredContent?.data?.screenshot?.outputPath === mcpScreenshotPath, "MCP capture_screenshot did not return the output path");
      assert(Number(screenshot.structuredContent?.data?.screenshot?.byteCount) > 0, "MCP capture_screenshot did not return the screenshot byte count");
      assert(typeof screenshot.structuredContent?.data?.screenshot?.source === "string", "MCP capture_screenshot did not return the actual source");
      assert(Number(screenshot.structuredContent?.data?.screenshot?.pixelWidth) > 0, "MCP capture_screenshot did not return pixelWidth");
      assert(Number(screenshot.structuredContent?.data?.screenshot?.pointWidth) > 0, "MCP capture_screenshot did not return the logical width");
      assert(Number(screenshot.structuredContent?.data?.screenshot?.scale) > 0, "MCP capture_screenshot did not return logical-to-pixel scale");
      assert(existsSync(mcpScreenshotPath), "MCP capture_screenshot did not write a PNG file");
      console.log(`MCP capture_screenshot passed: ${screenshot.structuredContent.data.screenshot.byteCount} bytes`);

      const comparison = await client.callTool("compare_screenshot", {
        appId: selectedAppId,
        expectedPath: mcpScreenshotPath,
        actualOutputPath: mcpActualPath,
        diffOutputPath: mcpDiffPath,
        threshold: 0.01,
        pixelTolerance: 2,
        regionLimit: 10,
        includeNodes: true,
        nodeLimit: 5,
        ...buildMCPScreenshotComparisonSourceInput()
      });
      assert(comparison.structuredContent?.data?.passed === true, `MCP compare_screenshot failed: ${JSON.stringify(comparison.structuredContent?.data)}`);
      assert(Number(comparison.structuredContent?.data?.mismatchRatio) <= 0.01, "MCP compare_screenshot mismatchRatio exceeds the threshold");
      assert(Array.isArray(comparison.structuredContent?.data?.affectedNodes), "MCP compare_screenshot did not return affectedNodes array");
      assert(existsSync(mcpActualPath), "MCP compare_screenshot did not write actual PNG");
      assert(existsSync(mcpDiffPath), "MCP compare_screenshot did not write diff PNG");
      console.log(`MCP compare_screenshot passed: mismatchRatio=${comparison.structuredContent.data.mismatchRatio}`);

      const baseline = await client.callTool("record_baseline", {
        appId: selectedAppId,
        outputDirectory: mcpBaselineDir,
        name: "smoke",
        ...buildMCPScreenshotSourceInput()
      });
      assert(existsSync(baseline.structuredContent?.data?.files?.manifestPath), "MCP record_baseline did not write manifest");
      assert(existsSync(baseline.structuredContent?.data?.files?.screenshotPath), "MCP record_baseline did not write the screenshot");
      assert(existsSync(baseline.structuredContent?.data?.files?.hierarchyPath), "MCP record_baseline did not write hierarchy");
      console.log(`MCP record_baseline passed: ${baseline.structuredContent.data.files.manifestPath}`);

      const baselineComparison = await client.callTool("compare_baseline", {
        appId: selectedAppId,
        baselinePath: baseline.structuredContent.data.files.manifestPath,
        threshold: 0.01,
        pixelTolerance: 2,
        ...buildMCPScreenshotComparisonSourceInput()
      });
      assert(baselineComparison.structuredContent?.data?.passed === true, `MCP compare_baseline failed: ${JSON.stringify(baselineComparison.structuredContent?.data)}`);
      console.log(`MCP compare_baseline passed: baseline=${baselineComparison.structuredContent.data.baselineName}`);
    } finally {
      rmSync(mcpScreenshotDir, { recursive: true, force: true });
    }

    const foundNodes = await client.callTool("find_nodes", {
      appId: selectedAppId,
      className: inspectClassName,
      visibleOnly: true,
      limit: 5
    });
    assert(Number(foundNodes.structuredContent?.data?.totalCount) > 0, "MCP find_nodes found no visible inspectable nodes");
    assert(Array.isArray(foundNodes.structuredContent?.data?.nodes), "MCP find_nodes did not return nodes array");
    if (foundNodes.structuredContent.data.hasMore) {
      assert(typeof foundNodes.structuredContent.data.nextCursor === "string", "MCP find_nodes did not return nextCursor");
      const nextPage = await client.callTool("find_nodes", {
        appId: selectedAppId,
        className: inspectClassName,
        visibleOnly: true,
        limit: 5,
        cursor: foundNodes.structuredContent.data.nextCursor
      });
      assert(nextPage.structuredContent?.data?.paginationSnapshotId === foundNodes.structuredContent.data.paginationSnapshotId, "MCP find_nodes next-page snapshot mismatch");
      assertPagesDoNotOverlap(foundNodes.structuredContent.data.nodes, nextPage.structuredContent?.data?.nodes, "MCP find_nodes");
    }
    console.log(`MCP find_nodes passed: returned ${foundNodes.structuredContent.data.nodes.length} / ${foundNodes.structuredContent.data.totalCount} nodes`);

    const inspectedNode = await client.callTool("inspect_node", {
      appId: selectedAppId,
      className: inspectClassName,
      visibleOnly: true
    });
    assert(inspectedNode.structuredContent?.data?.node?.detailOid, "MCP inspect_node did not return node.detailOid");
    const inspectedClassName = inspectedNode.structuredContent?.data?.node?.className;
    assert(typeof inspectedClassName === "string" && inspectedClassName.length > 0, "MCP inspect_node did not return node.className");
    assert(Array.isArray(inspectedNode.structuredContent?.data?.detail?.attributeGroups), "MCP inspect_node did not return detail.attributeGroups");
    console.log(`MCP inspect_node passed: class=${inspectedClassName}, detailOid=${inspectedNode.structuredContent.data.node.detailOid}`);

    const checkedNode = await client.callTool("check_node", buildCheckNodeToolArgs(selectedAppId, inspectedClassName));
    assert(checkedNode.structuredContent?.data?.passed === true, `MCP check_node check failed: ${JSON.stringify(checkedNode.structuredContent?.data?.failures)}`);
    assert(Array.isArray(checkedNode.structuredContent?.data?.failures), "MCP check_node did not return failures array");
    console.log(`MCP check_node passed: class=${inspectedClassName}, checked=${checkedNode.structuredContent.data.checkedCount}`);

    if (!selectedOid) {
      selectedOid = inspectedNode.structuredContent.data.node.detailOid;
    }

    const detail = await client.callTool("node_detail", { appId: selectedAppId, oid: selectedOid });
    const groups = collectObjects(detail.structuredContent?.data, (item) => Array.isArray(item.attributes) || Array.isArray(item.sections));
    assert(groups.length > 0, `MCP node_detail did not return attribute groups, oid=${selectedOid}`);
    console.log(`MCP node_detail passed: oid=${selectedOid}, ${groups.length} attribute groups`);

    const detailSummary = await client.callTool("summarize_node_detail", { appId: selectedAppId, oid: selectedOid });
    assert(Array.isArray(detailSummary.structuredContent?.data?.attributes), "MCP summarize_node_detail did not return attributes array");
    assert(Number(detailSummary.structuredContent?.data?.attributeCount) > 0, "MCP summarize_node_detail did not return an attribute summary");
    console.log(`MCP summarize_node_detail passed: ${detailSummary.structuredContent.data.attributeCount} attributes`);

    const detailAttribute = pickCheckableDetailAttribute(detailSummary.structuredContent.data.attributes);
    const checkedDetail = await client.callTool("check_node_detail", buildCheckNodeDetailToolArgs(selectedAppId, selectedOid, detailAttribute));
    assert(checkedDetail.structuredContent?.data?.passed === true, `MCP check_node_detail check failed: ${JSON.stringify(checkedDetail.structuredContent?.data?.failures)}`);
    assert(Array.isArray(checkedDetail.structuredContent?.data?.failures), "MCP check_node_detail did not return failures array");
    console.log(`MCP check_node_detail passed: attribute=${detailAttributeName(detailAttribute)}`);

    await runMCPPatchLifecycle(
      client,
      selectedAppId,
      selectedOid,
      detailSummary.structuredContent.data.attributes
    );

    const missingSnapshot = await client.callToolAllowingError("capture_hierarchy", {
      appId: selectedAppId,
      snapshotId: "00000000-0000-4000-8000-000000000000"
    });
    assert(missingSnapshot.isError === true, "MCP expired snapshot did not return an error state");
    assert(typeof missingSnapshot.structuredContent?.errorCode === "string", "MCP expired snapshot did not return errorCode");
    assert(typeof missingSnapshot.structuredContent?.recoverySuggestion === "string", "MCP expired snapshot did not return recoverySuggestion");
    console.log(`MCP error diagnostics passed: errorCode=${missingSnapshot.structuredContent.errorCode}`);
  } finally {
    client.stop();
  }
}

function runInspector(commandArgs) {
  const result = spawnSync(inspectorBin, commandArgs, {
    encoding: "utf8"
  });

  assert(result.error == null, `Unable to start CLI: ${result.error?.message}`);
  assert(result.status === 0, `CLI execution failed: ${commandArgs.join(" ")}\n${result.stderr}${result.stdout}`);

  try {
    const parsed = JSON.parse(result.stdout);
    assert(parsed.success !== false, `CLI returned a failure: ${parsed.error ?? result.stdout}`);
    return parsed;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Unable to parse CLI JSON: ${message}\n${result.stdout}`);
  }
}

function buildCheckNodeArgs(appId, className) {
  return [
    "check-node",
    appId,
    "--class",
    className,
    "--visible-only",
    "--expect-class",
    className,
    "--expect-visible",
    "true",
    "--json"
  ];
}

function runCLIPatchLifecycle(appId, oid, detailAttributes) {
  const initialList = runInspector(["list-attribute-patches", appId, "--json"]);
  assert(initialList.data?.patchCount === 0, "CLI patch lifecycle requires a clean Runtime patch state");
  const catalog = runInspector(["list-patchable-attributes", appId, "--json"]);
  const candidate = findReversibleStringPatch(
    detailAttributes,
    catalog.data?.attributes ?? []
  );
  const applied = runInspector([
    "apply-attribute-patch",
    appId,
    oid,
    "--attribute",
    candidate.attributeIdentifier,
    "--value",
    candidate.value,
    "--json"
  ]);
  const patchId = applied.data?.patch?.patchId;
  let reverted;
  try {
    assert(
      typeof patchId === "string" && patchId.length > 0,
      "CLI apply-attribute-patch did not return patchId"
    );
    const activeList = runInspector(["list-attribute-patches", appId, "--json"]);
    assert(
      activeList.data?.patches?.some((item) => item.patchId === patchId),
      "CLI list-attribute-patches did not return the applied patch"
    );
  } finally {
    reverted = typeof patchId === "string" && patchId.length > 0
      ? runInspector(["revert-attribute-patch", appId, patchId, "--json"])
      : runInspector(["clear-attribute-patches", appId, "--json"]);
  }
  assert(
    reverted.data?.remainingPatchCount === 0,
    "CLI patch lifecycle did not restore a clean state"
  );
  console.log(`CLI attribute patch lifecycle passed: attribute=${candidate.attributeIdentifier}`);
}

async function runMCPPatchLifecycle(client, appId, oid, detailAttributes) {
  const initialList = await client.callTool("list_attribute_patches", { appId });
  assert(
    initialList.structuredContent?.data?.patchCount === 0,
    "MCP patch lifecycle requires a clean Runtime patch state"
  );
  const catalog = await client.callTool("list_patchable_attributes", { appId });
  const candidate = findReversibleStringPatch(
    detailAttributes,
    catalog.structuredContent?.data?.attributes ?? []
  );
  const applied = await client.callTool("apply_attribute_patch", {
    appId,
    oid,
    attribute: candidate.attributeIdentifier,
    value: candidate.value
  });
  const patchId = applied.structuredContent?.data?.patch?.patchId;
  let reverted;
  try {
    assert(
      typeof patchId === "string" && patchId.length > 0,
      "MCP apply_attribute_patch did not return patchId"
    );
    const activeList = await client.callTool("list_attribute_patches", { appId });
    assert(
      activeList.structuredContent?.data?.patches?.some((item) => item.patchId === patchId),
      "MCP list_attribute_patches did not return the applied patch"
    );
  } finally {
    reverted = typeof patchId === "string" && patchId.length > 0
      ? await client.callTool("revert_attribute_patch", { appId, patchId })
      : await client.callTool("clear_attribute_patches", { appId });
  }
  assert(
    reverted.structuredContent?.data?.remainingPatchCount === 0,
    "MCP patch lifecycle did not restore a clean state"
  );
  console.log(`MCP attribute patch lifecycle passed: attribute=${candidate.attributeIdentifier}`);
}

function buildScreenshotSourceArgs() {
  const args = [];
  if (selectedScreenshotSource) {
    args.push("--source", selectedScreenshotSource);
  }
  if (selectedScreenshotTargetIdentifier) {
    args.push("--target-id", selectedScreenshotTargetIdentifier);
  }
  return args;
}

function buildScreenshotComparisonSourceArgs() {
  return buildScreenshotSourceArgs();
}

function buildMCPScreenshotSourceInput() {
  const input = {};
  if (selectedScreenshotSource) {
    input.source = selectedScreenshotSource;
  }
  if (selectedScreenshotTargetIdentifier) {
    input.targetIdentifier = selectedScreenshotTargetIdentifier;
  }
  return input;
}

function buildMCPScreenshotComparisonSourceInput() {
  return buildMCPScreenshotSourceInput();
}

function buildCheckNodeToolArgs(appId, className) {
  return {
    appId,
    className,
    visibleOnly: true,
    expectedClassName: className,
    expectedVisible: true
  };
}

function pickCheckableDetailAttribute(attributes) {
  const colorAttribute = attributes.find((item) => (
    typeof item.path === "string" &&
    item.path.length > 0 &&
    typeof item.colorHex === "string" &&
    item.colorHex.length > 0
  ));
  if (colorAttribute) {
    return colorAttribute;
  }

  const attribute = attributes.find((item) => (
    typeof item.path === "string" &&
    item.path.length > 0 &&
    typeof item.valuePreview === "string" &&
    item.valuePreview.length > 0
  ));
  assert(attribute, "No attribute found for check-node-detail");
  return attribute;
}

function buildCheckNodeDetailArgs(appId, oid, attribute) {
  return [
    "check-node-detail",
    appId,
    String(oid),
    "--attribute",
    detailAttributeName(attribute),
    "--expect-value",
    attribute.colorHex ?? attribute.valuePreview,
    "--json"
  ];
}

function buildCheckNodeDetailToolArgs(appId, oid, attribute) {
  return {
    appId,
    oid,
    attribute: detailAttributeName(attribute),
    expectedValue: attribute.colorHex ?? attribute.valuePreview
  };
}

function detailAttributeName(attribute) {
  return attribute.semanticName ?? attribute.path;
}

class MCPTestClient {
  constructor(entry, env) {
    this.entry = entry;
    this.env = env;
    this.nextId = 1;
    this.pending = new Map();
    this.buffer = "";
    this.process = undefined;
  }

  async start() {
    this.process = spawn(process.execPath, [this.entry], {
      env: this.env,
      stdio: ["pipe", "pipe", "pipe"]
    });

    this.process.stdout.setEncoding("utf8");
    this.process.stderr.setEncoding("utf8");
    this.process.stdout.on("data", (chunk) => this.receive(chunk));
    this.process.stderr.on("data", () => {});
    this.process.on("exit", (code) => {
      for (const pending of this.pending.values()) {
        pending.reject(new Error(`MCP process exited: ${code}`));
      }
      this.pending.clear();
    });
  }

  request(method, params) {
    const id = this.nextId++;
    this.send({
      jsonrpc: "2.0",
      id,
      method,
      params
    });

    return new Promise((resolvePromise, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`MCP request timed out: ${method}`));
      }, 10000);
      this.pending.set(id, {
        resolve: (value) => {
          clearTimeout(timer);
          resolvePromise(value);
        },
        reject: (error) => {
          clearTimeout(timer);
          reject(error);
        }
      });
    });
  }

  notify(method, params) {
    this.send({
      jsonrpc: "2.0",
      method,
      params
    });
  }

  async callTool(name, toolArgs) {
    const result = await this.callToolAllowingError(name, toolArgs);
    assert(result.isError !== true, `MCP tool returned a failure: ${name}\n${JSON.stringify(result, null, 2)}`);
    return result;
  }

  async callToolAllowingError(name, toolArgs) {
    return await this.request("tools/call", {
      name,
      arguments: toolArgs
    });
  }

  send(message) {
    assert(this.process?.stdin?.writable, "MCP process has not started");
    this.process.stdin.write(`${JSON.stringify(message)}\n`);
  }

  receive(chunk) {
    this.buffer += chunk;
    for (;;) {
      const newlineIndex = this.buffer.indexOf("\n");
      if (newlineIndex < 0) {
        break;
      }
      const line = this.buffer.slice(0, newlineIndex).trim();
      this.buffer = this.buffer.slice(newlineIndex + 1);
      if (!line) {
        continue;
      }
      this.handleLine(line);
    }
  }

  handleLine(line) {
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      return;
    }

    if (!message.id || !this.pending.has(message.id)) {
      return;
    }

    const pending = this.pending.get(message.id);
    this.pending.delete(message.id);
    if (message.error) {
      pending.reject(new Error(`MCP returned an error: ${JSON.stringify(message.error)}`));
    } else {
      pending.resolve(message.result);
    }
  }

  stop() {
    this.process?.kill();
  }
}

function assertFileExists(path, message) {
  assert(existsSync(path), message);
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

main().catch((error) => {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`Failed: ${message}`);
  process.exit(1);
});
