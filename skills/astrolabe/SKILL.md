---
name: astrolabe
description: Use when implementing, debugging, or reviewing a UI on a supported mobile platform and runtime frames, styles, visibility, screenshots, visual diffs, baselines, or temporary presentation experiments can verify the running result.
---

# Astrolabe UI Inspector

Use Astrolabe to observe and verify the UI that is actually running on a
supported mobile platform. Source code describes intent; Runtime nodes,
semantic attributes, and system screenshots show the result. Do not claim that
a UI is correct from source inspection alone when an inspectable App is running.

## Required Workflow

1. Discover the target with `list_apps`.
   - Read `diagnostics` before concluding that no App is available.
   - Match the user-provided App, application identifier, virtual device, or
     physical device.
   - If multiple candidates remain, ask which one to inspect.
   - Check `compatibility.status`, `capabilities`,
     `missingRuntimeCapabilities`, and `recoverySuggestion` before choosing
     tools.
   - Read `platform` instead of inferring a framework or transport from
     `appId`, device names, class names, or attribute namespaces.
   - Select tools only from advertised `capabilities`. The same Tool names are
     used across platforms; never invent `ios_*` or `android_*` Tool names.
   - Use the exact latest `appId` for every subsequent call.

2. Establish current screen context.
   - Start with `inspect_screen` for a compact screen overview and suggested
     targets.
   - Save the returned `snapshotId`. Pass it to subsequent hierarchy, node
     lookup, detail, and structured-check tools while investigating that same
     screen. This prevents navigation or dynamic updates from silently changing
     the node set midway through the workflow.
   - Omit `snapshotId` only when the task requires the latest screen or the user
     has intentionally navigated to a new state. The resulting call captures a
     new hierarchy and returns a new `snapshotId`.
   - Treat its suggested targets as curated starting points. Infrastructure
     containers, backing layers, and contentless full-screen generic controls
     are intentionally omitted; use `find_nodes` when one of those
     implementation nodes is the explicit inspection target.
   - Use `summarize_hierarchy` when bounded onscreen/text node lists and omitted
     counts are sufficient.
   - Use `capture_hierarchy` only when tree structure is required. Keep its
     default node bound, add `maxDepth` when possible, and read `nodeCount`,
     `returnedNodeCount`, `omittedNodeCount`, and `truncated` before assuming
     the tree is complete.

3. Locate nodes before inspecting or asserting.
   - Use `find_nodes` to see all plausible matches before invoking a tool that
     selects the first match.
   - When `hasMore` is true, keep the same `appId`, `snapshotId`, and selectors,
     and pass the returned `nextCursor` unchanged. Later pages read the frozen
     first-page result rather than recapturing a dynamic hierarchy. If
     `pagination_snapshot_expired` is returned, restart from the first page.
     Treat `pagination_snapshot_changed` as invalidated snapshot data and also
     restart instead of combining results.
     Do not increase `limit` beyond the advertised bound to force one oversized
     result.
   - Search broad to narrow: visible text, semantic role, custom class name,
     frame region, then hierarchy path.
   - Prefer stable semantic roles when text is localized, dynamic, or
     truncated.
   - Once the target is identified, use its latest `oid` or `detailOid` for
     precise follow-up calls.
   - Treat `visible` and `onscreen` as screen-intersection results. Use
     `hierarchyVisible` only to distinguish an otherwise displayable node that
     is outside the screen or clipped by an ancestor.

4. Traverse UI relations only when hierarchy edges cannot answer the question.
   - Require the App to advertise `uiGraphRelations`. If it does not, keep the
     investigation read-only and report the missing capability.
   - Follow `capture_hierarchy` → `query_ui_graph` →
     `summarize_node_detail`: choose `rootOid` from the captured hierarchy, then
     pass the same `appId` and `snapshotId` through graph traversal and detail
     inspection. Graph queries never capture or refresh a hierarchy.
   - Request only the exact namespaced `relationTypes` needed by the task. Treat
     platform-specific relation names as scoped Runtime data, not as portable
     assumptions or reasons to invent platform-specific Tool names.
   - Use `outgoing` when following relations owned by the root, `incoming` when
     locating owners of the root, and `both` only when the question requires
     both directions.
   - Keep traversal bounded. Read `truncated`, `truncationReasons`,
     `frontierOids`, and `omittedFrontierCount` before deciding whether to
     expand. Continue deliberately from a returned frontier on the same frozen
     snapshot instead of requesting the whole graph.
   - Inspect only relevant returned nodes with `summarize_node_detail`. If the
     snapshot expires, capture a new hierarchy and restart the complete chain;
     never combine nodes or relations from different snapshots.

