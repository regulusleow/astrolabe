//
//  AstrolabeAndroidRuntimeProviderTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

@testable import AstrolabeAndroidDeviceSupport
@testable import AstrolabeAndroidHost
@testable import AstrolabeCLI
@testable import AstrolabeRuntimeHostCore
import AstrolabeProtocol
import Foundation
import XCTest

final class AstrolabeAndroidRuntimeProviderTests: XCTestCase {
    func testAppIDRoundTripsWirelessSerialAndOpaqueRuntimeIdentity() throws {
        let value = AndroidRuntimeAppID(
            deviceSerial: "192.0.2.1:5555",
            processIdentifier: 321,
            applicationIdentifier: "com.example.demo:debug",
            runtimeInstanceIdentifier: "runtime/value:42"
        )

        XCTAssertEqual(try AndroidRuntimeAppID(rawValue: value.rawValue), value)
        XCTAssertTrue(value.rawValue.hasPrefix("android:"))
    }

    func testProviderDiscoversAndroidRuntimeThroughADBForward() throws {
        let runner = RecordingADBCommandRunner(results: [
            commandOutput("""
            List of devices attached
            emulator-5554 device product:sdk model:Pixel_9 device:emu transport_id:1
            """),
            commandOutput("0: 2 0 10000 1 01 1 @astrolabe_321\n"),
            commandOutput("47231\n")
        ])
        let clientFactory = QueueRuntimeClientFactory(clients: [
            FakeRuntimeClient(
                handshake: try makeHandshake(),
                appInfo: try makeAppInfo()
            )
        ])
        let provider = AstrolabeAndroidRuntimeProvider(
            adbClient: ADBClient(commandRunner: runner),
            clientFactory: clientFactory
        )

        let apps = try provider.fetchApps()

        let app = try XCTUnwrap(apps.first)
        XCTAssertEqual(apps.count, 1)
        XCTAssertTrue(app.appId.hasPrefix("android:"))
        XCTAssertEqual(app.applicationIdentifier, "com.example.demo")
        XCTAssertEqual(app.connectionKind, "emulator")
        XCTAssertEqual(app.deviceId, "emulator-5554")
        XCTAssertEqual(app.endpointPort, 47_231)
        XCTAssertEqual(runner.invocations, [
            ["devices", "-l"],
            ["-s", "emulator-5554", "shell", "cat", "/proc/net/unix"],
            ["-s", "emulator-5554", "forward", "tcp:0", "localabstract:astrolabe_321"]
        ])
    }

    func testProviderRoutesHierarchyThroughSharedRuntimeSession() throws {
        let runner = RecordingADBCommandRunner(results: [
            commandOutput("""
            List of devices attached
            emulator-5554 device product:sdk model:Pixel_9 device:emu transport_id:1
            """),
            commandOutput("0: 2 0 10000 1 01 1 @astrolabe_321\n"),
            commandOutput("47231\n")
        ])
        let probeClient = FakeRuntimeClient(
            handshake: try makeHandshake(),
            appInfo: try makeAppInfo()
        )
        let sessionClient = FakeRuntimeClient(
            handshake: try makeHandshake(),
            appInfo: try makeAppInfo(),
            hierarchy: try makeHierarchy()
        )
        let provider = AstrolabeAndroidRuntimeProvider(
            adbClient: ADBClient(commandRunner: runner),
            clientFactory: QueueRuntimeClientFactory(clients: [probeClient, sessionClient])
        )
        let appID = try XCTUnwrap(try provider.fetchApps().first?.appId)

        let hierarchy = try provider.fetchHierarchy(appId: appID)

        XCTAssertEqual(hierarchy["appId"] as? String, appID)
        XCTAssertEqual(hierarchy["snapshotId"] as? String, "snapshot-1")
        XCTAssertEqual(sessionClient.calls, ["handshake", "appInfo", "hierarchy"])
    }

    func testProviderReportsADBFailureWithoutBreakingOtherPlatformDiscovery() throws {
        let provider = AstrolabeAndroidRuntimeProvider(
            adbClient: ADBClient(commandRunner: FailingADBCommandRunner()),
            clientFactory: QueueRuntimeClientFactory(clients: [])
        )

        XCTAssertEqual(try provider.fetchApps().count, 0)
        let diagnostic = try XCTUnwrap(provider.appDiscoveryDiagnostics().first)
        XCTAssertEqual(diagnostic.errorCode, "adb_unavailable")
        XCTAssertEqual(diagnostic.platform, .android)
    }

