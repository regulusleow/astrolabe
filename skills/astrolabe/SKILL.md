---
name: astrolabe
description: Use when implementing, debugging, reviewing, or verifying a running mobile UI, including layout, rendered content, visibility, styles, images, text, screenshots, visual diffs, baselines, temporary presentation experiments, and UI relations such as View, Layer, mask, or ownership paths. Prefer Astrolabe runtime evidence over source-only conclusions whenever an inspectable App is available.
---

# Astrolabe UI Inspector

Use Astrolabe to observe and verify the UI that is actually running on a
supported mobile platform. Source code describes intent; Runtime nodes,
semantic attributes, relations, and system screenshots show the result. Do not
claim that a UI is correct from source inspection alone when an inspectable App
is running.

## Core Workflow

1. Discover the target with `list_apps`.
   - Read `diagnostics` before concluding that no App is available.
   - Match the user-provided App, application identifier, virtual device, or
     physical device. Ask when multiple candidates remain.
   - Check `compatibility.status`, `capabilities`,
     `missingRuntimeCapabilities`, and `recoverySuggestion` before selecting an
     operation.
   - Read `platform`; never infer a framework or transport from `appId`, device
     names, classes, or attribute namespaces.
   - Confirm that the required MCP Tool exists as well as the corresponding
     Runtime capability. Tool availability belongs to the installed Host/MCP;
     capabilities belong to the selected Runtime.
   - Use the exact latest `appId` for every subsequent call.

2. Establish Target State Readiness before formal acceptance.
   - Observe the actual current screen. Do not infer the target from source,
     route names, or intended navigation.
   - If the target is absent, use interaction only when both its MCP Tool and
     Runtime capability exist, and only through visible normal UI.
   - Otherwise request developer manual navigation, real-condition preparation,
     or explicit debug-fixture/mock authorization. Never use an App Router,
     private initializer, unapproved deep link, source shortcut, or business-state
     mutation to prepare the target.
   - After any preparation, rediscover the App and re-observe the target. Treat
     every readiness-observation snapshot as preliminary and discard it; do not
     reuse it for formal acceptance. Before readiness, do not issue a page
     `passed`, `failed`, or `inconclusive` verdict because acceptance has not
     started.
   - An authorized mock is presentation-only; end-to-end behavior remains
     unverified. Read [design-verification.md](references/design-verification.md)
     before any design verification.

3. Freeze the screen context.
   - After readiness, start with `inspect_screen` to create and retain the fresh,
     authoritative formal acceptance `snapshotId`.
   - For design acceptance, create authoritative Design Expectations and a
     complete Coverage Ledger before selecting or running checks.
   - Pass that same `appId` and `snapshotId` to hierarchy, lookup, detail, and
     structured-check tools while investigating the same state.
   - When tree structure or an implementation node is needed, call
     `capture_hierarchy` with the existing `snapshotId`; do not silently create
     a second snapshot.
   - The snapshot freezes hierarchy identity, not necessarily every node detail.
     Read `detailSource`: `snapshotCache` is cached evidence, while `liveRuntime`
     was resolved later through the frozen node's `detailOid`. A live detail and
     its hierarchy are not an atomic observation or guaranteed to have the same
     capture time. Compare `detailCapturedAtUnixTime` with `capturedAtUnixTime`
     when timing can affect the conclusion.
   - Omit `snapshotId` only when the latest state is required or the user has
     intentionally navigated. Restart the investigation from the new snapshot.
   - A screenshot is always latest-state evidence and is not pixel-synchronized
     with an older hierarchy snapshot.

4. Locate the actual rendering node.
   - Use `summarize_hierarchy` when counts and bounded lists are sufficient. Use
     `capture_hierarchy` only when the tree shape or implementation nodes matter.
   - `capture_hierarchy` returns at most 25 nodes by default. Set `nodeLimit` and
     `maxDepth` deliberately, then read `nodeCount`, `returnedNodeCount`,
     `omittedNodeCount`, and `truncated`. Do not conclude that a node is absent or
     missing from a truncated projection.
   - Use `find_nodes` to expose ambiguity before a first-match tool.
   - Search broad to narrow: visible text, semantic role, custom class, frame
     region, then hierarchy path.
   - Inspect nested label, image, Layer, or other content-bearing nodes instead
     of stopping at a control or layout container.
   - Follow `nextCursor` unchanged while `hasMore` is true. Keep the same
     selectors and frozen snapshot; restart when the pagination snapshot
     expires or changes.
   - Use the selected node's exact `oid` or `detailOid` for follow-up calls.

5. Prove rendered output, not only layout intent.
   - A layout box describes where a container participates in layout; it does
     not necessarily describe the rendered footprint of its content.
   - Before approving size, containment, clipping, alignment, or visual balance,
     inspect the relevant intrinsic content, mapping policy, clipping or masking,
     and transform or visual effect evidence.
   - For images, read `imageSize`, `imageScale`, `contentMode`, frame, bounds,
     and clipping together. A correct frame or bounds alone cannot prove that
     the image rendered at the intended size. A larger image under an
     unscaled content mode can overflow or crop.
   - Missing evidence for a dimension required by the review cannot produce
     `passed`; report the result as `inconclusive` and name the missing fact.
   - Read [rendered-content.md](references/rendered-content.md) whenever content
     can render differently from its container, including images, text, masks,
     transforms, shadows, and descendant drawing.

