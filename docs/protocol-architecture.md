# Astrolabe Protocol Architecture

## 1. Decision

The independent `astrolabe-protocol` repository is the single source of truth
for communication between Astrolabe Host, the iOS Runtime, and the Android
Runtime.

This design is implemented. The former `AstrolabeRuntimeProtocol` moved out of
`astrolabe-runtime-ios`, and Host no longer obtains protocol models through the
iOS Runtime. Both `astrolabe` and `astrolabe-runtime-ios` directly pin the
independent `AstrolabeProtocol 2.0.0` Swift package. The Android Runtime pins
the matching `astrolabe-protocol-kotlin 2.0.0` artifact from Maven Central.

After this separation, platform Runtime implementation changes no longer force
Host dependency updates. Host and platform Runtimes update the protocol package
only when the wire contract changes.

## 2. Target Architecture

```mermaid
flowchart TB
    Protocol[astrolabe-protocol<br/>Specification, Schemas, Fixtures, Swift and Kotlin Models]
    Host[astrolabe<br/>CLI, MCP, Host Transport]
    IOS[astrolabe-runtime-ios<br/>UIKit Runtime]
    Android[astrolabe-runtime-android<br/>Android Runtime]
    AppIOS[iOS App]
    AppAndroid[Android App]

    Protocol --> Host
    Protocol --> IOS
    Protocol --> Android
    IOS --> AppIOS
    Android --> AppAndroid
```

Dependencies must remain unidirectional: Host and platform Runtimes depend on
the protocol, while the protocol depends on no platform, transport
implementation, or product-layer code.

## 3. Repository Responsibilities

| Repository | Responsibility | Excludes |
| --- | --- | --- |
| `astrolabe-protocol` | Wire protocol, Swift and Kotlin DTOs, version negotiation, error models, Schemas, and Fixtures | UIKit, Android View, transport listeners, device discovery, CLI, and MCP |
| `astrolabe` | App discovery, iOS and Android Host Providers, Host transport, CLI, MCP, screenshots, and visual inspection | Platform Runtime UI collection implementations |
| `astrolabe-runtime-ios` | iOS lifecycle, Runtime Server, and UIKit/CALayer collection | Host commands and cross-platform protocol definitions |
| `astrolabe-runtime-android` | Android lifecycle, Runtime Server, Android View collection, local-socket transport, and patch execution | Host commands, cross-platform protocol definitions, and Compose inspection |

## 4. Protocol Repository Layout

```text
astrolabe-protocol/
├── Package.swift
├── Sources/
│   └── AstrolabeProtocol/
│       ├── Core/
│       ├── Framing/
│       ├── Inspection/
│       ├── Messaging/
│       ├── Negotiation/
│       └── Patching/
├── Tests/
│   └── AstrolabeProtocolTests/
├── settings.gradle.kts
├── AstrolabeProtocolKotlin/
│   └── src/
│       ├── main/kotlin/
│       └── test/kotlin/
├── PROTOCOL-2.0.md
├── Schemas/
│   ├── v1/
│   └── v2/
└── Fixtures/
    ├── v1/
    └── v2/
```

The Swift product is named `AstrolabeProtocol`, and the Kotlin artifact is
published as `io.github.regulusleow:astrolabe-protocol-kotlin`. The repository
provides:

- Length-prefixed frame codecs.
- Requests, responses, methods, and stable error codes.
- Handshakes, protocol version ranges, and capabilities.
- Application, screen, and device-information DTOs.
- Hierarchy, node, geometry, color, and node-detail DTOs.
- Swift and Kotlin JSON codec rules and cross-language test Fixtures.

The following do not belong in the protocol repository:

- `Network.framework` listeners and connection lifecycles.
- USB, usbmux, or PeerTalk adapters.
- UIKit, CALayer, Android View, or Compose types.
- Node collection, screenshots, visual diffs, CLI, or MCP implementations.

## 5. Cross-Language Contract

Swift types are not the cross-platform protocol. The cross-platform source of
truth consists of three parts:

1. Wire-format specification: frames, field semantics, request ordering, and
   error behavior.
2. `Schemas/v1`: JSON structure, required fields, optional fields, and data
   constraints.
3. `Fixtures/v1`: valid and invalid message samples with expected decoding
   results.

The Swift package and Kotlin artifact implement this contract in their
respective languages. Both bindings run compatibility tests against the same
Schemas and Fixtures in CI. The Android Runtime consumes the published Kotlin
artifact instead of defining a second copy of the protocol models. Default
Swift `Codable` or Kotlin serialization behavior must not become an
undocumented protocol rule.

## 6. Versioning Strategy

The protocol has three independent versions that must not be conflated:

| Version | Example | Purpose |
| --- | --- | --- |
| Package version | `AstrolabeProtocol 2.0.0`, `astrolabe-protocol-kotlin 2.0.0` | SwiftPM and Maven Central dependencies and releases |
| Wire Protocol version | `2.0` | Runtime handshake and compatibility decisions |
| Product version | Host 2.1.0 release snapshot: `astrolabe 2.2.2`, `runtime-ios 2.1.0`, `runtime-android 2.0.1` | Independent Host and platform SDK releases |

The product-version example is a release snapshot, not a lockstep versioning
requirement.

Host and the iOS Runtime use the same explicit semantic-version dependency:

```swift
.package(
    url: "https://github.com/regulusleow/astrolabe-protocol.git",
    exact: "2.0.0"
)
```

The Android Runtime similarly pins
`io.github.regulusleow:astrolabe-protocol-kotlin:2.0.0`. Consumers use exact
versions so products cannot automatically resolve different, unverified
protocol versions.

