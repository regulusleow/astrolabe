# Astrolabe（星盘）

English | [简体中文](README.zh-CN.md)

Astrolabe is a runtime UI inspection tool for AI coding agents. It combines a
Swift CLI, a local MCP server, and a packaged agent skill to inspect and verify
running mobile interfaces.

Android View inspection is supported through Astrolabe Runtime for Android 2.0.

## Features

- Discover supported apps running in iOS simulators, Android emulators, or on
  USB-connected devices.
- Inspect UIKit and Android View hierarchies, node frames, visibility, text,
  styles, semantic roles, and detailed runtime attributes.
- Capture native-resolution screenshots and compare them with expected images
  or recorded baselines.
- Query nodes and verify style, layout, and node-detail expectations.
- Keep related hierarchy operations bound to a frozen page snapshot.
- Apply allowlisted, in-memory presentation patches in Debug builds and revert
  them without changing source code or persistent application state.
- Expose the same inspection workflow through CLI commands, MCP tools, and the
  bundled `astrolabe` skill.

## Requirements

- macOS 13 or later
- Swift 5.9 or later
- Node.js 22 or later
- Android Platform Tools (ADB) when inspecting Android apps
- A supported app with an Astrolabe Runtime SDK enabled in Debug builds

## Installation

Install Astrolabe with Homebrew:

```bash
brew install regulusleow/tap/astrolabe
```

Configure Astrolabe for a specific AI client:

```bash
astrolabe install --client codex
astrolabe install --client opencode
astrolabe install --client claude-code
```

To configure every detected AI client at once:

```bash
astrolabe install --all-detected
```

Homebrew lifecycle operations do not modify AI-client configuration. Restart
the configured AI clients after running `astrolabe install`.

To install from source, clone the repository, then install Astrolabe for the AI
clients you use:

```bash
git clone https://github.com/regulusleow/astrolabe.git
cd astrolabe
npm run install:codex
npm run install:opencode
npm run install:claude-code
```

Codex, OpenCode, and Claude Code can be installed independently or together. A
multi-client installation builds the shared package once:

```bash
node scripts/install.mjs --client codex --client opencode --client claude-code
```

The source installer builds a Distribution under `~/.astrolabe/distributions/source` and links
the bundled skill into each client's supported user-level skill directory.
Each client adapter owns only its MCP configuration: Codex uses
`~/.codex/config.toml`, OpenCode uses `~/.config/opencode/opencode.json`, and
Claude Code uses `~/.claude.json`. Installing or uninstalling one client does
not remove another client's configuration or required skill link.

Restart the configured AI clients after installation.

Installation management commands:

```bash
npm run reinstall:codex
npm run check:codex
npm run uninstall:codex

npm run reinstall:opencode
npm run check:opencode
npm run uninstall:opencode

npm run reinstall:claude-code
npm run check:claude-code
npm run uninstall:claude-code
```

## Quick Start

Launch a Debug build that includes a supported Runtime SDK, then discover it:

```bash
astrolabe list-apps --json
```

Use the returned `appId` with inspection commands:

```bash
astrolabe inspect-screen <app-id> --json
astrolabe capture-hierarchy <app-id> --json
astrolabe find-nodes <app-id> --role text --visible-only --limit 20 --json
astrolabe inspect-node <app-id> --oid <oid> --json
astrolabe node-detail <app-id> <oid> --json
astrolabe capture-screenshot <app-id> --output /tmp/screen.png --source auto --json
```

Hierarchy commands return a `snapshotId`. Pass it to subsequent hierarchy,
node, style, and layout commands to keep the workflow bound to the captured
page. Screenshot and visual comparison commands always use the latest screen.

For a Runtime advertising `semanticInspection`, explicitly request semantic facts:

