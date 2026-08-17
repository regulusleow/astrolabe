# Design Verification

Use this reference only after Target State Readiness is `ready`. It defines
design intent; Runtime evidence only reports what is rendered.

## Target State Readiness

Observe the current screen first. If the target screen or View is absent, use
visible normal UI interaction only when both the Tool and Runtime capability
exist. Otherwise request one developer choice: manual navigation, preparation
of real business conditions, or explicit debug-fixture/mock authorization.

Never use an App Router, internal route, private initializer, unapproved deep
link, source shortcut, or business-state mutation. After preparation,
rediscover and re-observe the target, then discard every preliminary readiness
snapshot. Only the later formal-acceptance step creates the authoritative
`inspect_screen` snapshot. Before readiness, report the blocking condition and
preparation request, not a page verdict.

Record `status`, observed and target screen, blocking condition, preparation
mode, developer authorization, and verification scope. An authorized mock is
`presentation-only`: it can verify rendering but leaves navigation, business
conditions, data mapping, lifecycle, and release behavior unverified.

## Design Source Priority and Target Context

Use design sources in this priority order:

1. Explicit PRD requirements, design annotations, and Design Tokens.
2. The matching Figma variant and its Auto Layout, constraints, min/max,
   hug/fill, spacing mode, and breakpoint rules.
3. An accepted baseline with the same Target Context.
4. No authoritative source: mark each affected required expectation
   `inconclusive`.

Target Context records the Runtime conditions that determine which contract
applies: `viewportWidth`, `viewportHeight`, `safeAreaInsets`, `orientation`,
`sizeClass`, `displayScale`, `fontScale`, `locale`, `appearance`, and
`systemOccupancy`. Keep logical units distinct from screenshot pixels.

Default acceptance scope is the current Target Context supplied by the
developer. A passing current device is sufficient for that verdict. Do not
automatically start, switch to, or require another device, simulator, viewport,
or breakpoint because an adaptive or display-scale policy exists. Expand scope
only when the developer explicitly requests multi-device, breakpoint, or
additional Target Context acceptance.

## Design Expectation Record

Create one record for every required design fact. Explain every field in the
review artifact:

| Field | Meaning |
| --- | --- |
| `identifier` | Stable, reportable requirement name. |
| `category` | Content/state, geometry, spacing, typography, color, appearance, image rendering, adaptive behavior, or final composition. |
| `targets` | One or more uniquely located design nodes. |
| `metric` | Measured fact, such as width, spacing, centerY, fontSize, or color. |
| `policy` | Comparison semantics: exact, minimum, maximum, range, relation, derived, or conditional. |
| `expected` | Value, boundary, relation, or formula inputs required by the policy. |
| `unit` | Logical unit, pixel, ratio, color, or another explicit measurement unit. |
| `tolerance` | Measurement or floating-point error only. It is not layout flexibility. |
| `conditions` | Viewport, orientation, size class, locale, or state where this record applies. |
| `required` | Whether this record affects the page verdict. |
| `source` | PRD entry, Figma node, Design Token, or accepted baseline provenance. |

Do not create expectations from the current implementation. A selector must
identify one unique node before a check can pass. Missing uniqueness,
coordinate-system clarity, authoritative expectation, or required evidence is
`inconclusive`.

## Policy Semantics

| Policy | Meaning |
| --- | --- |
| `exact` | Actual equals the fixed expected value within measurement error. |
| `minimum` | Actual is not below the declared lower bound. |
| `maximum` | Actual is not above the declared upper bound. |
| `range` | Actual lies in the declared inclusive interval. |
| `relation` | Nodes satisfy declared alignment, equality, ordering, or spacing relation. |
| `derived` | Expected value is calculated from Target Context and declared fixed inputs. |
| `conditional` | Select a declared sub-policy for the matching breakpoint, orientation, or state. |

Treat font, size, weight, color, corner radius, border, fixed component size,
fixed edge inset, and fixed internal gap as `exact` unless the source says
otherwise. Treat a gap as flexible only when its source declares a minimum,
maximum, range, remaining-space formula, hug/fill, space-between, safe-area
rule, or breakpoint policy. Tolerance is measurement error only; never use a
large tolerance to imitate a flexible range.

## Display Quantization Tolerance

Tolerance covers renderer measurement and display quantization only; it never
adds layout flexibility or changes a fixed source contract. For frame-derived
geometry and relations, derive the default quantization budget from Target
Context `displayScale`: at most `1 / displayScale` logical unit, or one physical
pixel. Use the smallest tolerance that explains the evidence. If a source or
token declares a stricter tolerance, use that stricter value. If display scale
or coordinate provenance is unavailable, do not infer a budget.

Report raw `actual` values even when they pass within this budget. Apply the
declared tolerance explicitly: `exact` passes when absolute difference is at
most tolerance; `minimum` passes when actual is at least lower bound minus
tolerance; `maximum` passes when actual is at most upper bound plus tolerance;
and `range` passes when actual is within the inclusive bounds expanded by the
tolerance. This budget cannot conceal a meaningful boundary violation, overflow,
or fixed-gap regression.

For example, at displayScale 2, a measured `centerY` relation difference of
`-0.25` passes within the 0.5 logical-unit quantization budget. An exact
Avatar-to-Title requirement of 10 with actual 18 and tolerance 0.01 still
fails. Fixed component sizes and edge insets remain exact unless their source
declares another policy.

## Coverage and Evidence Gates

Maintain a Coverage Ledger with required expectation counts for: content and
state; geometry; spatial relations; typography; color; appearance; image
rendering; adaptive behavior; and final composition. A page has complete
coverage only when every required expectation is passed, failed, inconclusive,
or `notApplicable` with its evidence status recorded. `notApplicable` is valid
only when the authoritative contract says the expectation does not apply to
current conditions. It is neither unchecked nor a result that blocks `passed`
by itself; an Agent must not use it to evade a required check.

The Coverage Ledger must be complete for the current acceptance scope and
Target Context only. Other viewports are outside the current verdict by default;
their absence neither blocks `passed` nor makes the result `inconclusive`.

Use frozen Runtime evidence for exact values and relations. Confirm coordinates
use the same coordinate space before calculating a gap or alignment. Use latest
screenshots for composition and correlate them to Runtime nodes. If a screenshot
reveals an unexplained overflow, clipping, occlusion, or other contradiction,
the page cannot pass even when structured checks pass; investigate with a fresh,
consistent evidence chain.

Aggregate only after readiness:

```text
any required failed -> failed
otherwise any required inconclusive or unchecked -> inconclusive
otherwise all applicable required expectations passed and no unexplained screenshot contradiction -> passed
```

## ContactCell Example

This example illustrates per-gap policies; it is not a universal component
template. For `ContentView`, `Avatar`, `Title`, and `CallIcon`:

- Avatar and CallIcon are exactly 20x20.
- Avatar leading and CallIcon trailing edges are exactly 15.
- Avatar-to-Title spacing is exactly 10.
- Title-to-CallIcon spacing is a minimum of 10.
- Avatar, Title, and CallIcon each have a `centerY` relation to ContentView.

The Title-to-CallIcon gap can grow with remaining space, while the other stated
gaps remain fixed. A static Figma coordinate alone does not authorize that
growth; the flexible contract does.

## Reporting

For every design verification, report readiness and preparation, authorization
and scope, design provenance and reference viewport, Target Context, Coverage
Ledger counts, every failed or inconclusive expectation with expected/actual and
tolerance or range, screenshot/structured-evidence consistency, and final
verdict. For `presentation-only`, explicitly list end-to-end facts left
unverified.