Compatibility rules:

- Adding optional fields or capabilities preserves the current Wire Protocol
  major version.
- Removing fields, changing field semantics, or changing frame format requires
  a major version increase.
- Unknown optional fields must be ignorable. Unknown capabilities must be
  preserved but never invoked without support.
- Host may use only capabilities explicitly declared by the handshake.

### 6.1 Wire Protocol 2.0

Wire Protocol 2.0 provides the platform-neutral contract used by the initial
open-source package releases:

- The cross-platform Runtime release line uses `AstrolabeProtocol 2.0.0`.
- The Wire Protocol major version advances to `2.0`.
- Shared models use platform-neutral semantics such as application identifier.
- Protocol defines only shared DTOs, value types, extension points, Schemas,
  and Fixtures.
- Platform Runtimes or Host platform modules own UIKit, Auto Layout, View,
  Compose, discovery, port, and transport policies.
- Swift and Kotlin bindings run consistency tests against the same 2.0 Schemas
  and Fixtures.
- Host, iOS Runtime, and Android Runtime use 2.0 without V1 compatibility
  fields in current DTOs.

Protocol 2.0 enabled the Android Runtime without carrying forward V1 models
that contained Apple-specific field semantics.

### 6.2 Host Platform Boundary

Host uses a platform-decoupled boundary above Wire Protocol 2.0:

- Providers are split into five minimal capabilities: app discovery,
  hierarchy, node details, patch catalog, and attribute patching. Use cases
  depend only on the protocols they use.
- `HostPlatformModule` uses a Builder to atomically register Providers,
  screenshots, screen inspection, semantics, masks, and diagnostics, then
  validates capability declarations, implementations, and platform
  dependencies at startup.
- The iOS target owns Auto Layout, UIKit attribute aliases, iOS class-name
  heuristics, and physical-device errors. `AstrolabeCLI` no longer depends on
  iOS implementations.
- Platform strategies provide node-detail semantic mapping, Baseline issue
  classification, and visual-diff explanations. Platform selection uses the
  current command's `appId`, not redundant Runtime DTO fields.
- Source directories map one-to-one to SwiftPM targets. Shared Host tests depend
  only on `AstrolabeCLI`, while a separate target owns iOS integration tests.

Shared Host consumes only normalized Wire DTOs; the current module boundary
does not require platform-specific protocol dependencies.

The Android Runtime and Android Host Provider implement the same Protocol 2.0
contract without a compatibility layer around iOS attribute structures.

## 7. Test Boundaries

| Test | Owning Repository |
| --- | --- |
| Swift and Kotlin DTO round trips, frame codecs, Schema validation, and Fixture conformance | `astrolabe-protocol` |
| Runtime Server routing, lifecycle, and UIKit collection | `astrolabe-runtime-ios` |
| Runtime Server routing, lifecycle, Android View collection, and local-socket transport | `astrolabe-runtime-android` |
| Host client, iOS and Android Providers, transport, and compatibility policies | `astrolabe` |
| End-to-end tests between Host and a real Runtime Server | Dedicated integration suite or Runtime repository |

Standard Host test targets no longer depend on the complete
`AstrolabeRuntime`. TCP integration tests that require a real Runtime Server
belong in the Runtime repository or a dedicated integration suite. Host
validates client behavior through protocol Fixtures and replaceable transports.

## 8. Implementation Status

| Item | Status |
| --- | --- |
| Create the protocol repository and migrate Swift models, codecs, and protocol tests | Complete |
| Preserve the V1 specification, Schemas, and Fixtures as release history | Complete; current machine contracts live under the 2.0 assets |
| Publish `AstrolabeProtocol 2.0.0` for SwiftPM and Maven Central | Complete |
| Make Runtime depend on the independent protocol package and remove its local protocol target | Complete |
| Make Host depend directly on the independent protocol package | Complete |
| Remove the complete `AstrolabeRuntime` product dependency from Host tests | Complete |
| Implement and publish the Android View Runtime | Complete; Compose inspection is not supported |
| Implement the Android Host Provider and ADB-based discovery | Complete |
| Automate Protocol, both Runtime SDKs, and Host validation | Complete |
| Complete iOS USB physical-device end-to-end regression | Complete for both CLI and MCP |
| Design and implement platform-neutral Protocol 2.0 | Complete |
| Complete the Host platform-boundary refactor | Complete |

Coordinated releases proceed in this order: `astrolabe-protocol`, public
Protocol SwiftPM and Maven availability, `astrolabe-runtime-ios`,
`astrolabe-runtime-android`, public Android Runtime Maven availability, then
`astrolabe`. Protocol commits and tags must exist remotely before consumers
reference a new version.

The migration adds no dual-protocol adapter and does not duplicate models to
preserve old interfaces. All four core repositories use the independent
protocol module, preventing two long-lived sources of truth.

## 9. Acceptance Criteria

- `astrolabe/Package.swift` no longer references `astrolabe-runtime-ios`.
- iOS Runtime implementation changes do not modify Host `Package.resolved`.
- Host and iOS Runtime pin the same `AstrolabeProtocol` version, and Android
  Runtime pins the matching `astrolabe-protocol-kotlin` version.
- The Protocol repository imports no UIKit, AppKit, Network, or platform Runtime
  module.
- Swift and Kotlin protocol models pass the same Fixtures.
- Wire Protocol version negotiation explicitly rejects breaking protocol
  changes.
- Existing iOS Simulator, Android emulator, and USB physical-device UI
  inspection capabilities remain unchanged after migration.
