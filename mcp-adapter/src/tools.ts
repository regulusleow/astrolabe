import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import type { InspectorResult } from "./inspector-cli.js";
import { inspectorToolOutputSchema } from "./inspector-envelope.js";
import { runInspector } from "./inspector-cli.js";
import { toolResponse } from "./tool-response.js";

export type InspectorRunner = (inspectorBin: string, args: string[]) => Promise<InspectorResult>;

const semanticRoleValues = [
  "avatar",
  "button",
  "control",
  "image",
  "input",
  "list",
  "navigation",
  "scroll",
  "stack",
  "tabBar",
  "text",
  "timer",
  "web",
  "window"
] as const;

type NodeSemanticRole = typeof semanticRoleValues[number];

const snapshotIdSchema = z.string().uuid().optional().describe(
  "snapshotId returned by a hierarchy tool; when provided, use that page snapshot without recapturing the current hierarchy"
);
const screenshotSourceSchema = z.enum(["auto", "virtual", "physical"]).optional().describe(
  "Platform-neutral screenshot source; auto selects by app connection kind, virtual means a virtual device, and physical means a physical device"
);
const screenshotTargetIdentifierSchema = z.string().min(1).optional().describe(
  "Platform screenshot target identifier used to disambiguate multiple available targets"
);

type NodeQueryInput = {
  /** Exact node OID to match. */
  oid?: string;

  /** className substring to match. */
  className?: string;

  /** Text substring to match. */
  text?: string;

  /** Stable semantic role to match. */
  semanticRole?: NodeSemanticRole;

  /** Whether to match visible nodes only. */
  visibleOnly?: boolean;

  /** Maximum number of nodes to return. */
  limit?: number;

};

type FrameInput = {
  /** Expected x coordinate. */
  x: number;

  /** Expected y coordinate. */
  y: number;

  /** Expected width. */
  width: number;

  /** Expected height. */
  height: number;
};

type IgnoreRegionInput = {
  /** Top-left x coordinate of the ignore region, in pixels. */
  x: number;

  /** Top-left y coordinate of the ignore region, in pixels. */
  y: number;

  /** Width of the ignore region, in pixels. */
  width: number;

  /** Height of the ignore region, in pixels. */
  height: number;
};

type ScreenshotComparisonOptionsInput = {
  /** Output path for the actual screenshot PNG. */
  actualOutputPath?: string;

  /** Output path for the diff PNG. */
  diffOutputPath?: string;

  /** Maximum allowed mismatched-pixel ratio. */
  threshold?: number;

  /** Per-channel pixel tolerance. */
  pixelTolerance?: number;

  /** Maximum number of difference regions to return. */
  regionLimit?: number;

  /** Pixel regions to ignore during comparison. */
  ignoreRegions?: IgnoreRegionInput[];

  /** Node OIDs whose UI frames are ignored. */
  ignoreNodeOids?: string[];

  /** Named screenshot regions to ignore. */
  ignoreMasks?: string[];

  /** Screenshot regions ignored using frames matched by node queries. */
  ignoreNodeQueries?: NodeQueryInput[];

  /** Whether to return UI nodes that overlap difference regions. */
  includeNodes?: boolean;

  /** Maximum number of affected nodes to return. */
  nodeLimit?: number;

  /** Screenshot source. auto prefers the high-fidelity system capture available for the current connection type. */
  source?: "auto" | "virtual" | "physical";

  /** Platform screenshot target identifier used to disambiguate multiple available targets. */
  targetIdentifier?: string;

  /** Whether low-resolution screenshots may be used for pixel comparison. */
  allowLowResolution?: boolean;
};

const ignoreNodeQuerySchema = z.object({
  oid: z.string().min(1).optional().describe("Opaque node ID to match exactly"),
  className: z.string().min(1).optional().describe("className substring to match"),
  text: z.string().min(1).optional().describe("Text substring to match"),
  semanticRole: z.enum(semanticRoleValues).optional().describe("Stable semantic role to match"),
  visibleOnly: z.boolean().optional().describe("Whether to match only visible nodes"),
  limit: z.number().int().positive().optional().describe("Maximum nodes ignored by this query; defaults to 50")
}).refine((query) => query.oid !== undefined || !!query.className || !!query.text || !!query.semanticRole, {
  message: "Each ignoreNodeQueries item requires at least one selector: oid, className, text, or semanticRole"
});

type ScreenshotSourceInput = {
  /** Screenshot source. auto prefers the high-fidelity system capture available for the current connection type. */
  source?: "auto" | "virtual" | "physical";

  /** Platform screenshot target identifier used to disambiguate multiple available targets. */
  targetIdentifier?: string;
};

type NodeExpectationInput = {
  /** Expected exact className of the node. */
  expectedClassName?: string;

  /** Expected exact text of the node. */
  expectedText?: string;

  /** Expected node visibility. */
  expectedVisible?: boolean;

  /** Expected frame. */
  expectedFrame?: FrameInput;

  /** Tolerance allowed for numeric comparison. */
  tolerance?: number;
};

