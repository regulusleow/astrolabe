# Astrolabe（星盘）

English | [简体中文](README.zh-CN.md)

Astrolabe is a runtime UI inspection tool for AI coding agents. It combines a
Swift CLI, a local MCP server, and a packaged agent skill to inspect and verify
running mobile interfaces.

Android View inspection uses
[Astrolabe Runtime for Android](https://github.com/regulusleow/astrolabe-runtime-android).

## Features

- Discover supported apps running in iOS simulators, Android emulators, or on
  USB-connected devices.
- Inspect UIKit, Core Animation, and Android View hierarchies, node frames,
  visibility, text, styles, semantic roles, and detailed runtime attributes.
- Inspect SwiftUI semantic nodes, text styles, linear gradients, image metadata, and
  basic text visibility.
- Capture native-resolution screenshots and compare them with expected images
  or recorded baselines.
- Query nodes and verify style, layout, and node-detail expectations.
- Keep related hierarchy operations bound to a frozen page snapshot.
- Apply allowlisted, in-memory presentation patches in Debug builds and revert
  them without changing source code or persistent application state.
- Expose the same inspection workflow through CLI commands, MCP tools, and the
  bundled `astrolabe` skill.

## Requirements

- An Apple silicon Mac running macOS 13 or later
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

Source builds require Xcode with Swift 5.9 or later. Clone the repository, then
install Astrolabe for the AI clients you use:

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

For Homebrew installations, use the installed CLI to check or remove an AI
client's Astrolabe integration. These examples use Codex; replace `codex` with
`opencode` or `claude-code` as needed:

```bash
astrolabe check --client codex
astrolabe uninstall --client codex
```

For source installations, run these management commands from the cloned repository:

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

Launch a Debug build that includes a supported Runtime SDK and keep it in the
foreground while capturing UI. Discover the app:

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

Hierarchy commands return a `snapshotId`. Reuse it in subsequent queries to use
the same captured hierarchy. SwiftUI semantic details come from the corresponding
frozen capture. Native node details are read from the live Runtime on first lookup
and then cached for that snapshot. Screenshot and visual comparison commands
always use the latest screen.

The installed MCP server exposes the same capabilities to Codex, OpenCode, and
Claude Code. The bundled skill guides read-only UI inspection and comparison
with developer-provided design references.

### SwiftUI

Use an iOS Runtime that supports SwiftUI inspection. Add `--include-semantics`
when capturing, then reuse the returned `snapshotId` to find and inspect SwiftUI nodes:

```bash
astrolabe capture-hierarchy <app-id> --include-semantics --json
astrolabe find-nodes <app-id> --snapshot-id <page-snapshot-id> --role text --json
astrolabe inspect-node <app-id> --snapshot-id <page-snapshot-id> --oid <semantic-oid> --json
astrolabe check-style <app-id> --snapshot-id <page-snapshot-id> --oid <semantic-oid> --expect fontSize 28 --json
```

If multiple eligible windows exist, add `--window-id <window-id>` to the capture
command. SwiftUI node details belong to that snapshot; keep its `snapshotId`
with the node ID for subsequent inspection.

With MCP, set `includeSemantics: true` on `capture_hierarchy`, then pass its
returned `snapshotId` to `find_nodes` and `inspect_node`.

`--visible-only` includes only nodes with confirmed basic visibility. Missing or
ambiguous style information returns `verification=unableToVerify`.

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
  Runtime SDK for UIKit, Core Animation, and SwiftUI inspection in Debug builds.
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