5. Inspect the smallest useful data surface.
   - Use `inspect_node` to find one node and obtain its details in one call.
   - Use `summarize_node_detail` for flattened, searchable semantic attributes.
     Pass `filter` when only font, color, layout, image, text, or another small
     attribute group is needed.
   - Use raw `node_detail` only when the summary omitted necessary structure or
     metadata.
   - With `snapshotId`, node selection always comes from the frozen hierarchy.
     Node detail is loaded from the snapshot cache when available; otherwise it
     is requested by the original `detailOid` and cached. Never drop
     `snapshotId` to recover a missing old node, because that can match a
     different node on the current screen.
   - For controls, inspect child label/image nodes when visible content is not
     exposed by the parent. For example, button text may belong to a nested
     label.
   - For icon or image sizing, inspect the image-bearing node instead of
     stopping at its container geometry. A correct frame or bounds alone does
     not prove that the image content renders at the intended size.
   - Read the platform-namespaced content mode, `imageSize`, `imageScale`, and
     rendering mode attributes returned by node details together with the node
     frame and bounds. On UIKit these are commonly exposed as
     `ios.view.contentMode`, `ios.imageView.imageSize`,
     `ios.imageView.imageScale`, and `ios.imageView.renderingMode`; other
     platforms may expose different namespaced paths.
   - Treat `imageSize` as the logical image size reported by the Runtime,
     regardless of whether the source asset was SVG, PDF, PNG, or another
     format.
   - When `imageSize` exceeds the bounds and an unscaled content mode such as
     `center` is used, treat cropping, overflow, or an oversized icon as a
     concrete risk and verify it against the design and a latest screenshot.
     Do not infer that `scaleAspectFit` is universally correct: centered,
     aspect-fill, resizable, or intentionally cropped content may be valid.

6. Convert requirements into structured checks.
   - Use `check_node` for class, text, visibility, or exact frame checks.
   - Use `check_node_detail` for one semantic attribute.
   - Use `check_style` for a group of font, color, radius, border, shadow, or
     similar style expectations on one node.
   - Use `check_layout` for spacing, alignment, center, width, or height
     relations between two nodes.
   - Prefer these assertion tools over manual arithmetic when they express the
     requirement directly. Use explicit tolerances only when the requirement
     allows them.

7. Use screenshots as visual evidence, not as a replacement for node data.
   - Use `capture_screenshot` with `source: "auto"` for visual review.
   - Screenshot tools always capture the latest screen and do not accept
     `snapshotId`. Do not claim that a screenshot taken after navigation is
     pixel-synchronized with an older hierarchy snapshot.
   - Use node attributes for exact logical values such as frames, spacing, font
     size, colors, and corner radius. On iOS, logical geometry maps to points.
     On Android View, it maps to density-independent pixels after Runtime
     density normalization.
   - Use `compare_screenshot` when an expected PNG exists and pixel-level pass
     or fail is sufficient.
   - Use `inspect_diff` when the AI must explain mismatch regions, correlate
     them with Runtime nodes, and choose the next investigation.
   - Use `record_baseline` and `compare_baseline` for repeatable regression
     checks across source iterations.

8. Iterate until the running UI passes.
   - After source changes, build and relaunch using the project workflow when
     permitted by the user and repository instructions.
   - Run `list_apps` again after every relaunch because `appId` can change.
   - Capture a fresh hierarchy because node identifiers are process-local.
   - Repeat the relevant structured checks and visual comparison.
   - Do not reuse an old `appId`, `oid`, or `detailOid` after an App restart.

## Tool Selection

| Goal | Preferred tool | Use instead when |
| --- | --- | --- |
| Discover Apps and capabilities | `list_apps` | Always run first or after relaunch |
| Understand the current screen | `inspect_screen` | Use `summarize_hierarchy` for bounded lists |
| Continue investigating one captured screen | Pass its `snapshotId` | Omit it only to capture the latest screen |
| Export a bounded UI tree | `capture_hierarchy` | Set `maxDepth`; inspect truncation metadata |
| Trace non-hierarchy UI relations | `query_ui_graph` | Require `uiGraphRelations`; inspect truncation metadata before expanding |
| Find candidate nodes | `find_nodes` | Follow `nextCursor`; restart when the frozen snapshot expires |
| Find and inspect one node | `inspect_node` | Use after uniqueness is established |
| Read semantic properties | `summarize_node_detail` | Use `node_detail` for omitted raw structure |
| Assert node identity/frame | `check_node` | Use node details for semantic styles |
| Assert one property | `check_node_detail` | Use `check_style` for multiple properties |
| Assert multiple styles | `check_style` | Use exact semantic paths when available |
| Assert spacing/alignment/size | `check_layout` | Avoid manual frame arithmetic when supported |
| Capture visual state | `capture_screenshot` | Pair with node data for exact conclusions |
| Compare with expected PNG | `compare_screenshot` | Use `inspect_diff` when diagnosis is needed |
| Explain visual mismatch | `inspect_diff` | Prefer baseline input when one exists |
| Create reusable reference | `record_baseline` | Record only an accepted, stable UI state |
| Check against a reference | `compare_baseline` | Keep device and viewport conditions stable |
| Discover temporary patch support | `list_patchable_attributes` | Run before every patch experiment |
| Test a UI hypothesis | `apply_attribute_patch` | Only for supported presentation attributes |
| Inspect or restore patches | `list_attribute_patches`, `revert_attribute_patch`, `clear_attribute_patches` | Clear all before final verification |