    func testProviderRejectsRuntimeWhoseProcessDoesNotOwnDiscoveredSocket() throws {
        let runner = RecordingADBCommandRunner(results: [
            commandOutput("""
            List of devices attached
            emulator-5554 device product:sdk model:Pixel_9 device:emu transport_id:1
            """),
            commandOutput("0: 2 0 10000 1 01 1 @astrolabe_321\n"),
            commandOutput("47231\n"),
            commandOutput("")
        ])
        let provider = AstrolabeAndroidRuntimeProvider(
            adbClient: ADBClient(commandRunner: runner),
            clientFactory: QueueRuntimeClientFactory(clients: [
                FakeRuntimeClient(
                    handshake: try makeHandshake(),
                    appInfo: try makeAppInfo(processIdentifier: "654")
                )
            ])
        )

        XCTAssertTrue(try provider.fetchApps().isEmpty)
        let diagnostic = try XCTUnwrap(provider.appDiscoveryDiagnostics().first)
        XCTAssertEqual(
            diagnostic.errorCode,
            "astrolabe_runtime_invalid_response"
        )
        XCTAssertEqual(runner.invocations.last, [
            "-s", "emulator-5554", "forward", "--remove", "tcp:47231"
        ])
    }

    func testProviderDiscoversRuntimesAcrossMultipleDevices() throws {
        let runner = RecordingADBCommandRunner(results: [
            commandOutput("""
            List of devices attached
            emulator-5554 device product:sdk model:Pixel_9 device:emu transport_id:1
            568ced7b device product:salami model:CPH2581 device:OP595DL1 transport_id:2
            """),
            commandOutput("0: 2 0 10000 1 01 1 @astrolabe_321\n"),
            commandOutput("47231\n"),
            commandOutput("0: 2 0 10000 1 01 1 @astrolabe_654\n"),
            commandOutput("47232\n")
        ])
        let provider = AstrolabeAndroidRuntimeProvider(
            adbClient: ADBClient(commandRunner: runner),
            clientFactory: QueueRuntimeClientFactory(clients: [
                FakeRuntimeClient(
                    handshake: try makeHandshake(instanceIdentifier: "runtime-emulator"),
                    appInfo: try makeAppInfo(
                        processIdentifier: "321",
                        instanceIdentifier: "runtime-emulator",
                        applicationIdentifier: "com.example.emulator"
                    )
                ),
                FakeRuntimeClient(
                    handshake: try makeHandshake(instanceIdentifier: "runtime-device"),
                    appInfo: try makeAppInfo(
                        processIdentifier: "654",
                        instanceIdentifier: "runtime-device",
                        applicationIdentifier: "com.example.device"
                    )
                )
            ])
        )

        let apps = try provider.fetchApps()

        XCTAssertEqual(apps.map(\.applicationIdentifier), [
            "com.example.emulator",
            "com.example.device"
        ])
        XCTAssertEqual(apps.map(\.deviceId), ["emulator-5554", "568ced7b"])
        XCTAssertEqual(apps.map(\.endpointPort), [47_231, 47_232])
    }

    func testProviderReplacesRestartedRuntimeAndClosesPreviousForward() throws {
        let runner = RecordingADBCommandRunner(results: [
            commandOutput("""
            List of devices attached
            emulator-5554 device product:sdk model:Pixel_9 device:emu transport_id:1
            """),
            commandOutput("0: 2 0 10000 1 01 1 @astrolabe_321\n"),
            commandOutput("47231\n"),
            commandOutput("""
            List of devices attached
            emulator-5554 device product:sdk model:Pixel_9 device:emu transport_id:1
            """),
            commandOutput("0: 2 0 10000 1 01 1 @astrolabe_321\n"),
            commandOutput("47232\n"),
            commandOutput("")
        ])
        let provider = AstrolabeAndroidRuntimeProvider(
            adbClient: ADBClient(commandRunner: runner),
            clientFactory: QueueRuntimeClientFactory(clients: [
                FakeRuntimeClient(
                    handshake: try makeHandshake(instanceIdentifier: "runtime-before"),
                    appInfo: try makeAppInfo(instanceIdentifier: "runtime-before")
                ),
                FakeRuntimeClient(
                    handshake: try makeHandshake(instanceIdentifier: "runtime-after"),
                    appInfo: try makeAppInfo(instanceIdentifier: "runtime-after")
                )
            ])
        )

        let firstAppID = try XCTUnwrap(try provider.fetchApps().first?.appId)
        let secondAppID = try XCTUnwrap(try provider.fetchApps().first?.appId)

        XCTAssertNotEqual(firstAppID, secondAppID)
        XCTAssertTrue(runner.invocations.contains([
            "-s", "emulator-5554", "forward", "--remove", "tcp:47231"
        ]))
    }