type StyleExpectationInput = {
  /** Style attribute semantic name, semantic path, path, identifier, or title to match. */
  attribute: string;

  /** Expected style attribute value. */
  expectedValue: string;
};

type CheckStyleInput = NodeQueryInput & {
  /** Style attribute expectations to check in a batch. */
  expectations: StyleExpectationInput[];

  /** Whether the actual value may contain the expected value. */
  contains?: boolean;

  /** Tolerance allowed for numeric comparison. */
  tolerance?: number;
};

type LayoutNodeQueryInput = {
  /** Exact node OID to match. */
  oid?: string;

  /** className substring to match. */
  className?: string;

  /** Text substring to match. */
  text?: string;

  /** Whether to match visible nodes only. */
  visibleOnly?: boolean;
};

type CheckLayoutInput = {
  /** Query used to locate the first node. */
  from: LayoutNodeQueryInput;

  /** Query used to locate the second node. */
  to: LayoutNodeQueryInput;

  /** Layout relation to check. */
  relation: "vertical-spacing" | "horizontal-spacing" | "same-left" | "same-right" | "same-top" | "same-bottom" | "same-center-x" | "same-center-y" | "same-width" | "same-height";

  /** Expected relation value. */
  expectedValue: number;

  /** Tolerance allowed for numeric comparison. */
  tolerance?: number;
};

