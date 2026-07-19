//
//  HostPlatformModuleRegistryTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeProtocol
import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import AstrolabeCLI

private typealias Fixtures = CLICommandTestFixtures

final class HostPlatformModuleRegistryTests: XCTestCase {
    func testListAppsReturnsAppListOutput() throws {
        let service = Fixtures.FakeInspectorService()
        service.apps = [
            InspectableAppRecord(
                appId: "app-1",
                platform: .ios,
                providerIdentifier: "ios-runtime",
                capabilities: [.appDiscovery, .hierarchy, .nodeDetail],
                displayName: "Demo",
                applicationIdentifier: "com.example.demo",
                deviceName: "iPhone 15",
                providerVersion: "1",
                connectionKind: "simulator",
                deviceId: "simulator",
                endpointPort: 47164,
                processIdentifier: "ios-process",
                compatibility: RuntimeCompatibilityRecord(
                    status: .updateRequired,
                    hostVersion: "0.1.0",
                    runtimeVersion: "0.0.9",
                    negotiatedProtocolVersion: RuntimeProtocolVersionRecord(
                        major: 1,
                        minor: 0
                    ),
                    runtimeCapabilities: ["appInfo", "hierarchySnapshot"],
                    missingRuntimeCapabilities: ["nodeDetail"],
                    recoverySuggestion: "Update the Runtime"
                )
            )
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: ["list-apps"])

        guard case .appList(let result) = output else {
            return XCTFail("list-apps should return appList output")
        }
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.schemaVersion, 4)
        XCTAssertEqual(result.command, "list-apps")
        XCTAssertNil(result.error)
        XCTAssertNil(result.errorCode)
        XCTAssertEqual(result.data?.apps.first?.appId, "app-1")
        XCTAssertEqual(result.data?.apps.first?.platform, .ios)
        XCTAssertEqual(result.data?.apps.first?.providerIdentifier, "ios-runtime")
        XCTAssertEqual(
            result.data?.apps.first?.compatibility?.status,
            .updateRequired
        )
        XCTAssertEqual(
            result.data?.apps.first?.compatibility?.missingRuntimeCapabilities,
            ["nodeDetail"]
        )
        XCTAssertEqual(service.calls, [.fetchApps])
    }

    func testRegistryAggregatesAppsAcrossPlatforms() throws {
        let iosProvider = Fixtures.FakeInspectorService()
        iosProvider.descriptor = RuntimeUIProviderDescriptor(
            identifier: "ios-provider",
            platform: .ios,
            capabilities: [.appDiscovery, .hierarchy]
        )
        iosProvider.apps = [
            InspectableAppRecord(
                appId: "ios:app-1",
                platform: .ios,
                providerIdentifier: "ios-provider",
                capabilities: [.appDiscovery, .hierarchy],
                displayName: "iOS Demo",
                applicationIdentifier: "com.example.ios",
                deviceName: "iPhone",
                providerVersion: "1",
                connectionKind: "simulator",
                deviceId: "ios-device",
                endpointPort: 47164,
                processIdentifier: "ios-process"
            )
        ]
        let androidProvider = Fixtures.FakeInspectorService()
        androidProvider.descriptor = RuntimeUIProviderDescriptor(
            identifier: "android-provider",
            platform: .android,
            capabilities: [.appDiscovery, .hierarchy]
        )
        androidProvider.apps = [
            InspectableAppRecord(
                appId: "android:app-1",
                platform: .android,
                providerIdentifier: "android-provider",
                capabilities: [.appDiscovery, .hierarchy],
                displayName: "Android Demo",
                applicationIdentifier: "com.example.android",
                deviceName: "Pixel",
                providerVersion: "1",
                connectionKind: "adb",
                deviceId: "android-device",
                endpointPort: 27183,
                processIdentifier: "android-process"
            )
        ]

        let apps = try Fixtures.makePlatformRegistry(
            providers: [iosProvider, androidProvider]
        ).fetchApps()

        XCTAssertEqual(apps.map(\.platform), [.ios, .android])
        XCTAssertEqual(apps.map(\.providerIdentifier), ["ios-provider", "android-provider"])
        XCTAssertEqual(iosProvider.calls, [.fetchApps])
        XCTAssertEqual(androidProvider.calls, [.fetchApps])
    }

    func testRegistrySkipsProvidersWithoutAppDiscovery() throws {
        let provider = Fixtures.FakeInspectorService()
        provider.descriptor = RuntimeUIProviderDescriptor(
            identifier: "android-provider",
            platform: .android,
            capabilities: [.hierarchy]
        )

        let apps = try Fixtures.makePlatformRegistry(providers: [provider]).fetchApps()

        XCTAssertTrue(apps.isEmpty)
        XCTAssertTrue(provider.calls.isEmpty)
    }

    func testRegistryRoutesTargetToMatchingProvider() throws {
        let iosProvider = Fixtures.FakeInspectorService()
        iosProvider.handledAppIds = ["ios:app-1"]
        iosProvider.hierarchy = ["provider": "ios"]
        let androidProvider = Fixtures.FakeInspectorService()
        androidProvider.descriptor = RuntimeUIProviderDescriptor(
            identifier: "android-provider",
            platform: .android,
            capabilities: [.appDiscovery, .hierarchy, .nodeDetail]
        )
        androidProvider.handledAppIds = ["android:app-1"]
        androidProvider.hierarchy = ["provider": "android"]
        let registry = try Fixtures.makePlatformRegistry(
            providers: [iosProvider, androidProvider]
        )

        let hierarchy = try registry.fetchHierarchy(appId: "android:app-1")

        XCTAssertEqual(hierarchy["provider"] as? String, "android")
        XCTAssertTrue(iosProvider.calls.isEmpty)
        XCTAssertEqual(androidProvider.calls, [.fetchHierarchy("android:app-1")])
    }

    func testRegistryResolvesTargetPlatform() throws {
        let iosProvider = Fixtures.FakeInspectorService()
        iosProvider.handledAppIds = ["ios:app-1"]
        let androidProvider = Fixtures.FakeInspectorService()
        androidProvider.descriptor = RuntimeUIProviderDescriptor(
            identifier: "android-provider",
            platform: .android,
            capabilities: [.hierarchy]
        )
        androidProvider.handledAppIds = ["android:app-1"]
        let registry = try Fixtures.makePlatformRegistry(
            providers: [iosProvider, androidProvider]
        )

        XCTAssertEqual(try registry.platform(for: "android:app-1"), .android)
    }

    func testRegistryRejectsUnknownTarget() throws {
        let provider = Fixtures.FakeInspectorService()
        provider.handledAppIds = ["ios:known-app"]
        let registry = try Fixtures.makePlatformRegistry(providers: [provider])

        XCTAssertThrowsError(try registry.fetchHierarchy(appId: "unknown:app-1")) { error in
            XCTAssertEqual(CLIError.code(for: error), "target_provider_not_found")
            XCTAssertEqual(
                CLIError.recoverySuggestion(for: error),
                "Run list-apps again and use the current appId"
            )
        }
    }

    func testRegistryRejectsUnsupportedTargetCapability() throws {
        let provider = Fixtures.FakeInspectorService()
        provider.descriptor = RuntimeUIProviderDescriptor(
            identifier: "android-provider",
            platform: .android,
            capabilities: [.hierarchy]
        )
        provider.handledAppIds = ["android:app-1"]
        provider.hierarchy = ["provider": "android"]
        let registry = try Fixtures.makePlatformRegistry(providers: [provider])

        XCTAssertNoThrow(try registry.fetchHierarchy(appId: "android:app-1"))
        XCTAssertThrowsError(try registry.fetchNodeDetail(appId: "android:app-1", oid: "node-42")) { error in
            XCTAssertEqual(CLIError.code(for: error), "target_capability_unsupported")
            XCTAssertEqual(
                CLIError.recoverySuggestion(for: error),
                "Check the capabilities returned by list-apps and select an app that supports the required capability"
            )
            XCTAssertEqual(
                String(describing: error),
                "Runtime UI Provider android-provider does not support nodeDetail: android:app-1"
            )
        }
        XCTAssertEqual(provider.calls, [.fetchHierarchy("android:app-1")])
    }

}