    func testProviderRemovesForwardWhenADBDeviceDisconnects() throws {
        let runner = RecordingADBCommandRunner(results: [
            commandOutput("""
            List of devices attached
            emulator-5554 device product:sdk model:Pixel_9 device:emu transport_id:1
            """),
            commandOutput("0: 2 0 10000 1 01 1 @astrolabe_321\n"),
            commandOutput("47231\n"),
            commandOutput("""
            List of devices attached
            emulator-5554 offline transport_id:1
            """),
            commandOutput("")
        ])
        let provider = AstrolabeAndroidRuntimeProvider(
            adbClient: ADBClient(commandRunner: runner),
            clientFactory: QueueRuntimeClientFactory(clients: [
                FakeRuntimeClient(
                    handshake: try makeHandshake(),
                    appInfo: try makeAppInfo()
                )
            ])
        )

        XCTAssertEqual(try provider.fetchApps().count, 1)
        XCTAssertTrue(try provider.fetchApps().isEmpty)

        XCTAssertEqual(provider.appDiscoveryDiagnostics().first?.errorCode, "adb_device_offline")
        XCTAssertTrue(runner.invocations.contains([
            "-s", "emulator-5554", "forward", "--remove", "tcp:47231"
        ]))
    }

    func testProviderDeduplicatesRuntimeSocketEntries() throws {
        let runner = RecordingADBCommandRunner(results: [
            commandOutput("""
            List of devices attached
            emulator-5554 device product:sdk model:Pixel_9 device:emu transport_id:1
            """),
            commandOutput("""
            0: 2 0 10000 1 01 1 @astrolabe_321
            1: 2 0 10000 1 01 1 @astrolabe_321
            """),
            commandOutput("47231\n")
        ])
        let provider = AstrolabeAndroidRuntimeProvider(
            adbClient: ADBClient(commandRunner: runner),
            clientFactory: QueueRuntimeClientFactory(clients: [
                FakeRuntimeClient(
                    handshake: try makeHandshake(),
                    appInfo: try makeAppInfo()
                )
            ])
        )

        XCTAssertEqual(try provider.fetchApps().count, 1)
        XCTAssertEqual(
            runner.invocations.filter { $0.contains("localabstract:astrolabe_321") }.count,
            1
        )
    }

    private func commandOutput(_ value: String) -> ADBCommandResult {
        ADBCommandResult(
            standardOutput: Data(value.utf8),
            standardError: Data(),
            exitCode: 0
        )
    }

    private func makeHandshake(
        instanceIdentifier: String = "runtime-42"
    ) throws -> RuntimeHandshakePayload {
        RuntimeHandshakePayload(
            runtime: RuntimeDescriptor(
                identifier: try RuntimeNamespacedIdentifier(
                    rawValue: "astrolabe.runtime-android"
                ),
                version: "1.0.0",
                instanceID: try RuntimeOpaqueIdentifier(rawValue: instanceIdentifier)
            ),
            platform: "android",
            negotiatedProtocolVersion: .v2,
            capabilities: [
                .applicationInfo,
                .hierarchySnapshot,
                .nodeDetail,
                .attributePatchDiscovery,
                .attributePatching,
                .requestCancellation
            ],
            extensions: nil
        )
    }

    private func makeAppInfo(
        processIdentifier: String = "321",
        instanceIdentifier: String = "runtime-42",
        applicationIdentifier: String = "com.example.demo"
    ) throws -> RuntimeApplicationInfoPayload {
        RuntimeApplicationInfoPayload(
            application: RuntimeApplication(
                identifier: applicationIdentifier,
                displayName: "Demo",
                version: "1.0",
                buildVersion: "1"
            ),
            target: RuntimeTarget(
                identifier: try RuntimeOpaqueIdentifier(rawValue: instanceIdentifier),
                processIdentifier: processIdentifier,
                kind: "application",
                primary: true
            ),
            environment: RuntimeEnvironment(
                platform: "Android",
                operatingSystemVersion: "16",
                deviceCategory: "phone",
                deviceName: "Pixel 9",
                deviceModel: "Pixel_9",
                virtualDevice: true,
                locale: "en_US",
                layoutDirection: .leftToRight,
                display: makeDisplay(),
                extensions: nil
            ),
            extensions: nil
        )
    }

