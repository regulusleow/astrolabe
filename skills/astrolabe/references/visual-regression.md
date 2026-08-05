# Visual And Baseline Verification

Read this reference when screenshots, design matching, pixel differences, or
reusable baselines matter.

## Screenshot Evidence

- Use `capture_screenshot` with `source: "auto"` unless a specific virtual or
  physical target is required.
- Screenshots capture the latest screen and do not accept `snapshotId`. Never
  claim pixel synchronization with an older hierarchy snapshot.
- Runtime frames and spacing use logical units. Screenshot dimensions and masks
  use pixels. Convert only with the reported logical-to-pixel scale.
- Do not make pixel conclusions from a low-resolution screenshot unless the
  task explicitly accepts that limitation.
- Pair screenshots with Runtime details when exact geometry, content mapping,
  clipping, or style values affect the verdict.

## Match A Design

1. Freeze the hierarchy and locate each real content-bearing node.
2. Verify exact Runtime geometry and semantic styles.
3. Apply the rendered-content evidence gate before approving containment or
   apparent size.
4. Capture a latest screenshot for composition.
5. Use `inspect_diff` when an expected image exists and the cause matters.
6. Inspect affected nodes before changing source.
7. After implementation, relaunch, refresh identifiers, and repeat.

## Baselines

1. Record a baseline only from an accepted, stable state.
2. Keep device, viewport, appearance, scale, and stable content consistent.
3. Use `compare_baseline` for repeatable pass/fail and `inspect_diff` for causes.
4. Re-record only when the intended design changed, never to hide a regression.

For dynamic clocks, timers, avatars, names, and similar content, prefer stable
node-query ignore regions. Use named masks for known system UI. Ignore only the
smallest justified region because broad masks can hide real defects.