6. Choose hierarchy or UI Graph deliberately.
   - Use hierarchy tools for ordinary parent-child structure.
   - Use `query_ui_graph` for ownership, cross-tree, non-hierarchy relations, or
     a bounded uniform relation traversal. Require both the Tool and the
     `uiGraphRelations` capability.
   - The frozen chain is `capture_hierarchy` → `query_ui_graph` →
     `summarize_node_detail`, always with the same `appId` and `snapshotId`.
   - Request only the necessary namespaced relation types and direction. Read
     `truncated`, `truncationReasons`, `frontierOids`, and
     `omittedFrontierCount` before expanding.
   - Read [ui-graph.md](references/ui-graph.md) for relation semantics,
     platform examples, and exact recovery behavior.

7. Turn requirements into evidence-backed checks.
   - Use `check_node` for identity, text, visibility, or exact frame.
   - Use `check_node_detail` for one semantic attribute, `check_style` for a
     related style group, and `check_layout` for relations between nodes.
   - Use `summarize_node_detail` with a narrow filter before raw `node_detail`.
   - Structured checks prove exact Runtime facts. Screenshots prove visual
     composition. Use both when the conclusion depends on both.
   - Read [visual-regression.md](references/visual-regression.md) for screenshot,
     diff, baseline, coordinate, and dynamic-region rules.

8. Iterate until source-backed behavior is verified.
   - After source changes, build and relaunch only when permitted by the user and
     repository instructions.
   - Run `list_apps` again after relaunch because `appId` can change. Capture a
     fresh hierarchy because node identifiers are process-local.
   - Temporary patches test hypotheses; they are not implementation. Read
     [temporary-patches.md](references/temporary-patches.md) before patching and
     restore all patches before final verification.

## Tool Routing

| Goal | Preferred tool | Gate |
| --- | --- | --- |
| Discover Apps and compatibility | `list_apps` | Always first and after relaunch |
| Understand the current screen | `inspect_screen` | Retain `snapshotId` |
| Summarize hierarchy contents | `summarize_hierarchy` | Prefer when tree shape is unnecessary |
| Inspect bounded tree structure | `capture_hierarchy` | Reuse the snapshot and inspect truncation metadata |
| Find candidate nodes | `find_nodes` | Page without changing selectors or snapshot |
| Find and inspect one unique node | `inspect_node` | Establish uniqueness first |
| Read semantic properties | `summarize_node_detail` | Use raw `node_detail` only for omitted structure |
| Trace UI relations | `query_ui_graph` | Require Tool plus `uiGraphRelations` |
| Assert one node or property | `check_node`, `check_node_detail` | Use exact expectations and tolerances |
| Assert grouped style or layout | `check_style`, `check_layout` | Inspect the real content-bearing nodes |
| Capture latest visual state | `capture_screenshot` | Do not treat it as frozen-snapshot evidence |
| Compare or explain pixels | `compare_screenshot`, `inspect_diff` | Keep source, scale, and viewport explicit |
| Record or compare a reference | `record_baseline`, `compare_baseline` | Record only an accepted stable state |
| Test a presentation hypothesis | patch lifecycle tools | Read the patch reference and restore state |

## Evidence Gates

- Container geometry is insufficient when content can scale, align, overflow,
  crop, wrap, transform, cast effects, use masks, or draw descendants.
- A screenshot alone is insufficient for exact logical values. Runtime
  attributes alone are insufficient for final visual composition.
- Runtime geometry uses logical units. Screenshot dimensions and ignore regions
  use pixels. Convert only with the reported logical-to-pixel scale.
- A shared `snapshotId` keeps node identity and hierarchy stable, but a
  `liveRuntime` detail can be captured later. Treat timing-sensitive mixed
  evidence as `inconclusive` unless the time gap is irrelevant or reverified.
- A truncated hierarchy can prove facts about returned nodes, but cannot prove
  that an unreturned node or relationship is absent.
- Treat `visible` and `onscreen` as screen intersection. Use
  `hierarchyVisible` to distinguish otherwise displayable offscreen or
  ancestor-clipped nodes.
- Do not prescribe a universal scaling or clipping mode. Compare actual
  rendering semantics with the product requirement.

## Recovery

- No App: report discovery diagnostics and their recovery suggestion.
- Incompatible Runtime: report platform, Host/Runtime versions, `errorCode`,
  missing capabilities, and `recoverySuggestion`.
- Required Tool absent: report a Host/MCP installation or version gap; do not
  misreport it as a missing Runtime capability.
- Stale App or node: rediscover the App and capture a new snapshot.
- Expired or changed snapshot: restart the complete workflow; never combine old
  and new nodes, details, cursors, or relations.
- Ambiguous node: report candidates and narrow the selector before asserting.
- Missing detail: report the unavailable fact. Do not substitute a current node
  under an old `snapshotId`.
- Screenshot failure: report source, target identifier, and recovery suggestion;
  do not fall back to an unrelated target.

## Reporting

Report only evidence relevant to the question:

- Target App, platform, device, `appId`, and required capabilities.
- `snapshotId`, hierarchy source, and capture time for frozen evidence. When
  details are used, also report `detailSource` and `detailCapturedAtUnixTime`.
- Nodes inspected: class, text when relevant, `oid`, frame, and content-bearing
  role.
- Exact attributes or relation paths, expected and actual values, tolerances,
  and any missing evidence.
- Screenshot source, dimensions, scale, and diff result when visual evidence is
  used.
- Active temporary patches, clearly labeled as experiments.
- For design verification: readiness, preparation mode, authorization, and
  verification scope; design provenance and reference viewport; Target Context;
  Coverage Ledger counts; each failed or inconclusive expectation with expected,
  actual, and tolerance or range; screenshot/structured-evidence consistency;
  and final verdict.

For formal acceptance after readiness, end with `passed`, `failed`, or
`inconclusive`. Only source implementation plus clean Runtime verification can
produce `passed`. Before readiness, report only readiness, blocking condition,
and requested preparation. For exploratory or factual questions, answer the
finding directly and state uncertainty instead of forcing a pass/fail label.