export function registerInspectorTools(
  server: McpServer,
  inspectorBin: string,
  inspectorRunner: InspectorRunner = runInspector
): void {
  server.registerTool(
    "list_apps",
    {
      title: "List Inspectable Apps",
      description: "Discover apps reachable through the current Runtime UI Providers and return platform, capabilities, Runtime version, compatibility status, missing capabilities, and upgrade guidance. Check compatibility.status before using other tools.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {}
    },
    async () => {
      return toolResponse(await inspectorRunner(inspectorBin, ["list-apps", "--json"]));
    }
  );

  server.registerTool(
    "capture_hierarchy",
    {
      title: "Capture UI Hierarchy",
      description: "Return the UI hierarchy tree, frames, classes, colors, and basic node data. Without snapshotId, capture the current page and create a snapshot; with snapshotId, read only that snapshot. Returns at most 25 nodes by default.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        snapshotId: snapshotIdSchema,
        nodeLimit: z.number().int().min(1).max(200).optional().describe("Maximum number of returned nodes; defaults to 25 and cannot exceed 200"),
        maxDepth: z.number().int().min(0).optional().describe("Maximum returned hierarchy depth; the root depth is 0")
      }
    },
    async ({ appId, snapshotId, nodeLimit, maxDepth }) => {
      const args = ["capture-hierarchy", appId, "--node-limit", String(nodeLimit ?? 25)];
      appendSnapshotId(args, snapshotId);
      if (maxDepth !== undefined) {
        args.push("--max-depth", String(maxDepth));
      }
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "capture_screenshot",
    {
      title: "Export Current Screenshot",
      description: "Select a screenshot source using the platform-neutral source option and write a local PNG. Returns the actual source, pixel size, logical size, and scale. auto selects an available high-fidelity system screenshot based on the app connection kind.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        outputPath: z.string().min(1).describe("PNG output path"),
        source: screenshotSourceSchema,
        targetIdentifier: screenshotTargetIdentifierSchema
      }
    },
    async ({ appId, outputPath, source, targetIdentifier }) => {
      const args = ["capture-screenshot", appId, "--output", outputPath];
      appendScreenshotSourceOptions(args, { source, targetIdentifier });
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "list_patchable_attributes",
    {
      title: "List Patchable UI Attributes",
      description: "Fetch the patchable attribute catalog from the target app Runtime, including attribute patterns, value types, applicable node types, numeric bounds, and input formats. Use this tool before apply_attribute_patch.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps that declares the attributePatchDiscovery capability")
      }
    },
    async ({ appId }) => {
      return toolResponse(await inspectorRunner(inspectorBin, [
        "list-patchable-attributes",
        appId,
        "--json"
      ]));
    }
  );

  server.registerTool(
    "apply_attribute_patch",
    {
      title: "Temporarily Patch a Runtime UI Attribute",
      description: "Temporarily modify one allowlisted presentation attribute in the Debug Runtime session to validate a UI hypothesis. This does not change source code, binaries, or persistent state. Before calling, query the Runtime allowlist with list_patchable_attributes and confirm oid and semanticPath with summarize_node_detail.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps that declares the attributePatching capability"),
        oid: z.string().min(1).describe("Opaque node ID from the latest hierarchy (oid or detailOid)"),
        attribute: z.string().min(1).describe("Complete namespaced attribute path returned by node details and present in the current Runtime allowlist; replace placeholders in parameterized catalog paths"),
        value: z.string().describe("Temporary value; use decimal for numbers, #RRGGBB or #RRGGBBAA for colors, and width,height for shadowOffset")
      }
    },
    async ({ appId, oid, attribute, value }) => {
      return toolResponse(await inspectorRunner(inspectorBin, [
        "apply-attribute-patch",
        appId,
        oid,
        "--attribute",
        attribute,
        "--value",
        value,
        "--json"
      ]));
    }
  );

  server.registerTool(
    "list_attribute_patches",
    {
      title: "List Temporary UI Attribute Patches",
      description: "List temporary attribute patches still active in the target app's current Runtime Server session.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps")
      }
    },
    async ({ appId }) => {
      return toolResponse(await inspectorRunner(inspectorBin, [
        "list-attribute-patches",
        appId,
        "--json"
      ]));
    }
  );

  server.registerTool(
    "revert_attribute_patch",
    {
      title: "Revert a Temporary UI Attribute Patch",
      description: "Restore the initial value recorded by a temporary patch without restarting the app.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        patchId: z.string().min(1).describe("Opaque patchId returned by apply_attribute_patch")
      }
    },
    async ({ appId, patchId }) => {
      return toolResponse(await inspectorRunner(inspectorBin, [
        "revert-attribute-patch",
        appId,
        patchId,
        "--json"
      ]));
    }
  );

  server.registerTool(
    "clear_attribute_patches",
    {
      title: "Clear Temporary UI Attribute Patches",
      description: "Restore all temporary attribute patches in the target app's current Runtime Server session.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps")
      }
    },
    async ({ appId }) => {
      return toolResponse(await inspectorRunner(inspectorBin, [
        "clear-attribute-patches",
        appId,
        "--json"
      ]));
    }
  );

  server.registerTool(
    "compare_screenshot",
    {
      title: "Compare Current Screenshot",
      description: "Capture the current screen using source and compare it pixel by pixel with an expected PNG, optionally writing actual and diff PNG files.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        expectedPath: z.string().min(1).describe("Expected PNG path"),
        actualOutputPath: z.string().min(1).optional().describe("Actual screenshot PNG output path"),
        diffOutputPath: z.string().min(1).optional().describe("Diff PNG output path; mismatched pixels are marked red"),
        threshold: z.number().min(0).max(1).optional().describe("Maximum allowed mismatched-pixel ratio; defaults to 0"),
        pixelTolerance: z.number().int().min(0).max(255).optional().describe("Per-channel pixel tolerance; defaults to 0"),
        regionLimit: z.number().int().min(0).optional().describe("Maximum number of returned diff regions; defaults to 10"),
        ignoreRegions: z.array(z.object({
          x: z.number().int().min(0).describe("Ignored region left coordinate in pixels"),
          y: z.number().int().min(0).describe("Ignored region top coordinate in pixels"),
          width: z.number().int().positive().describe("Ignored region width in pixels"),
          height: z.number().int().positive().describe("Ignored region height in pixels")
        })).optional().describe("Pixel regions ignored during comparison, useful for dynamic content, timestamps, and system status bars"),
        ignoreNodeOids: z.array(z.string().min(1)).optional().describe("Opaque node IDs ignored by UI-node frame, useful for dynamic avatars, times, and display names"),
        ignoreMasks: z.array(z.string().min(1)).optional().describe("Ignore screenshot regions by preset names supported by the current platform Provider"),
        ignoreNodeQueries: z.array(ignoreNodeQuerySchema).optional().describe("Match frames by node query and ignore their screenshot regions, useful for dynamic text, avatars, and countdowns"),
        includeNodes: z.boolean().optional().describe("Whether to return UI nodes overlapping diff regions"),
        nodeLimit: z.number().int().min(0).optional().describe("Maximum number of returned affected nodes; defaults to 5"),
        source: screenshotSourceSchema,
        targetIdentifier: screenshotTargetIdentifierSchema,
        allowLowResolution: z.boolean().optional().describe("Whether to allow low-resolution screenshots in pixel comparison")
      }
    },
    async ({ appId, expectedPath, actualOutputPath, diffOutputPath, threshold, pixelTolerance, regionLimit, ignoreRegions, ignoreNodeOids, ignoreMasks, ignoreNodeQueries, includeNodes, nodeLimit, source, targetIdentifier, allowLowResolution }) => {
      const args = ["compare-screenshot", appId, "--expected", expectedPath];
      appendScreenshotComparisonOptions(args, { actualOutputPath, diffOutputPath, threshold, pixelTolerance, regionLimit, ignoreRegions, ignoreNodeOids, ignoreMasks, ignoreNodeQueries, includeNodes, nodeLimit, source, targetIdentifier, allowLowResolution });
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "inspect_diff",
    {
      title: "Inspect Current Screenshot Differences",
      description: "Capture the current screen using source, compare it pixel by pixel with an expected PNG or baseline manifest, and return diff regions, suspected UI nodes, and recommended follow-up checks.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        expectedPath: z.string().min(1).optional().describe("Expected PNG path; optional when baselinePath is provided"),
        baselinePath: z.string().min(1).optional().describe("Baseline manifest JSON path returned by record_baseline"),
        actualOutputPath: z.string().min(1).optional().describe("Actual screenshot PNG output path"),
        diffOutputPath: z.string().min(1).optional().describe("Diff PNG output path; mismatched pixels are marked red"),
        threshold: z.number().min(0).max(1).optional().describe("Maximum allowed mismatched-pixel ratio; defaults to 0"),
        pixelTolerance: z.number().int().min(0).max(255).optional().describe("Per-channel pixel tolerance; defaults to 0"),
        regionLimit: z.number().int().min(0).optional().describe("Maximum number of returned diff regions; defaults to 10"),
        ignoreRegions: z.array(z.object({
          x: z.number().int().min(0).describe("Ignored region left coordinate in pixels"),
          y: z.number().int().min(0).describe("Ignored region top coordinate in pixels"),
          width: z.number().int().positive().describe("Ignored region width in pixels"),
          height: z.number().int().positive().describe("Ignored region height in pixels")
        })).optional().describe("Pixel regions ignored during comparison, useful for dynamic content, timestamps, and system status bars"),
        ignoreNodeOids: z.array(z.string().min(1)).optional().describe("Opaque node IDs ignored by UI-node frame, useful for dynamic avatars, times, and display names"),
        ignoreMasks: z.array(z.string().min(1)).optional().describe("Ignore screenshot regions by preset names supported by the current platform Provider"),
        ignoreNodeQueries: z.array(ignoreNodeQuerySchema).optional().describe("Match frames by node query and ignore their screenshot regions, useful for dynamic text, avatars, and countdowns"),
        nodeLimit: z.number().int().min(0).optional().describe("Maximum number of returned affected nodes; defaults to 5"),
        source: screenshotSourceSchema,
        targetIdentifier: screenshotTargetIdentifierSchema,
        allowLowResolution: z.boolean().optional().describe("Whether to allow low-resolution screenshots in pixel comparison")
      }
    },
    async ({ appId, expectedPath, baselinePath, actualOutputPath, diffOutputPath, threshold, pixelTolerance, regionLimit, ignoreRegions, ignoreNodeOids, ignoreMasks, ignoreNodeQueries, nodeLimit, source, targetIdentifier, allowLowResolution }) => {
      if (!expectedPath && !baselinePath) {
        throw new Error("inspect_diff requires expectedPath or baselinePath");
      }
      const args = ["inspect-diff", appId];
      if (baselinePath) {
        args.push("--baseline", baselinePath);
      }
      if (expectedPath) {
        args.push("--expected", expectedPath);
      }
      appendScreenshotComparisonOptions(args, { actualOutputPath, diffOutputPath, threshold, pixelTolerance, regionLimit, ignoreRegions, ignoreNodeOids, ignoreMasks, ignoreNodeQueries, includeNodes: true, nodeLimit, source, targetIdentifier, allowLowResolution });
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "record_baseline",
    {
      title: "Record UI Baseline",
      description: "Capture the current screenshot and UI hierarchy and write a local baseline manifest for later use by compare_baseline.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        outputDirectory: z.string().min(1).describe("Baseline output directory"),
        name: z.string().min(1).optional().describe("Baseline name; defaults to baseline"),
        ignoreRegions: z.array(z.object({
          x: z.number().int().min(0).describe("Ignored region left coordinate in pixels"),
          y: z.number().int().min(0).describe("Ignored region top coordinate in pixels"),
          width: z.number().int().positive().describe("Ignored region width in pixels"),
          height: z.number().int().positive().describe("Ignored region height in pixels")
        })).optional().describe("Reusable screenshot ignore regions recorded in the baseline manifest"),
        ignoreNodeOids: z.array(z.string().min(1)).optional().describe("Opaque node IDs recorded in the baseline manifest by UI-node frame"),
        ignoreMasks: z.array(z.string().min(1)).optional().describe("Record screenshot ignore regions by preset names supported by the current platform Provider"),
        ignoreNodeQueries: z.array(ignoreNodeQuerySchema).optional().describe("Match frames by node query and record screenshot ignore regions in the baseline manifest"),
        source: screenshotSourceSchema,
        targetIdentifier: screenshotTargetIdentifierSchema
      }
    },
    async ({ appId, outputDirectory, name, ignoreRegions, ignoreNodeOids, ignoreMasks, ignoreNodeQueries, source, targetIdentifier }) => {
      const args = ["record-baseline", appId, "--output-dir", outputDirectory];
      if (name) {
        args.push("--name", name);
      }
      appendIgnoreRegions(args, ignoreRegions);
      appendIgnoreNodeOids(args, ignoreNodeOids);
      appendIgnoreMasks(args, ignoreMasks);
      appendIgnoreNodeQueries(args, ignoreNodeQueries);
      appendScreenshotSourceOptions(args, { source, targetIdentifier });
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "compare_baseline",
    {
      title: "Compare UI Baseline",
      description: "Read the manifest generated by record_baseline and compare the current screenshot pixel by pixel with the baseline PNG.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        baselinePath: z.string().min(1).describe("manifestPath returned by record_baseline"),
        actualOutputPath: z.string().min(1).optional().describe("Actual screenshot PNG output path"),
        diffOutputPath: z.string().min(1).optional().describe("Diff PNG output path; mismatched pixels are marked red"),
        threshold: z.number().min(0).max(1).optional().describe("Maximum allowed mismatched-pixel ratio; defaults to 0"),
        pixelTolerance: z.number().int().min(0).max(255).optional().describe("Per-channel pixel tolerance; defaults to 0"),
        regionLimit: z.number().int().min(0).optional().describe("Maximum number of returned diff regions; defaults to 10"),
        ignoreRegions: z.array(z.object({
          x: z.number().int().min(0).describe("Ignored region left coordinate in pixels"),
          y: z.number().int().min(0).describe("Ignored region top coordinate in pixels"),
          width: z.number().int().positive().describe("Ignored region width in pixels"),
          height: z.number().int().positive().describe("Ignored region height in pixels")
        })).optional().describe("Pixel regions ignored during comparison, useful for dynamic content, timestamps, and system status bars"),
        ignoreNodeOids: z.array(z.string().min(1)).optional().describe("Opaque node IDs ignored by UI-node frame, useful for dynamic avatars, times, and display names"),
        ignoreMasks: z.array(z.string().min(1)).optional().describe("Ignore screenshot regions by preset names supported by the current platform Provider"),
        ignoreNodeQueries: z.array(ignoreNodeQuerySchema).optional().describe("Match frames by node query and ignore their screenshot regions, useful for dynamic text, avatars, and countdowns"),
        includeNodes: z.boolean().optional().describe("Whether to return UI nodes overlapping diff regions"),
        nodeLimit: z.number().int().min(0).optional().describe("Maximum number of returned affected nodes; defaults to 5"),
        source: screenshotSourceSchema,
        targetIdentifier: screenshotTargetIdentifierSchema,
        allowLowResolution: z.boolean().optional().describe("Whether to allow low-resolution screenshots in pixel comparison")
      }
    },
    async ({ appId, baselinePath, actualOutputPath, diffOutputPath, threshold, pixelTolerance, regionLimit, ignoreRegions, ignoreNodeOids, ignoreMasks, ignoreNodeQueries, includeNodes, nodeLimit, source, targetIdentifier, allowLowResolution }) => {
      const args = ["compare-baseline", appId, "--baseline", baselinePath];
      appendScreenshotComparisonOptions(args, { actualOutputPath, diffOutputPath, threshold, pixelTolerance, regionLimit, ignoreRegions, ignoreNodeOids, ignoreMasks, ignoreNodeQueries, includeNodes, nodeLimit, source, targetIdentifier, allowLowResolution });
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "node_detail",
    {
      title: "Read Node Details",
      description: "Read details for a UI node. With snapshotId, first verify that the node belongs to the snapshot and prefer cached snapshot details, requesting the Runtime by the original detailOid only when details are absent.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        snapshotId: snapshotIdSchema,
        oid: z.string().min(1).describe("Opaque node ID returned by capture_hierarchy (oid or detailOid)")
      }
    },
    async ({ appId, snapshotId, oid }) => {
      const args = ["node-detail", appId, oid];
      appendSnapshotId(args, snapshotId);
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "summarize_node_detail",
    {
      title: "Summarize Node Attribute Details",
      description: "Read runtime attribute details for a UI node and flatten them into a list that is easier for AI to search and compare.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        snapshotId: snapshotIdSchema,
        oid: z.string().min(1).describe("Opaque node ID returned by capture_hierarchy (oid or detailOid)"),
        filter: z.string().min(1).optional().describe("Filter attributes by path, title, type, or value preview")
      }
    },
    async ({ appId, snapshotId, oid, filter }) => {
      const args = ["summarize-node-detail", appId, oid];
      appendSnapshotId(args, snapshotId);
      if (filter) {
        args.push("--filter", filter);
      }
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "check_node_detail",
    {
      title: "Check Node Attribute Details",
      description: "Read the runtime attribute summary for a UI node and check whether an attribute exists or matches an expected value.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        snapshotId: snapshotIdSchema,
        oid: z.string().min(1).describe("Opaque node ID returned by capture_hierarchy (oid or detailOid)"),
        attribute: z.string().min(1).describe("Attribute semantic name, semantic path, path, identifier, or title to match"),
        expectedValue: z.string().optional().describe("Expected attribute value preview"),
        contains: z.boolean().optional().describe("Whether the actual value may contain the expected value"),
        tolerance: z.number().min(0).optional().describe("Allowed tolerance for numeric comparison")
      }
    },
    async ({ appId, snapshotId, oid, attribute, expectedValue, contains, tolerance }) => {
      const args = ["check-node-detail", appId, oid, "--attribute", attribute];
      appendSnapshotId(args, snapshotId);
      if (expectedValue !== undefined) {
        args.push("--expect-value", expectedValue);
      }
      if (contains) {
        args.push("--contains");
      }
      if (tolerance !== undefined) {
        args.push("--tolerance", String(tolerance));
      }
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "check_style",
    {
      title: "Check Node Style Bundle",
      description: "Find the first UI node matching the query and check its style. With snapshotId, locate the node only in that hierarchy snapshot and prefer cached details.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        snapshotId: snapshotIdSchema,
        oid: z.string().min(1).optional().describe("Opaque node ID to match exactly"),
        className: z.string().min(1).optional().describe("className substring to match, such as UILabel"),
        text: z.string().min(1).optional().describe("Text substring to match"),
        visibleOnly: z.boolean().optional().describe("Whether to match only visible nodes"),
        expectations: z.array(z.object({
          attribute: z.string().min(1).describe("Style attribute semantic name, semantic path, path, identifier, or title"),
          expectedValue: z.string().describe("Expected style attribute value")
        })).min(1).describe("Style attribute expectations to check as a batch"),
        contains: z.boolean().optional().describe("Whether the actual value may contain the expected value"),
        tolerance: z.number().min(0).optional().describe("Allowed tolerance for numeric comparison")
      }
    },
    async ({ appId, snapshotId, oid, className, text, visibleOnly, expectations, contains, tolerance }) => {
      const args = ["check-style", appId];
      appendSnapshotId(args, snapshotId);
      appendNodeQueryArgs(args, { oid, className, text, visibleOnly });
      appendStyleExpectationArgs(args, { expectations, contains, tolerance });
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "summarize_hierarchy",
    {
      title: "Summarize UI Hierarchy",
      description: "Return a bounded set of on-screen nodes, text nodes, and basic statistics. Without snapshotId, capture the current page; with snapshotId, read only that snapshot.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        snapshotId: snapshotIdSchema
      }
    },
    async ({ appId, snapshotId }) => {
      const args = ["summarize-hierarchy", appId];
      appendSnapshotId(args, snapshotId);
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "inspect_screen",
    {
      title: "Inspect Current Screen",
      description: "Return screen statistics, inspection targets in logical coordinates, snapshotId, and hierarchySource. Without snapshotId, capture the current page and create a snapshot; with snapshotId, analyze only that snapshot.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        snapshotId: snapshotIdSchema,
        targetLimit: z.number().int().min(1).max(100).optional().describe("Maximum number of recommended follow-up nodes; defaults to 12"),
        classLimit: z.number().int().min(1).max(100).optional().describe("Maximum number of classes in statistics; defaults to 12")
      }
    },
    async ({ appId, snapshotId, targetLimit, classLimit }) => {
      const args = ["inspect-screen", appId];
      appendSnapshotId(args, snapshotId);
      if (targetLimit) {
        args.push("--target-limit", String(targetLimit));
      }
      if (classLimit) {
        args.push("--class-limit", String(classLimit));
      }
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "find_nodes",
    {
      title: "Find UI Nodes",
      description: "Find UI nodes by query. Without snapshotId, capture the current page; with snapshotId, query only that snapshot. Pagination cursors remain bound to the page snapshot used by the first query.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        snapshotId: snapshotIdSchema,
        oid: z.string().min(1).optional().describe("Opaque node ID to match exactly"),
        className: z.string().min(1).optional().describe("className substring to match, such as UILabel"),
        text: z.string().min(1).optional().describe("Text substring to match"),
        semanticRole: z.enum(semanticRoleValues).optional().describe("Stable semantic role to match"),
        visibleOnly: z.boolean().optional().describe("Whether to return only on-screen visible nodes"),
        limit: z.number().int().min(1).max(100).optional().describe("Maximum nodes per page; defaults to 50 and cannot exceed 100"),
        cursor: z.string().min(1).max(4096).optional().describe("Complete nextCursor returned by the previous page; subsequent pages read the same frozen snapshot, and appId and query filters must remain unchanged")
      }
    },
    async ({ appId, snapshotId, oid, className, text, semanticRole, visibleOnly, limit, cursor }) => {
      const args = ["find-nodes", appId];
      appendSnapshotId(args, snapshotId);
      appendNodeQueryArgs(args, { oid, className, text, semanticRole, visibleOnly, limit });
      if (cursor) {
        args.push("--cursor", cursor);
      }
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "inspect_node",
    {
      title: "Inspect Matching Node Details",
      description: "Find the first matching UI node and read its details. With snapshotId, locate the node only in that snapshot and read details on demand from cache or the same Runtime object.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        snapshotId: snapshotIdSchema,
        oid: z.string().min(1).optional().describe("Opaque node ID to match exactly"),
        className: z.string().min(1).optional().describe("className substring to match, such as UILabel"),
        text: z.string().min(1).optional().describe("Text substring to match"),
        visibleOnly: z.boolean().optional().describe("Whether to match only visible nodes")
      }
    },
    async ({ appId, snapshotId, oid, className, text, visibleOnly }) => {
      const args = ["inspect-node", appId];
      appendSnapshotId(args, snapshotId);
      appendNodeQueryArgs(args, { oid, className, text, visibleOnly });
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "check_node",
    {
      title: "Check Node Expectations",
      description: "Find the first matching UI node and check its text, type, visibility, and frame. With snapshotId, inspect only the specified page snapshot.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        snapshotId: snapshotIdSchema,
        oid: z.string().min(1).optional().describe("Opaque node ID to match exactly"),
        className: z.string().min(1).optional().describe("className substring to match, such as UILabel"),
        text: z.string().min(1).optional().describe("Text substring to match"),
        visibleOnly: z.boolean().optional().describe("Whether to match only visible nodes"),
        expectedClassName: z.string().min(1).optional().describe("Expected exact node className"),
        expectedText: z.string().optional().describe("Expected exact node text"),
        expectedVisible: z.boolean().optional().describe("Expected node visibility"),
        expectedFrame: z.object({
          x: z.number().describe("Expected x coordinate"),
          y: z.number().describe("Expected y coordinate"),
          width: z.number().describe("Expected width"),
          height: z.number().describe("Expected height")
        }).optional().describe("Expected frame"),
        tolerance: z.number().min(0).optional().describe("Allowed tolerance for numeric comparison")
      }
    },
    async ({
      appId,
      snapshotId,
      oid,
      className,
      text,
      visibleOnly,
      expectedClassName,
      expectedText,
      expectedVisible,
      expectedFrame,
      tolerance
    }) => {
      const args = ["check-node", appId];
      appendSnapshotId(args, snapshotId);
      appendNodeQueryArgs(args, { oid, className, text, visibleOnly });
      appendNodeExpectationArgs(args, { expectedClassName, expectedText, expectedVisible, expectedFrame, tolerance });
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );

  server.registerTool(
    "check_layout",
    {
      title: "Check Layout Relation Between Two Nodes",
      description: "Locate two UI nodes by query and check their layout relation. With snapshotId, locate both nodes in the same page snapshot.",
      outputSchema: inspectorToolOutputSchema,
      inputSchema: {
        appId: z.string().min(1).describe("appId returned by list_apps"),
        snapshotId: snapshotIdSchema,
        from: z.object({
          oid: z.string().min(1).optional().describe("First opaque node ID"),
          className: z.string().min(1).optional().describe("First node className substring"),
          text: z.string().min(1).optional().describe("First node text substring"),
          visibleOnly: z.boolean().optional().describe("Whether to match only visible nodes")
        }).describe("First-node query"),
        to: z.object({
          oid: z.string().min(1).optional().describe("Second opaque node ID"),
          className: z.string().min(1).optional().describe("Second node className substring"),
          text: z.string().min(1).optional().describe("Second node text substring"),
          visibleOnly: z.boolean().optional().describe("Whether to match only visible nodes")
        }).describe("Second-node query"),
        relation: z.enum(["vertical-spacing", "horizontal-spacing", "same-left", "same-right", "same-top", "same-bottom", "same-center-x", "same-center-y", "same-width", "same-height"]).describe("Layout relation to check"),
        expectedValue: z.number().describe("Expected relation value, such as the desired vertical-spacing gap"),
        tolerance: z.number().min(0).optional().describe("Allowed tolerance for numeric comparison")
      }
    },
    async ({ appId, snapshotId, from, to, relation, expectedValue, tolerance }) => {
      const args = ["check-layout", appId];
      appendSnapshotId(args, snapshotId);
      appendPrefixedNodeQueryArgs(args, "from", from);
      appendPrefixedNodeQueryArgs(args, "to", to);
      args.push("--relation", relation, "--expect", String(expectedValue));
      if (tolerance !== undefined) {
        args.push("--tolerance", String(tolerance));
      }
      args.push("--json");
      return toolResponse(await inspectorRunner(inspectorBin, args));
    }
  );
}

