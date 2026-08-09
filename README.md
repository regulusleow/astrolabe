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
