---
name: astrolabe
description: Use when inspecting a running mobile app UI or reviewing whether an implementation matches supplied design references.
---

# Astrolabe

Use Astrolabe MCP to read the UI hierarchy, node properties, and screenshots of a mobile app that is currently running. UI review is read-only by default, and every conclusion must be based on current runtime evidence.

## 1. Acceptance prerequisites

First use `list_apps` to check runtime availability and compatibility. Only then use `inspect_screen` to confirm the target state. Before formal acceptance, all of these conditions must hold:

- The app must be running and remain in the foreground.
- `list_apps` finds the target app, and its `compatibility.status` allows inspection to continue.
- `inspect_screen` confirms that the current screen shows the UI, component, or state to be reviewed.

A successful build, passed unit tests, completed installation, or an app that was launched and then killed does not make the app inspectable.

If `list_apps` cannot find the target app, stop and ask the developer to launch it and keep it in the foreground. If compatibility does not allow inspection, report `compatibility.status` and `recoverySuggestion`, then stop. If the target state is not shown, state which UI, component, or state the developer must prepare, then wait for the developer.

Keep acceptance read-only: do not click, scroll, type, trigger UI elements, events, routes or deep links, or change business state.

After the developer prepares the target state, restart from `list_apps`.

## 2. Basic Astrolabe MCP calls

Call the tools in this order:

1. `list_apps`: confirm that the target app is discoverable and obtain the latest `appId`; check `compatibility.status`, and report `recoverySuggestion` and stop if incompatible.
2. `inspect_screen`: confirm that the current UI and state match the acceptance target, then obtain a new `snapshotId`.
3. `find_nodes`: find candidate nodes by text, semantic role, or class name.
4. `inspect_node` or `summarize_node_detail`: read a node's frame, text, style, and other properties.
5. `capture_screenshot`: capture the current rendered result.
6. For exact assertions, use `check_node`, `check_node_detail`, `check_style`, or `check_layout`.

Within one static inspection, reuse the same `appId` and `snapshotId` for hierarchy, lookup, detail, and assertion tools. A screenshot represents the latest state at capture time and is not guaranteed to be synchronized with an older snapshot.

After the app is restarted, killed, or reinstalled, run `list_apps` and `inspect_screen` again and discard the old `appId`, `snapshotId`, and node identifiers. If only the target state changes, run `list_apps` again to confirm the current `appId`, then run `inspect_screen` for a new `snapshotId`; the `appId` may stay the same, but do not reuse the old snapshot or node evidence.

If multiple nodes match, narrow the selector instead of guessing. When evidence is missing, report “unable to verify” instead of inferring runtime behavior from source code.

## 3. Design consistency review

Confirm the design references, target UI state, and runtime environment before inspecting the current screen. Design references may include design tool files, images, annotations, visual specifications, design systems, or an accepted reference UI. If the runtime state does not match the acceptance target, follow the prerequisites and wait for the developer.

Compare each design requirement with the runtime actual:

- Text, font family, font size, font weight, line height, and wrapping
- Text, background, border, and icon colors and opacity
- Position, width, height, alignment, relative spacing, and safe areas
- Corner radius, borders, shadows, clipping, and occlusion
- Image or icon assets, aspect ratio, scaling, and rendered output

Use node properties for exact values and screenshots for overall composition. Verify relative spacing from the relevant node frames or with `check_layout`.

Use this report structure:

```markdown
### Target
- App, runtime environment, target state, `appId`, `snapshotId`, and node `oid`

### Differences
| Item | Design requirement | Runtime actual | Evidence | Result |
| --- | --- | --- | --- | --- |

### Conclusion
- Aligned / Not aligned / Unable to verify
```