function appendSnapshotId(args: string[], snapshotId: string | undefined): void {
  if (snapshotId) {
    args.push("--snapshot-id", snapshotId);
  }
}

function appendScreenshotComparisonOptions(args: string[], input: ScreenshotComparisonOptionsInput): void {
  appendScreenshotSourceOptions(args, input);
  if (input.actualOutputPath) {
    args.push("--actual-output", input.actualOutputPath);
  }
  if (input.diffOutputPath) {
    args.push("--diff-output", input.diffOutputPath);
  }
  if (input.threshold !== undefined) {
    args.push("--threshold", String(input.threshold));
  }
  if (input.pixelTolerance !== undefined) {
    args.push("--pixel-tolerance", String(input.pixelTolerance));
  }
  if (input.regionLimit !== undefined) {
    args.push("--region-limit", String(input.regionLimit));
  }
  appendIgnoreRegions(args, input.ignoreRegions);
  appendIgnoreNodeOids(args, input.ignoreNodeOids);
  appendIgnoreMasks(args, input.ignoreMasks);
  appendIgnoreNodeQueries(args, input.ignoreNodeQueries);
  if (input.includeNodes) {
    args.push("--include-nodes");
  }
  if (input.nodeLimit !== undefined) {
    args.push("--node-limit", String(input.nodeLimit));
  }
  if (input.allowLowResolution) {
    args.push("--allow-low-resolution");
  }
}