```bash
astrolabe capture-hierarchy <app-id> --include-semantics --window-id <window-id> --json
astrolabe find-nodes <app-id> --snapshot-id <page-snapshot-id> --role text --json
astrolabe inspect-node <app-id> --snapshot-id <page-snapshot-id> --oid <semantic-oid> --json
astrolabe check-style <app-id> --snapshot-id <page-snapshot-id> --oid <semantic-oid> --expect fontSize 28 --json
```

`--window-id` is optional when exactly one eligible ordinary window exists. It
requires `--include-semantics`; neither capture selector can accompany
`--snapshot-id`. Ambiguous or unavailable targets return typed window diagnostics
in `extensions.common.inspectionTargets`, including excluded windows. An unsupported
Runtime fails explicitly. Omitted semantic options preserve render capture.

The existing MCP tools `capture_hierarchy`, `summarize_hierarchy`, `inspect_screen`,
and `find_nodes` accept optional `includeSemantics` and `windowId`. Their CLI
commands accept the corresponding flags. Semantic nodes live in `semanticItems`,
separate from render `displayItems`; they preserve actual runtime types, AX frames,
and source. AX geometry does not establish visibility, opacity, local bounds, or
physical interaction. Unqualified searches include semantic candidates; visible-only
searches require proven render visibility. UI Graph uses `tree.semanticChild` and
only Runtime-witnessed cross-source relations.

Semantic detail requires the saved Host page `snapshotId`. Host retains the original
`runtimeSnapshotId` and `runtimeCapturedAtUnixTime` before assigning its page ID.
Detail misses query that frozen Runtime capture, validate node, snapshot, source,
and original time, and report `detailSource=runtimeSnapshot`. Cached historical
detail can be read while the app is unavailable. Missing, expired, or mismatched
captures fail without recapturing current UI. Native view/layer details retain their
existing live behavior.

On a Runtime advertising `semanticInspection`, an exact bare oid is verified by
a direct node-detail request before any automatic hierarchy capture. Refused or
unknown IDs stop immediately; successful native IDs retain the usual live
inspection flow. IDs therefore must come from an existing capture in the same
Runtime process. Runtimes without that capability retain the prior native flow.
Host never infers semantic identity from an ID prefix or numeric shape.

Inspect `semanticCapture` and `semanticContext` availability/issues rather than
assuming complete visual recovery. Candidate Text fields remain in
`semanticContext.textCandidates`; they never satisfy style assertions. Missing or
ambiguous semantic style returns `verification=unableToVerify`, while an independently
proven canonical field can be checked even when other fields are partial. See the
[approved semantic contract](docs/architecture/2026-10-18-swiftui-semantic-inspection.md).

The installed MCP server exposes the same capabilities to Codex, OpenCode, and
Claude Code. The bundled skill guides app discovery, snapshot reuse, node
selection, runtime checks, screenshots, visual comparison, and temporary
presentation experiments.

## Development

Install dependencies and run the test suites:

```bash
npm ci
npm --prefix mcp-adapter ci
npm test
swift test --parallel
```

Build the Release CLI:

```bash
swift build -c release --product astrolabe
```

Run end-to-end smoke tests with a supported app running:

```bash
npm run test:smoke
npm run test:usb
```

## Repositories

- [astrolabe-protocol](https://github.com/regulusleow/astrolabe-protocol):
  platform-neutral Wire Protocol, Schemas, Fixtures, and Swift/Kotlin DTOs and
  Codecs.
- [astrolabe-runtime-ios](https://github.com/regulusleow/astrolabe-runtime-ios):
  Debug-only UIKit Runtime SDK.
- [astrolabe-runtime-android](https://github.com/regulusleow/astrolabe-runtime-android):
  Debug-only Android View Runtime SDK.

Astrolabe Host consumes the shared protocol directly and does not depend on a
platform Runtime implementation package.

## Roadmap

- Jetpack Compose Runtime inspection.
- Integrations for additional AI coding platforms.

## License

Astrolabe is available under the [Apache License 2.0](LICENSE). Components
derived from third-party projects remain subject to their original licenses;
see [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES) for details.
