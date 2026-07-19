# Astrolabe

Astrolabe is a runtime UI inspection tool for AI coding agents. It combines a
Swift CLI, a local MCP server, and a packaged Codex skill to inspect and verify
running mobile interfaces.

## Features

- Discover supported apps running in iOS simulators or on paired USB devices.
- Inspect UI hierarchies, node frames, visibility, text, styles, semantic roles,
  and detailed runtime attributes.
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
- A supported app with an Astrolabe Runtime SDK enabled in Debug builds

## Installation

Clone the repository and install Astrolabe for Codex:

```bash
git clone https://github.com/regulusleow/astrolabe.git
cd astrolabe
npm run install:codex
```

The installer builds the CLI and MCP adapter, installs the package under
`~/.astrolabe/package`, links the bundled skill into
`~/.agents/skills/astrolabe`, and updates the managed Astrolabe sections in
`~/.codex/config.toml`.

Restart Codex or open a new Codex session after installation.

Installation management commands:

```bash
npm run reinstall:codex
npm run update:codex
npm run check:codex
npm run uninstall:codex
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

The installed MCP server exposes the same capabilities to Codex. The bundled
skill guides app discovery, snapshot reuse, node selection, runtime checks,
screenshots, visual comparison, and temporary presentation experiments.
Codex is currently the only officially supported AI coding platform.

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
  platform-neutral Wire Protocol, Schemas, Fixtures, and Swift DTOs.
- [astrolabe-runtime-ios](https://github.com/regulusleow/astrolabe-runtime-ios):
  Debug-only UIKit Runtime SDK.

Astrolabe Host consumes the shared protocol directly and does not depend on a
platform Runtime implementation package.

## Roadmap

- Android Runtime and Host support.
- Integrations for additional AI coding platforms.

## License

Astrolabe is available under the [Apache License 2.0](LICENSE). Components
derived from third-party projects remain subject to their original licenses;
see [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES) for details.