function appendScreenshotSourceOptions(args: string[], input: ScreenshotSourceInput): void {
  if (input.source) {
    args.push("--source", input.source);
  }
  if (input.targetIdentifier) {
    args.push("--target-id", input.targetIdentifier);
  }
}

function appendIgnoreRegions(args: string[], ignoreRegions: IgnoreRegionInput[] | undefined): void {
  if (!ignoreRegions) {
    return;
  }
  for (const region of ignoreRegions) {
    args.push(
      "--ignore-region",
      String(region.x),
      String(region.y),
      String(region.width),
      String(region.height)
    );
  }
}

function appendIgnoreNodeOids(args: string[], ignoreNodeOids: string[] | undefined): void {
  if (!ignoreNodeOids) {
    return;
  }
  for (const oid of ignoreNodeOids) {
    args.push("--ignore-node-oid", oid);
  }
}

function appendIgnoreMasks(args: string[], ignoreMasks: string[] | undefined): void {
  if (!ignoreMasks) {
    return;
  }
  for (const mask of ignoreMasks) {
    args.push("--ignore-mask", mask);
  }
}

function appendIgnoreNodeQueries(args: string[], ignoreNodeQueries: NodeQueryInput[] | undefined): void {
  if (!ignoreNodeQueries) {
    return;
  }
  for (const query of ignoreNodeQueries) {
    args.push("--ignore-node-query");
    appendPrefixedIgnoreNodeQueryArgs(args, query);
  }
}