## Common Verification Paths

### Check One UI Requirement

1. `list_apps`
2. `inspect_screen` and retain its `snapshotId`
3. `find_nodes` with that `snapshotId`
4. `summarize_node_detail` with the same `snapshotId` and a narrow filter
5. `check_node`, `check_node_detail`, `check_style`, or `check_layout` with the same `snapshotId`
6. `capture_screenshot` only when the latest visual context is useful

### Trace A UI Relation

1. `list_apps` and confirm `uiGraphRelations` is advertised.
2. `capture_hierarchy` and retain its `snapshotId`.
3. Select the root `oid` from that hierarchy.
4. `query_ui_graph` with the same `appId` and `snapshotId`, the narrowest useful
   `relationTypes`, and the direction required by the question.
5. Read `truncated`, `truncationReasons`, `frontierOids`, and
   `omittedFrontierCount`. Expand from a returned frontier only when the missing
   branch matters to the investigation.
6. Use `summarize_node_detail` on relevant returned nodes with the same frozen
   snapshot, then report the exact relation path used as evidence.

For a UIKit rendering investigation, a task-scoped example is
`UIView --ios.view.backingLayer--> CALayer --tree.layerChild--> descendant
CALayer`. Query those exact relation types in the `outgoing` direction. Do not
assume that path exists on another platform or Runtime.

### Match a Design

1. Inspect the screen and locate each important visible node.
2. Reuse the returned `snapshotId` for node lookup, details, and structured checks.
3. Verify geometry and styles with structured checks in Runtime logical units.
4. Capture a latest screenshot for composition and visual review.
5. If a comparable expected image exists, use `inspect_diff` to localize
   differences and inspect the returned affected nodes.
6. Change source, relaunch, refresh IDs, and repeat until all required checks
   pass.

### Verify Icon Or Image Rendering

1. Locate the actual image-bearing node, including nested image views inside a
   control, and retain the current `snapshotId`.
2. Check its frame and bounds, then inspect `view.contentMode`,
   `imageView.imageSize`, `imageView.imageScale`, and rendering mode on the same
   snapshot.
3. Compare the logical image size with the container bounds. If the image is
   larger and the content mode does not scale, report the potential rendered
   size or cropping mismatch instead of declaring the container frame correct.
4. Express known requirements with `check_node_detail` or `check_style`; use a
   latest screenshot to confirm the resulting visual composition.
5. Decide whether `center`, aspect fit, aspect fill, or another mode is correct
   from the design intent. Never prescribe one mode solely from the asset file
   type.

### Run a Visual Regression Check

1. Record a baseline only from an accepted state.
2. Keep target device, viewport, appearance, scale, and stable content
   consistent.
3. Compare with `compare_baseline` for pass/fail or `inspect_diff` for causes.
4. Inspect affected nodes before changing source.
5. Re-record the baseline only when the intended design itself changed, never
   merely to hide a regression.

## Temporary Attribute Patches

Use patches to test a concrete presentation hypothesis without rebuilding.
Patches are not implementation and must never be reported as a completed fix.

1. Confirm the App advertises both `attributePatchDiscovery` and
   `attributePatching`.
2. Call `list_patchable_attributes` and select an advertised
   `attributePattern` whose `targetRoles` match the target node. An empty
   `targetRoles` list means the attribute can target any compatible node role.
3. Refresh the hierarchy, locate the latest node, and inspect the exact semantic
   attribute path. Patch calls target live Runtime objects and do not read a
   frozen hierarchy snapshot. For a
   parameterized pattern, replace `<identifier>` with the concrete identifier
   returned by node details.
4. Encode the value according to `valueType`, `valueConstraints`, and
   `acceptedFormats`; never infer an unadvertised property or format. Use exact
   casing for catalog `allowedValues`. When a measurement advertises exactly one
   accepted format, provide its numeric magnitude and let the Host encode the
   catalog unit.
5. Apply one testable hypothesis with `apply_attribute_patch`.
6. Confirm `actualValue`, then use `list_attribute_patches` to verify the active
   state. Applying the same node and attribute again replaces that patch while
   preserving its first original value and patch identifier.
7. Re-read live node details and capture or compare a screenshot when visual
   evidence is relevant.