    private func makeHierarchy() throws -> RuntimeHierarchySnapshotPayload {
        RuntimeHierarchySnapshotPayload(
            snapshotID: try RuntimeOpaqueIdentifier(rawValue: "snapshot-1"),
            capturedAtUnixTime: 1,
            targetIdentifier: try RuntimeOpaqueIdentifier(rawValue: "runtime-42"),
            orientation: "portrait",
            display: makeDisplay(),
            viewport: RuntimeCoordinateRect(
                x: 0,
                y: 0,
                width: 440,
                height: 956,
                coordinateSpace: .viewport,
                unit: .logical
            ),
            roots: [],
            extensions: nil
        )
    }

    private func makeDisplay() -> RuntimeDisplayInfo {
        RuntimeDisplayInfo(
            logicalSize: RuntimeMeasuredSize(width: 440, height: 956, unit: .logical),
            pixelSize: RuntimeMeasuredSize(width: 1_080, height: 2_400, unit: .pixel),
            logicalToPixelScale: RuntimeScale(x: 2.5, y: 2.5),
            maximumRefreshRate: 120
        )
    }
}

private final class RecordingADBCommandRunner: ADBCommandRunning {
    private var results: [ADBCommandResult]
    private(set) var invocations = [[String]]()

    init(results: [ADBCommandResult]) {
        self.results = results
    }

    func run(arguments: [String]) throws -> ADBCommandResult {
        invocations.append(arguments)
        guard !results.isEmpty else {
            return ADBCommandResult(
                standardOutput: Data(),
                standardError: Data(),
                exitCode: 0
            )
        }
        return results.removeFirst()
    }
}

private struct FailingADBCommandRunner: ADBCommandRunning {
    func run(arguments: [String]) throws -> ADBCommandResult {
        throw CocoaError(.fileNoSuchFile)
    }
}

private final class QueueRuntimeClientFactory: AstrolabeRuntimeClientCreating {
    private var clients: [FakeRuntimeClient]

    init(clients: [FakeRuntimeClient]) {
        self.clients = clients
    }

    func makeClient(
        endpoint: AstrolabeRuntimeEndpoint
    ) throws -> any AstrolabeRuntimeClient {
        clients.removeFirst()
    }
}

private final class FakeRuntimeClient: AstrolabeRuntimeClient {
    private let handshakeValue: RuntimeHandshakePayload
    private let appInfoValue: RuntimeApplicationInfoPayload
    private let hierarchyValue: RuntimeHierarchySnapshotPayload?
    private(set) var calls = [String]()

    init(
        handshake: RuntimeHandshakePayload,
        appInfo: RuntimeApplicationInfoPayload,
        hierarchy: RuntimeHierarchySnapshotPayload? = nil
    ) {
        handshakeValue = handshake
        appInfoValue = appInfo
        hierarchyValue = hierarchy
    }

    func handshake() throws -> RuntimeHandshakePayload {
        calls.append("handshake")
        return handshakeValue
    }

    func appInfo() throws -> RuntimeApplicationInfoPayload {
        calls.append("appInfo")
        return appInfoValue
    }

    func hierarchySnapshot() throws -> RuntimeHierarchySnapshotPayload {
        calls.append("hierarchy")
        return try XCTUnwrap(hierarchyValue)
    }

    func nodeDetail(nodeID: RuntimeOpaqueIdentifier) throws -> RuntimeNodeDetailPayload {
        throw AstrolabeRuntimeClientError.invalidResponse("Unexpected node detail request")
    }

    func patchableAttributes() throws -> RuntimePatchableAttributesPayload {
        throw AstrolabeRuntimeClientError.invalidResponse("Unexpected patch catalog request")
    }

    func applyAttributePatch(
        _ parameters: RuntimeApplyAttributePatchParameters
    ) throws -> RuntimeAttributePatch {
        throw AstrolabeRuntimeClientError.invalidResponse("Unexpected patch request")
    }

    func attributePatches() throws -> RuntimeAttributePatchListPayload {
        throw AstrolabeRuntimeClientError.invalidResponse("Unexpected patch list request")
    }

    func revertAttributePatch(
        _ parameters: RuntimeRevertAttributePatchParameters
    ) throws -> RuntimeRevertAttributePatchPayload {
        throw AstrolabeRuntimeClientError.invalidResponse("Unexpected patch revert request")
    }

    func clearAttributePatches() throws -> RuntimeClearAttributePatchesPayload {
        throw AstrolabeRuntimeClientError.invalidResponse("Unexpected patch clear request")
    }

    func close() {}
}