function appendPrefixedIgnoreNodeQueryArgs(args: string[], input: NodeQueryInput): void {
  if (input.oid) {
    args.push("--query-oid", input.oid);
  }
  if (input.className) {
    args.push("--query-class", input.className);
  }
  if (input.text) {
    args.push("--query-text", input.text);
  }
  if (input.semanticRole) {
    args.push("--query-role", input.semanticRole);
  }
  if (input.visibleOnly) {
    args.push("--query-visible-only");
  }
  if (input.limit) {
    args.push("--query-limit", String(input.limit));
  }
}

function appendNodeQueryArgs(args: string[], input: NodeQueryInput): void {
  if (input.oid) {
    args.push("--oid", input.oid);
  }
  if (input.className) {
    args.push("--class", input.className);
  }
  if (input.text) {
    args.push("--text", input.text);
  }
  if (input.semanticRole) {
    args.push("--role", input.semanticRole);
  }
  if (input.visibleOnly) {
    args.push("--visible-only");
  }
  if (input.limit) {
    args.push("--limit", String(input.limit));
  }
}

function appendNodeExpectationArgs(args: string[], input: NodeExpectationInput): void {
  if (input.expectedClassName) {
    args.push("--expect-class", input.expectedClassName);
  }
  if (input.expectedText !== undefined) {
    args.push("--expect-text", input.expectedText);
  }
  if (input.expectedVisible !== undefined) {
    args.push("--expect-visible", String(input.expectedVisible));
  }
  if (input.expectedFrame) {
    args.push(
      "--expect-frame",
      String(input.expectedFrame.x),
      String(input.expectedFrame.y),
      String(input.expectedFrame.width),
      String(input.expectedFrame.height)
    );
  }
  if (input.tolerance !== undefined) {
    args.push("--tolerance", String(input.tolerance));
  }
}

function appendStyleExpectationArgs(args: string[], input: CheckStyleInput): void {
  for (const expectation of input.expectations) {
    args.push("--expect", expectation.attribute, expectation.expectedValue);
  }
  if (input.contains) {
    args.push("--contains");
  }
  if (input.tolerance !== undefined) {
    args.push("--tolerance", String(input.tolerance));
  }
}

function appendPrefixedNodeQueryArgs(args: string[], prefix: "from" | "to", input: LayoutNodeQueryInput): void {
  if (input.oid !== undefined) {
    args.push(`--${prefix}-oid`, input.oid);
  }
  if (input.className) {
    args.push(`--${prefix}-class`, input.className);
  }
  if (input.text) {
    args.push(`--${prefix}-text`, input.text);
  }
  if (input.visibleOnly) {
    args.push(`--${prefix}-visible-only`);
  }
}