8. If disproved, revert the patch. If confirmed, translate it into a source
   change.
9. Use `revert_attribute_patch` for one experiment or
   `clear_attribute_patches` for all experiments.
10. Rebuild or relaunch, obtain a new `appId`, and verify that the source-backed
   UI passes with `patchCount == 0`.

Treat the Runtime catalog as the only source of truth for supported paths.
Never rely on a remembered whitelist because Runtime versions and platforms may
advertise different attributes.

Patches persist across separate MCP or CLI connections while the same App
Runtime is alive. App relaunch, rebuild, or Runtime replacement removes them.
If `patchConflict` is returned, list active patches and revert the conflicting
one before retrying. Do not use patches for business state, persistent data, or
arbitrary method invocation.

## Node Search Recovery

When a node cannot be found:

1. Run `list_apps` again and reject stale App IDs.
2. Refresh with `inspect_screen` or `summarize_hierarchy`.
3. Remove over-specific filters and search by one stable signal at a time.
4. Use `find_nodes` to expose ambiguity instead of relying on first-match
   behavior, and page until the target is found or `hasMore` is false.
5. Inspect parent, child, and sibling nodes for nested visible content.
6. Use the screenshot and visible frames to narrow the region, then map back to
   Runtime nodes.
7. If still unresolved, report selectors attempted, candidate nodes, and
   current top-level containers. Do not claim the UI element is absent.

## Screenshot And Diff Rules

- Runtime frames and spacing declare `unit: "logical"`; screenshot dimensions
  and ignore regions declare pixel units. Convert only with the reported
  logical-to-pixel scale. On iOS, logical units correspond to points; on
  Android View, they correspond to density-independent pixels.
- A hierarchy `snapshotId` freezes node identity, structure, geometry, and
  basic attributes for up to five minutes. Local quota eviction can shorten
  that lifetime. It does not freeze the device screen.
- `detailSource: snapshotCache` means detail was reused from the page snapshot;
  `detailSource: liveRuntime` means the original snapshot node was resolved but
  its detail had to be fetched and cached during this call.
- Keep `source: "auto"` unless a specific virtual or physical target is
  required. When multiple targets are connected, provide `targetIdentifier`
  to remove ambiguity.
- Do not use a low-resolution screenshot for pixel conclusions unless the task
  explicitly accepts it.
- For dynamic clocks, avatars, timers, names, and similar content, prefer
  `ignoreNodeQueries` with stable semantic roles. Use named masks for system UI
  such as the status bar or home indicator.
- Ignore only known dynamic regions. Broad masks can hide real layout defects.
- Prefer `inspect_diff` with node correlation before guessing why pixels differ.

## Failure Handling

- No App: report discovery diagnostics and their recovery suggestion.
- Incompatible Runtime: report platform, Host/Runtime versions,
  `errorCode`, missing capabilities, and `recoverySuggestion`; do not call
  unsupported tools.
- Stale App or node: refresh App discovery and hierarchy.
- Expired hierarchy snapshot: capture a new page snapshot and restart the
  workflow; do not combine new nodes with results from the expired snapshot.
- Unsupported UI graph: report that `uiGraphRelations` is missing and do not
  infer relations from platform implementation details.
- Truncated UI graph: report `truncationReasons`, `frontierOids`, and
  `omittedFrontierCount`; expand only the frontier required by the question.
- Snapshot detail unavailable: report that the original Runtime object is no
  longer readable. Do not recapture the hierarchy and substitute a current
  node under the old `snapshotId`.
- Ambiguous node: use `find_nodes`, compare candidates, then target an `oid`.
- Unsupported or invalid patch: refresh `list_patchable_attributes`, keep the
  operation read-only, and report the structured error instead of attempting
  another property blindly.
- Screenshot failure: report selected source, target identifier, and recovery
  suggestion; do not silently fall back to an unrelated App or device.

## Reporting

Report concise, reproducible evidence:

- Target App, platform, device or virtual device, current `appId`, and relevant
  advertised capabilities.
- Hierarchy `snapshotId`, `hierarchySource`, and capture time.
- Nodes inspected: class, text when available, `oid`, and frame.
- Exact attributes or relation paths checked, including direction and relation
  types, expected values, actual values, and tolerances.
- UI graph truncation reasons, frontier OIDs, and omitted frontier count when a
  graph result is incomplete.
- Screenshot source, dimensions, scale, and diff result when used.
- Active temporary patches, if any, clearly labeled as experiments.
- Node-detail source and detail capture time when a frozen hierarchy was used.
- Uncertainty caused by missing data, dynamic content, ambiguity, or unsupported
  Runtime capabilities.

End with one explicit result: `passed`, `failed`, or `inconclusive`. A temporary patch
may prove a hypothesis, but only source implementation plus a clean Runtime
verification can produce `passed` for completed development.
