# UI Graph Inspection

Read this reference for ownership, cross-tree, mask, backing-layer, or another
relation that ordinary hierarchy inspection cannot express efficiently.

## Entry Gate

Two independent gates must pass:

1. The installed Host/MCP exposes the `query_ui_graph` Tool.
2. The selected App advertises `uiGraphRelations`.

If the Tool is unavailable while the capability is present, report a Host/MCP
installation or version gap. If the Tool exists but the capability is absent,
report a Runtime capability gap. Do not collapse these failures.

Use hierarchy directly for ordinary parent-child inspection. Use UI Graph when
the question concerns non-hierarchy ownership or when a bounded, uniform
relation traversal materially helps. Derived `tree.viewChild` and
`tree.layerChild` remain available, but they do not require the Runtime to
duplicate authoritative hierarchy edges.

## Frozen Workflow

1. Run `inspect_screen` and retain its `snapshotId`.
2. When the root is omitted from the compact result, call `capture_hierarchy`
   with the same `snapshotId`; do not recapture the current screen.
3. Select `rootOid` from that frozen hierarchy.
4. Call `query_ui_graph` with the same `appId` and `snapshotId`, the narrowest
   useful `relationTypes`, and the required direction.
5. Read `truncated`, `truncationReasons`, `frontierOids`, and
   `omittedFrontierCount` before expanding.
6. Inspect relevant returned nodes with `summarize_node_detail` under the same
   snapshot.

Use `outgoing` for relations owned by the root, `incoming` to locate owners, and
`both` only when the question genuinely needs both directions. Continue from a
frontier only when that branch matters; never request an unbounded graph.

## Platform-Scoped Examples

UIKit backing and descendant Layer traversal:

```text
UIView --ios.view.backingLayer--> CALayer --tree.layerChild--> CALayer
```

UIKit mask ownership:

```text
UIView --ios.view.backingLayer--> CALayer --ios.layer.mask--> CAShapeLayer
```

The mask edge proves object identity and ownership. Shape path, fill rule, and
other drawing semantics belong to node details rather than relation extensions.

Android View hierarchy through the uniform relation API:

```text
ViewGroup --tree.viewChild--> View
```

Do not assume that a platform-scoped relation exists on another Runtime, and do
not invent platform-specific MCP Tool names.

## Recovery

- `ui_graph_node_not_found`: verify that `rootOid` came from the same frozen
  snapshot. Do not substitute a current node under the old snapshot.
- `invalid_ui_graph_snapshot`: capture one fresh hierarchy and retry the full
  chain once. If it repeats, report a Host/Runtime graph-contract defect with
  both versions; do not keep retrying or infer missing edges.
- Snapshot expired or mismatched: restart from screen inspection and keep every
  subsequent node and relation on the new snapshot.
- Missing capability: stay read-only and report the Runtime recovery suggestion.
- Truncated result: report reasons and frontier metadata, then expand only a
  branch required by the question.

Report the exact relation types, direction, root, returned path, and any
truncation. Unknown or malformed topology cannot produce `passed`.
