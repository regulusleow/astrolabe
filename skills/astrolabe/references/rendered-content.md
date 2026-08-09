# Rendered Content Verification

Read this reference whenever a review concerns apparent size, containment,
cropping, overflow, alignment, or visual balance. The governing rule is:

> The layout box and the rendered footprint are separate facts.

A container can have the expected frame while its content renders larger,
smaller, cropped, distorted, offset, transformed, or outside that frame.

## Five Evidence Layers

Evaluate only the layers relevant to the target, but do not skip one that can
change the conclusion.

1. **Layout box**: frame, bounds, constraints, and position in the parent.
2. **Intrinsic content**: image dimensions, text/glyph content, shape path,
   descendant drawing, or another natural content extent.
3. **Mapping policy**: scaling, aspect handling, alignment, content gravity,
   wrapping, line limits, or drawing mode.
4. **Clipping or masking**: container clipping, ancestor clipping, masks, and
   crop regions.
5. **Transform or visual effect**: transforms, shadows, borders, filters, and
   other drawing that changes the visible footprint without changing layout.

If a required evidence layer is unavailable, state which fact is missing. The
container frame alone cannot produce `passed` for a rendered-size or
containment requirement.

## General Decision Process

1. Locate the node that actually draws the content. A button or cell may only
   contain the image, label, Layer, or custom drawing node that matters.
2. Record the layout box in Runtime logical units.
3. Inspect intrinsic content evidence and the policy that maps it into the box.
4. Determine whether clipping or masking constrains the visible result.
5. Inspect transforms and visual effects when they can extend or move pixels.
6. Use a latest screenshot to confirm composition. Do not claim it is
   synchronized with an older hierarchy snapshot.
7. Compare the resulting semantics with the requirement. Intentional overflow,
   crop, or effects may be valid, but they require explicit evidence.

## Images And Icons

Inspect the image-bearing node, not only its container. Read the returned
platform-namespaced equivalents of:

- bounds and frame;
- `imageSize` and `imageScale`;
- `contentMode` or platform mapping policy;
- clipping, masks, insets, resizable regions, and transforms when exposed;
- rendering mode when it affects appearance.

Use these consequences rather than memorizing one platform-specific fix:

| Evidence | Consequence to verify |
| --- | --- |
| Intrinsic image exceeds bounds under an unscaled mode such as center or edge alignment | The rendered content remains intrinsically sized; it either overflows or is clipped |
| Aspect fit | Content stays inside the box but may leave unused space |
| Aspect fill | Content covers the box but may crop outside its aspect-preserving projection |
| Stretch or scale-to-fill with different aspect ratios | Content may distort |
| Unknown mapping or clipping policy | Rendered containment is unproven |

Do not prescribe `scaleAspectFit`, clipping, or asset resizing automatically.
First identify the expected behavior. An intentionally oversized illustration
and an icon that must remain inside its control have different contracts.

## Text And Custom Drawing

The same model applies beyond images:

- Text can exceed a label's expected visual region through wrapping, truncation,
  line height, font metrics, transforms, or disabled clipping.
- A shape path can draw outside its Layer bounds or be altered by a mask.
- Sublayers and custom drawing can extend outside a View's frame.
- Shadows, borders, and filters can expand the visible footprint without
  changing bounds.
- Transforms can change apparent size and position after layout.

When Runtime details do not expose the decisive drawing fact, use available
relations to inspect the real rendering node and visual evidence to confirm the
result. Missing decisive evidence means `inconclusive`, not `passed`.

## Approval Gate

For claims such as “correct size”, “fits inside”, “not cropped”, “aligned”, or
“matches the design”, require evidence for every applicable layer above. Report
the observed mismatch or risk explicitly; do not let a correct container frame
cancel contradictory content evidence.
