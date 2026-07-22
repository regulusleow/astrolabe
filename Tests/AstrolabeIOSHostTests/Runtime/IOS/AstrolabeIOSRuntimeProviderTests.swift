//
//  AstrolabeIOSRuntimeProviderTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/11.
//

@testable import AstrolabeCLI
@testable import AstrolabeIOSDeviceSupport
@testable import AstrolabeIOSHost
@testable import AstrolabeRuntimeHostCore
import AstrolabeProtocol
import Foundation
import XCTest

final class AstrolabeIOSRuntimeProviderTests: XCTestCase {
    func testProviderRoutesMarkedSimulatorAndUSBAppIDs() {
        let endpoint = makeEndpoint()
        let appID = AstrolabeRuntimeAppID(
            endpoint: endpoint,
            runtimeInstanceIdentifier: "runtime-42"
        )
        let usbAppID = AstrolabeRuntimeAppID(
            endpoint: AstrolabeRuntimeEndpoint(
                connectionKind: "usb",
                deviceId: "2",
                host: "usbmux",
                port: 47_210
            ),
            runtimeInstanceIdentifier: "runtime-42"
        )
        let provider = AstrolabeIOSRuntimeProvider()

        XCTAssertEqual(provider.descriptor.identifier, "astrolabe-ios-runtime")
        XCTAssertEqual(
            provider.descriptor.capabilities,
            [
                .appDiscovery,
                .hierarchy,
                .nodeDetail,
                .attributePatchDiscovery,
                .attributePatching
            ]
        )
        XCTAssertTrue(provider.canHandle(appId: appID.rawValue))
        XCTAssertTrue(provider.canHandle(appId: usbAppID.rawValue))
        XCTAssertFalse(
            provider.canHandle(appId: "simulator:simulator:47164:42")
        )
    }

    func testRuntimeAppIDRoundTripsOpaqueInstanceIdentifier() throws {
        let appID = AstrolabeRuntimeAppID(
            endpoint: makeEndpoint(),
            runtimeInstanceIdentifier: "process:instance/42"
        )

        let decoded = try AstrolabeRuntimeAppID(rawValue: appID.rawValue)

        XCTAssertEqual(decoded.runtimeInstanceIdentifier, "process:instance/42")
        XCTAssertEqual(decoded.rawValue, appID.rawValue)
    }

    func testUSBEndpointDiscoveryBuildsDevicePortCandidates() {
        let discovery = USBMuxAstrolabeRuntimeEndpointDiscovery(
            deviceDiscovery: FakeUSBMuxDeviceDiscovery(
                deviceIdentifiers: ["3", "7"]
            )
        )

        let snapshot = discovery.discoverEndpoints()
        let endpoints = snapshot.endpoints

        XCTAssertEqual(
            endpoints.count,
            AstrolabeIOSRuntimePortDefaults.deviceRange.count * 2
        )
        XCTAssertEqual(endpoints.first?.connectionKind, "usb")
        XCTAssertEqual(endpoints.first?.deviceId, "3")
        XCTAssertEqual(
            endpoints.first?.port,
            AstrolabeIOSRuntimePortDefaults.deviceRange.lowerBound
        )
        XCTAssertEqual(endpoints.last?.deviceId, "7")
        XCTAssertEqual(
            endpoints.last?.port,
            AstrolabeIOSRuntimePortDefaults.deviceRange.upperBound
        )
        XCTAssertTrue(snapshot.diagnostics.isEmpty)
    }

    func testUSBEndpointDiscoveryReportsMissingWiredDevice() throws {
        let discovery = USBMuxAstrolabeRuntimeEndpointDiscovery(
            deviceDiscovery: FakeUSBMuxDeviceDiscovery(deviceIdentifiers: [])
        )

        let snapshot = discovery.discoverEndpoints()

        XCTAssertTrue(snapshot.endpoints.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(snapshot.diagnostics.first).errorCode,
            "usb_device_not_connected"
        )
    }

    func testUSBEndpointDiscoveryReportsTransportFailure() throws {
        let discovery = USBMuxAstrolabeRuntimeEndpointDiscovery(
            deviceDiscovery: FakeUSBMuxDeviceDiscovery(
                error: TestUSBMuxDiscoveryError.failed
            )
        )

        let snapshot = discovery.discoverEndpoints()

        XCTAssertTrue(snapshot.endpoints.isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(snapshot.diagnostics.first).errorCode,
            "usb_device_discovery_failed"
        )
    }

    func testProviderReportsHandshakeFailureAsDiscoveryDiagnostic() throws {
        let endpoint = makeEndpoint()
        let client = FakeAstrolabeRuntimeClient()
        let provider = AstrolabeIOSRuntimeProvider(
            endpointDiscovery: FakeAstrolabeRuntimeEndpointDiscovery(
                values: [endpoint]
            ),
            clientFactory: FakeAstrolabeRuntimeClientFactory(
                clients: [client]
            )
        )

        XCTAssertTrue(try provider.fetchApps().isEmpty)
        let diagnostic = try XCTUnwrap(
            provider.appDiscoveryDiagnostics().first
        )
        XCTAssertEqual(
            diagnostic.errorCode,
            "astrolabe_runtime_invalid_response"
        )
        XCTAssertEqual(diagnostic.connectionKind, "simulator")
        XCTAssertEqual(diagnostic.endpointPort, Int(endpoint.port))
    }

    func testProviderReportsUSBDeviceWhenRuntimePortsAreUnavailable() throws {
        let endpoint = AstrolabeRuntimeEndpoint(
            connectionKind: "usb",
            deviceId: "2",
            host: "usbmux",
            port: 47_210
        )
        let client = FakeAstrolabeRuntimeClient()
        client.handshakeError = .connectionFailed("Connection refused")
        let provider = AstrolabeIOSRuntimeProvider(
            endpointDiscovery: FakeAstrolabeRuntimeEndpointDiscovery(
                values: [endpoint]
            ),
            clientFactory: FakeAstrolabeRuntimeClientFactory(
                clients: [client]
            )
        )

        XCTAssertTrue(try provider.fetchApps().isEmpty)
        let diagnostic = try XCTUnwrap(
            provider.appDiscoveryDiagnostics().first
        )
        XCTAssertEqual(diagnostic.errorCode, "usb_runtime_unavailable")
        XCTAssertEqual(diagnostic.deviceId, "2")
        XCTAssertEqual(diagnostic.endpointPort, 0)
    }

    func testProviderPreservesEndpointDiscoveryDiagnostics() throws {
        let expected = RuntimeAppDiscoveryDiagnostic(
            providerIdentifier: "astrolabe-ios-runtime",
            platform: .ios,
            connectionKind: "usb",
            deviceId: "usbmux",
            endpointPort: 0,
            errorCode: "usb_device_not_connected",
            message: "No USB device found",
            recoverySuggestion: "Connect a physical device"
        )
        let provider = AstrolabeIOSRuntimeProvider(
            endpointDiscovery: FakeAstrolabeRuntimeEndpointDiscovery(
                values: [],
                diagnostics: [expected]
            ),
            clientFactory: FakeAstrolabeRuntimeClientFactory(clients: [])
        )

        XCTAssertTrue(try provider.fetchApps().isEmpty)
        XCTAssertEqual(
            try XCTUnwrap(provider.appDiscoveryDiagnostics().first).errorCode,
            "usb_device_not_connected"
        )
    }

    func testProviderDiscoversRuntimeAndMapsAppRecord() throws {
        let endpoint = makeEndpoint()
        let client = FakeAstrolabeRuntimeClient()
        client.handshakeValue = try makeHandshake()
        client.appInfoValue = try makeAppInfo()
        let factory = FakeAstrolabeRuntimeClientFactory(clients: [client])
        let provider = AstrolabeIOSRuntimeProvider(
            endpointDiscovery: FakeAstrolabeRuntimeEndpointDiscovery(
                values: [endpoint]
            ),
            clientFactory: factory
        )

        let apps = try provider.fetchApps()

        let app = try XCTUnwrap(apps.first)
        XCTAssertEqual(apps.count, 1)
        XCTAssertEqual(app.providerIdentifier, "astrolabe-ios-runtime")
        XCTAssertEqual(app.displayName, "Demo")
        XCTAssertEqual(app.applicationIdentifier, "com.example.demo")
        XCTAssertEqual(app.providerVersion, "0.1.0")
        XCTAssertEqual(app.endpointPort, Int(endpoint.port))
        XCTAssertEqual(app.processIdentifier, "42")
        XCTAssertEqual(app.compatibility?.status, .compatible)
        XCTAssertEqual(
            app.compatibility?.hostVersion,
            AstrolabeHostMetadata.version
        )
        XCTAssertEqual(
            app.compatibility?.negotiatedProtocolVersion.major,
            2
        )
        XCTAssertTrue(
            app.compatibility?.missingRuntimeCapabilities.isEmpty == true
        )
        XCTAssertNil(app.compatibility?.recoverySuggestion)
        XCTAssertTrue(app.appId.hasSuffix(":astrolabe"))
        XCTAssertEqual(client.calls, ["handshake", "appInfo", "close"])
    }

    func testProviderKeepsOlderRuntimeVisibleWithUpdateSuggestion() throws {
        let endpoint = makeEndpoint()
        let client = FakeAstrolabeRuntimeClient()
        client.handshakeValue = try makeHandshake(
            runtimeVersion: "0.0.9",
            capabilities: [.applicationInfo, .hierarchySnapshot]
        )
        client.appInfoValue = try makeAppInfo()
        let provider = AstrolabeIOSRuntimeProvider(
            endpointDiscovery: FakeAstrolabeRuntimeEndpointDiscovery(
                values: [endpoint]
            ),
            clientFactory: FakeAstrolabeRuntimeClientFactory(clients: [client])
        )

        let app = try XCTUnwrap(provider.fetchApps().first)

        XCTAssertEqual(app.providerVersion, "0.0.9")
        XCTAssertEqual(app.capabilities, [.appDiscovery, .hierarchy])
        XCTAssertEqual(app.compatibility?.status, .updateRequired)
        XCTAssertEqual(
            app.compatibility?.missingRuntimeCapabilities,
            ["attributePatchDiscovery", "attributePatching", "nodeDetail"]
        )
        XCTAssertEqual(
            app.compatibility?.runtimeCapabilities,
            ["applicationInfo", "hierarchySnapshot"]
        )
        XCTAssertTrue(
            app.compatibility?.recoverySuggestion?.contains(
                "Update astrolabe-runtime-ios"
            ) == true
        )
        XCTAssertEqual(client.calls, ["handshake", "appInfo", "close"])
    }

    func testProviderAllowsSupportedFeatureAndRejectsMissingFeature() throws {
        let endpoint = makeEndpoint()
        let appID = AstrolabeRuntimeAppID(
            endpoint: endpoint,
            runtimeInstanceIdentifier: "runtime-42"
        )
        let client = FakeAstrolabeRuntimeClient()
        client.handshakeValue = try makeHandshake(
            runtimeVersion: "0.0.9",
            capabilities: [.applicationInfo, .hierarchySnapshot]
        )
        client.appInfoValue = try makeAppInfo()
        client.hierarchyValue = try makeHierarchy()
        let provider = AstrolabeIOSRuntimeProvider(
            endpointDiscovery: FakeAstrolabeRuntimeEndpointDiscovery(values: []),
            clientFactory: FakeAstrolabeRuntimeClientFactory(clients: [client])
        )

        XCTAssertNoThrow(try provider.fetchHierarchy(appId: appID.rawValue))
        XCTAssertThrowsError(
            try provider.fetchNodeDetail(appId: appID.rawValue, oid: "node-1")
        ) { error in
            XCTAssertEqual(
                CLIError.code(for: error),
                "astrolabe_runtime_update_required"
            )
            XCTAssertEqual(
                CLIError.recoverySuggestion(for: error),
                "Astrolabe Runtime 0.0.9 is missing capabilities: nodeDetail. Update astrolabe-runtime-ios, then rebuild and launch the app"
            )
        }
        XCTAssertEqual(
            client.calls,
            ["handshake", "appInfo", "hierarchy"]
        )
    }

    func testProviderReusesSessionForHierarchyAndNodeDetail() throws {
        let endpoint = makeEndpoint()
        let appID = AstrolabeRuntimeAppID(
            endpoint: endpoint,
            runtimeInstanceIdentifier: "runtime-42"
        )
        let client = FakeAstrolabeRuntimeClient()
        client.handshakeValue = try makeHandshake()
        client.appInfoValue = try makeAppInfo()
        client.hierarchyValue = try makeHierarchy()
        client.nodeDetailValue = try makeNodeDetail()
        let factory = FakeAstrolabeRuntimeClientFactory(clients: [client])
        let provider = AstrolabeIOSRuntimeProvider(
            endpointDiscovery: FakeAstrolabeRuntimeEndpointDiscovery(values: []),
            clientFactory: factory
        )

        let hierarchy = try provider.fetchHierarchy(appId: appID.rawValue)
        let detail = try provider.fetchNodeDetail(
            appId: appID.rawValue,
            oid: "node-1"
        )

        let displayItems = try XCTUnwrap(
            hierarchy["displayItems"] as? [[String: Any]]
        )
        let label = try XCTUnwrap(displayItems.first)
        XCTAssertEqual(label["className"] as? String, "UILabel")
        XCTAssertEqual(label["customDisplayTitle"] as? String, "Hello")
        XCTAssertEqual(label["visible"] as? Bool, true)
        XCTAssertEqual(label["onscreen"] as? Bool, true)
        XCTAssertEqual(label["hierarchyVisible"] as? Bool, true)
        XCTAssertEqual(
            label["backgroundColor"] as? [Double],
            [1, 1, 1, 1]
        )
        XCTAssertEqual(
            (label["frame"] as? [String: Any])?["x"] as? Double,
            10
        )
        let groups = try XCTUnwrap(
            detail["attributeGroups"] as? [[String: Any]]
        )
        let sections = try XCTUnwrap(
            groups.first?["sections"] as? [[String: Any]]
        )
        let attributes = try XCTUnwrap(
            sections.first?["attributes"] as? [[String: Any]]
        )
        XCTAssertEqual(attributes.first?["identifier"] as? String, "fontSize")
        XCTAssertEqual(attributes.first?["value"] as? Double, 12)
        XCTAssertEqual(
            attributes.last?["identifier"] as? String,
            "attributedTextRuns"
        )
        let runs = try XCTUnwrap(attributes.last?["value"] as? [[String: Any]])
        XCTAssertEqual(runs.first?["location"] as? Int64, 0)
        XCTAssertEqual(runs.first?["length"] as? Int64, 5)
        XCTAssertEqual(
            (runs.first?["fontSize"] as? [String: Any])?["value"] as? Double,
            12
        )
        XCTAssertEqual(runs.first?["foregroundColor"] as? [Double], [1, 0, 0, 1])
        XCTAssertEqual(factory.createdEndpoints, [endpoint])
        XCTAssertEqual(
            client.calls,
            ["handshake", "appInfo", "hierarchy", "nodeDetail:node-1"]
        )
    }

    func testProviderBootstrapsHierarchyBeforeDirectNodeDetail() throws {
        let endpoint = makeEndpoint()
        let appID = AstrolabeRuntimeAppID(
            endpoint: endpoint,
            runtimeInstanceIdentifier: "runtime-42"
        )
        let client = FakeAstrolabeRuntimeClient()
        client.handshakeValue = try makeHandshake()
        client.appInfoValue = try makeAppInfo()
        client.hierarchyValue = try makeHierarchy()
        client.nodeDetailValue = try makeNodeDetail()
        let provider = AstrolabeIOSRuntimeProvider(
            endpointDiscovery: FakeAstrolabeRuntimeEndpointDiscovery(values: []),
            clientFactory: FakeAstrolabeRuntimeClientFactory(clients: [client])
        )

        _ = try provider.fetchNodeDetail(appId: appID.rawValue, oid: "node-1")

        XCTAssertEqual(
            client.calls,
            ["handshake", "appInfo", "hierarchy", "nodeDetail:node-1"]
        )
    }

    func testProviderBatchDetailsCaptureHierarchyOnlyOnce() throws {
        let endpoint = makeEndpoint()
        let appID = AstrolabeRuntimeAppID(
            endpoint: endpoint,
            runtimeInstanceIdentifier: "runtime-42"
        )
        let client = FakeAstrolabeRuntimeClient()
        client.handshakeValue = try makeHandshake()
        client.appInfoValue = try makeAppInfo()
        client.hierarchyValue = try makeHierarchy()
        client.nodeDetailValue = try makeNodeDetail()
        let provider = AstrolabeIOSRuntimeProvider(
            endpointDiscovery: FakeAstrolabeRuntimeEndpointDiscovery(values: []),
            clientFactory: FakeAstrolabeRuntimeClientFactory(clients: [client])
        )

        let batch = try provider.fetchNodeDetails(
            appId: appID.rawValue,
            oids: ["node-1", "node-2"]
        )

        XCTAssertEqual(batch.detailsByOID.keys.sorted(), ["node-1", "node-2"])
        XCTAssertTrue(batch.failuresByOID.isEmpty)
        XCTAssertEqual(
            client.calls,
            [
                "handshake",
                "appInfo",
                "hierarchy",
                "nodeDetail:node-1",
                "nodeDetail:node-2"
            ]
        )
    }

    func testProviderRoutesAttributePatchLifecycleThroughOneRuntimeSession() throws {
        let endpoint = makeEndpoint()
        let appID = AstrolabeRuntimeAppID(
            endpoint: endpoint,
            runtimeInstanceIdentifier: "runtime-42"
        )
        let patchID = try RuntimeOpaqueIdentifier(rawValue: "patch-1")
        let patch = RuntimeAttributePatch(
            patchID: patchID,
            nodeID: try RuntimeOpaqueIdentifier(rawValue: "node-1"),
            attributeIdentifier: try RuntimeAttributeIdentifier(rawValue: "ui.fontSize"),
            originalValue: .number(14),
            requestedValue: .number(16),
            actualValue: .number(16),
            appliedAtUnixTime: 1
        )
        let client = FakeAstrolabeRuntimeClient()
        client.handshakeValue = try makeHandshake()
        client.appInfoValue = try makeAppInfo()
        client.hierarchyValue = try makeHierarchy()
        client.patchableAttributeCatalogValue = RuntimePatchableAttributesPayload(
            attributes: [
                try RuntimePatchableAttribute(
                    attributePattern: "label.fontSize",
                    valueType: RuntimePatchValueType(rawValue: "number"),
                    targetRoles: ["label"],
                    valueConstraints: nil,
                    extensions: RuntimeExtensionMap()
                )
            ]
        )
        client.attributePatchValue = patch
        client.attributePatchListValue = RuntimeAttributePatchListPayload(patches: [patch])
        client.attributePatchRevertValue = RuntimeRevertAttributePatchPayload(
            revertedPatchID: patchID,
            restoredValue: .number(14),
            remainingPatchCount: 0
        )
        let provider = AstrolabeIOSRuntimeProvider(
            endpointDiscovery: FakeAstrolabeRuntimeEndpointDiscovery(values: []),
            clientFactory: FakeAstrolabeRuntimeClientFactory(clients: [client])
        )

        let catalog = try provider.fetchPatchableAttributeCatalog(
            appId: appID.rawValue
        )
        let apply = try provider.applyAttributePatch(
            appId: appID.rawValue,
            oid: "node-1",
            attributeIdentifier: "label.fontSize",
            value: .number(16)
        )
        let list = try provider.fetchAttributePatches(appId: appID.rawValue)
        let revert = try provider.revertAttributePatch(
            appId: appID.rawValue,
            patchID: patchID.rawValue
        )
        let clear = try provider.clearAttributePatches(appId: appID.rawValue)

        XCTAssertEqual(
            ((apply["patch"] as? [String: Any])?["actualValue"] as? [String: Any])?["value"] as? Double,
            16
        )
        XCTAssertEqual(catalog.attributes.count, 1)
        XCTAssertEqual(list["patchCount"] as? Int, 1)
        XCTAssertEqual(revert["remainingPatchCount"] as? Int, 0)
        XCTAssertEqual(clear["remainingPatchCount"] as? Int, 0)
        XCTAssertEqual(client.calls, [
            "handshake",
            "appInfo",
            "patchableAttributes",
            "hierarchy",
            "applyAttributePatch:node-1:label.fontSize",
            "attributePatches",
            "revertAttributePatch:\(patchID.rawValue)",
            "clearAttributePatches"
        ])
    }

    func testProviderRejectsSessionWhenAppInfoDoesNotMatchHandshake() throws {
        let endpoint = makeEndpoint()
        let appID = AstrolabeRuntimeAppID(
            endpoint: endpoint,
            runtimeInstanceIdentifier: "runtime-42"
        )
        let client = FakeAstrolabeRuntimeClient()
        client.handshakeValue = try makeHandshake()
        client.appInfoValue = try makeAppInfo(runtimeInstanceIdentifier: "runtime-43")
        let provider = AstrolabeIOSRuntimeProvider(
            endpointDiscovery: FakeAstrolabeRuntimeEndpointDiscovery(values: []),
            clientFactory: FakeAstrolabeRuntimeClientFactory(clients: [client])
        )

        XCTAssertThrowsError(
            try provider.fetchHierarchy(appId: appID.rawValue)
        ) { error in
            guard case AstrolabeRuntimeClientError.invalidResponse = error else {
                return XCTFail("Expected an invalid Runtime response error, got \(error)")
            }
        }
        XCTAssertEqual(client.calls, ["handshake", "appInfo", "close"])
    }

    func testProtocolClientUsesFramedTypedRequests() throws {
        let transport = ScriptedAstrolabeRuntimeTransport(
            handshake: try makeHandshake(),
            appInfo: try makeAppInfo()
        )
        let client = AstrolabeRuntimeProtocolClient(
            transport: transport,
            runtimePackageName: "astrolabe-runtime-ios"
        )

        let handshake = try client.handshake()
        let appInfo = try client.appInfo()

        XCTAssertEqual(handshake.runtime.instanceID.rawValue, "runtime-42")
        XCTAssertEqual(appInfo.application.identifier, "com.example.demo")
        XCTAssertEqual(transport.requestMethods, [.handshake, .applicationInfo])
        XCTAssertTrue(transport.didConnect)
    }

    func testProtocolClientReportsMajorVersionMismatchWithRuntimeUpdateRecovery() throws {
        let transport = ScriptedAstrolabeRuntimeTransport(
            handshake: try makeHandshake(),
            appInfo: try makeAppInfo(),
            responseProtocolVersion: RuntimeProtocolVersion(major: 1, minor: 0)
        )
        let client = AstrolabeRuntimeProtocolClient(
            transport: transport,
            runtimePackageName: "astrolabe-runtime-ios"
        )

        XCTAssertThrowsError(try client.handshake()) { error in
            guard case let AstrolabeRuntimeClientError.protocolVersionMismatch(
                host,
                runtime,
                runtimePackageName
            ) = error else {
                return XCTFail("Expected a protocol version mismatch error, got \(error)")
            }
            XCTAssertEqual(host, .v2)
            XCTAssertEqual(runtime, RuntimeProtocolVersion(major: 1, minor: 0))
            XCTAssertEqual(runtimePackageName, "astrolabe-runtime-ios")
            XCTAssertEqual(
                AstrolabeRuntimeClientError.protocolVersionMismatch(
                    host: host,
                    runtime: runtime,
                    runtimePackageName: runtimePackageName
                ).errorRecoverySuggestion,
                "Update astrolabe-runtime-ios, then rebuild and launch the app"
            )
        }
    }

    func testProtocolClientMapsResponseMethodMismatchToStableInvalidResponse() throws {
        let transport = ScriptedAstrolabeRuntimeTransport(
            handshake: try makeHandshake(),
            appInfo: try makeAppInfo(),
            responseMethod: .applicationInfo
        )
        let client = AstrolabeRuntimeProtocolClient(
            transport: transport,
            runtimePackageName: "astrolabe-runtime-ios"
        )

        XCTAssertThrowsError(try client.handshake()) { error in
            guard case let AstrolabeRuntimeClientError.invalidResponse(message) = error else {
                return XCTFail("Expected an invalid response error, got \(error)")
            }
            XCTAssertEqual(message, "Response method does not match the request")
        }
    }

    func testResponseMapperPreservesShadowOffsetSemanticPaths() throws {
        let endpoint = makeEndpoint()
        let appID = AstrolabeRuntimeAppID(
            endpoint: endpoint,
            runtimeInstanceIdentifier: "runtime-42"
        )
        let detail = RuntimeNodeDetailPayload(
            nodeID: try RuntimeOpaqueIdentifier(rawValue: "node-1"),
            sections: [
                RuntimeAttributeSection(
                    category: try RuntimeAttributeCategory(rawValue: "ios.layer"),
                    attributes: [
                        RuntimeAttribute(
                            identifier: try RuntimeAttributeIdentifier(rawValue: "layer.shadowOffsetWidth"),
                            value: .number(3)
                        ),
                        RuntimeAttribute(
                            identifier: try RuntimeAttributeIdentifier(rawValue: "layer.shadowOffsetHeight"),
                            value: .number(-4)
                        )
                    ]
                )
            ],
            extensions: nil
        )

        let mapped = AstrolabeRuntimeResponseMapper().nodeDetail(
            appID: appID.rawValue,
            requestedNodeID: try RuntimeOpaqueIdentifier(rawValue: "node-1"),
            detail: detail
        )
        let groups = try XCTUnwrap(mapped["attributeGroups"] as? [[String: Any]])
        let sections = try XCTUnwrap(groups.first?["sections"] as? [[String: Any]])
        let attributes = try XCTUnwrap(
            sections.first?["attributes"] as? [[String: Any]]
        )

        XCTAssertEqual(
            attributes.compactMap { $0["identifier"] as? String },
            ["shadowOffsetWidth", "shadowOffsetHeight"]
        )
        XCTAssertEqual(
            attributes.compactMap { $0["semanticPath"] as? String },
            ["layer.shadowOffsetWidth", "layer.shadowOffsetHeight"]
        )
    }

    func testCLIErrorMapsAstrolabeRuntimeFailures() {
        let error = AstrolabeRuntimeClientError.staleApp(
            runtimeInstanceIdentifier: "runtime-43"
        )

        XCTAssertEqual(
            CLIError.code(for: error),
            "astrolabe_runtime_stale_app"
        )
        XCTAssertEqual(
            CLIError.recoverySuggestion(for: error),
            "Run list-apps again and use the current appId"
        )
    }

    private func makeEndpoint() -> AstrolabeRuntimeEndpoint {
        AstrolabeRuntimeEndpoint(
            connectionKind: "simulator",
            deviceId: "simulator",
            host: "127.0.0.1",
            port: 47_200
        )
    }

    private func makeHandshake(
        runtimeVersion: String = "0.1.0",
        capabilities: [RuntimeCapability] = [
            .applicationInfo,
            .hierarchySnapshot,
            .nodeDetail,
            .attributePatchDiscovery,
            .attributePatching,
            .requestCancellation
        ]
    ) throws -> RuntimeHandshakePayload {
        RuntimeHandshakePayload(
            runtime: RuntimeDescriptor(
                identifier: try RuntimeNamespacedIdentifier(rawValue: "astrolabe.runtime-ios"),
                version: runtimeVersion,
                instanceID: try RuntimeOpaqueIdentifier(rawValue: "runtime-42")
            ),
            platform: "ios",
            negotiatedProtocolVersion: .v2,
            capabilities: capabilities,
            extensions: nil
        )
    }

    private func makeAppInfo(
        runtimeInstanceIdentifier: String = "runtime-42",
        processIdentifier: String = "42"
    ) throws -> RuntimeApplicationInfoPayload {
        RuntimeApplicationInfoPayload(
            application: RuntimeApplication(
                identifier: "com.example.demo",
                displayName: "Demo",
                version: "1.0",
                buildVersion: "1"
            ),
            target: RuntimeTarget(
                identifier: try RuntimeOpaqueIdentifier(rawValue: runtimeInstanceIdentifier),
                processIdentifier: processIdentifier,
                kind: "application",
                primary: true
            ),
            environment: RuntimeEnvironment(
                platform: "iOS",
                operatingSystemVersion: "26.5",
                deviceCategory: "phone",
                deviceName: "iPhone 17 Pro Max",
                deviceModel: "iPhone18,2",
                virtualDevice: true,
                locale: "zh_CN",
                layoutDirection: .leftToRight,
                display: makeDisplay(),
                extensions: nil
            ),
            extensions: nil
        )
    }

    private func makeDisplay() -> RuntimeDisplayInfo {
        RuntimeDisplayInfo(
            logicalSize: RuntimeMeasuredSize(width: 440, height: 956, unit: .logical),
            pixelSize: RuntimeMeasuredSize(width: 1_320, height: 2_868, unit: .pixel),
            logicalToPixelScale: RuntimeScale(x: 3, y: 3),
            maximumRefreshRate: 120
        )
    }

    private func makeHierarchy() throws -> RuntimeHierarchySnapshotPayload {
        RuntimeHierarchySnapshotPayload(
            snapshotID: try RuntimeOpaqueIdentifier(rawValue: "snapshot-1"),
            capturedAtUnixTime: 1,
            targetIdentifier: try RuntimeOpaqueIdentifier(rawValue: "runtime-42"),
            orientation: "portrait",
            display: makeDisplay(),
            viewport: rect(x: 0, y: 0, width: 440, height: 956, space: .viewport),
            roots: [
                RuntimeNode(
                    nodeID: try RuntimeOpaqueIdentifier(rawValue: "node-1"),
                    parentID: nil,
                    siblingIndex: 0,
                    role: "label",
                    runtimeType: RuntimeType(name: "UILabel", ancestors: ["UIView"]),
                    geometry: RuntimeNodeGeometry(
                        bounds: rect(x: 0, y: 0, width: 100, height: 30, space: .local),
                        frameInParent: rect(x: 10, y: 20, width: 100, height: 30, space: .parent),
                        frameInScreen: rect(x: 10, y: 20, width: 100, height: 30, space: .screen)
                    ),
                    visibility: try RuntimeNodeVisibility(
                        hidden: false,
                        hiddenByAncestor: false,
                        opacity: 1,
                        effectiveOpacity: 1,
                        intersectsViewport: true,
                        fullyClippedByAncestor: false,
                        onscreen: true
                    ),
                    clipsContent: false,
                    backgroundColor: RuntimeColor(
                        colorSpace: "extended-srgb",
                        red: 1.000_000_119,
                        green: 1.000_000_119,
                        blue: 1.000_000_119,
                        alpha: 1.000_000_119
                    ),
                    text: "Hello",
                    accessibility: nil,
                    interaction: RuntimeInteraction(
                        interactive: false,
                        enabled: nil,
                        selected: nil,
                        focused: nil
                    ),
                    availableDetailCategories: [try RuntimeNamespacedIdentifier(rawValue: "ios.label")],
                    extensions: try RuntimeExtensionMap(),
                    children: []
                )
            ],
            extensions: nil
        )
    }

    private func makeNodeDetail() throws -> RuntimeNodeDetailPayload {
        RuntimeNodeDetailPayload(
            nodeID: try RuntimeOpaqueIdentifier(rawValue: "node-1"),
            sections: [
                RuntimeAttributeSection(
                    category: try RuntimeAttributeCategory(rawValue: "ios.label"),
                    attributes: [
                        RuntimeAttribute(
                            identifier: try RuntimeAttributeIdentifier(rawValue: "ui.fontSize"),
                            value: .number(12)
                        ),
                        RuntimeAttribute(
                            identifier: try RuntimeAttributeIdentifier(rawValue: "ui.attributedTextRuns"),
                            value: .textRuns([
                                RuntimeTextRun(
                                    range: RuntimeTextRange(location: 0, length: 5),
                                    text: "Hello",
                                    fontName: ".SFUI-Regular",
                                    fontFamilyName: ".AppleSystemUIFont",
                                    fontSize: RuntimeMeasurement(value: 12, unit: .logical),
                                    color: RuntimeColor(
                                        colorSpace: "srgb",
                                        red: 1,
                                        green: 0,
                                        blue: 0,
                                        alpha: 1
                                    ),
                                    extensions: try RuntimeExtensionMap()
                                )
                            ])
                        )
                    ]
                )
            ],
            extensions: nil
        )
    }

    private func rect(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        space: RuntimeCoordinateSpace
    ) -> RuntimeCoordinateRect {
        RuntimeCoordinateRect(
            x: x,
            y: y,
            width: width,
            height: height,
            coordinateSpace: space,
            unit: .logical
        )
    }
}

private struct FakeAstrolabeRuntimeEndpointDiscovery:
    AstrolabeRuntimeEndpointDiscovering {
    /// Runtime endpoint returned by the test.
    let values: [AstrolabeRuntimeEndpoint]

    /// Endpoint discovery diagnostic returned by the test.
    let diagnostics: [RuntimeAppDiscoveryDiagnostic]

    init(
        values: [AstrolabeRuntimeEndpoint],
        diagnostics: [RuntimeAppDiscoveryDiagnostic] = []
    ) {
        self.values = values
        self.diagnostics = diagnostics
    }

    func discoverEndpoints() -> AstrolabeRuntimeEndpointDiscoverySnapshot {
        AstrolabeRuntimeEndpointDiscoverySnapshot(
            endpoints: values,
            diagnostics: diagnostics
        )
    }
}

private struct FakeUSBMuxDeviceDiscovery: USBMuxDeviceDiscovering {
    /// usbmux device returned by the test.
    let devices: [USBMuxDeviceIdentity]

    /// usbmux discovery error simulated by the test.
    let error: Error?

    init(deviceIdentifiers: [String]) {
        devices = deviceIdentifiers.map { identifier in
            USBMuxDeviceIdentity(
                deviceIdentifier: identifier,
                serialNumber: "UDID-\(identifier)"
            )
        }
        error = nil
    }

    init(error: Error) {
        devices = []
        self.error = error
    }

    func connectedDevices() throws -> [USBMuxDeviceIdentity] {
        if let error {
            throw error
        }
        return devices
    }
}

private enum TestUSBMuxDiscoveryError: Error {
    case failed
}

private final class FakeAstrolabeRuntimeClientFactory:
    AstrolabeRuntimeClientCreating {
    private var clients: [FakeAstrolabeRuntimeClient]
    private(set) var createdEndpoints = [AstrolabeRuntimeEndpoint]()

    init(clients: [FakeAstrolabeRuntimeClient]) {
        self.clients = clients
    }

    func makeClient(
        endpoint: AstrolabeRuntimeEndpoint
    ) -> any AstrolabeRuntimeClient {
        createdEndpoints.append(endpoint)
        return clients.removeFirst()
    }
}

private final class FakeAstrolabeRuntimeClient: AstrolabeRuntimeClient {
    var handshakeError: AstrolabeRuntimeClientError?
    var handshakeValue: RuntimeHandshakePayload?
    var appInfoValue: RuntimeApplicationInfoPayload?
    var hierarchyValue: RuntimeHierarchySnapshotPayload?
    var nodeDetailValue: RuntimeNodeDetailPayload?
    var patchableAttributeCatalogValue = RuntimePatchableAttributesPayload(
        attributes: []
    )
    var attributePatchValue: RuntimeAttributePatch?
    var attributePatchListValue = RuntimeAttributePatchListPayload(patches: [])
    var attributePatchRevertValue: RuntimeRevertAttributePatchPayload?
    var attributePatchClearValue = RuntimeClearAttributePatchesPayload(
        revertedPatchIDs: [],
        remainingPatchCount: 0
    )
    private(set) var calls = [String]()

    func handshake() throws -> RuntimeHandshakePayload {
        calls.append("handshake")
        if let handshakeError {
            throw handshakeError
        }
        guard let handshakeValue else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "Test client has no handshakeValue"
            )
        }
        return handshakeValue
    }

    func appInfo() throws -> RuntimeApplicationInfoPayload {
        calls.append("appInfo")
        guard let appInfoValue else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "Test client has no appInfoValue"
            )
        }
        return appInfoValue
    }

    func hierarchySnapshot() throws -> RuntimeHierarchySnapshotPayload {
        calls.append("hierarchy")
        guard let hierarchyValue else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "Test client has no hierarchyValue"
            )
        }
        return hierarchyValue
    }

    func nodeDetail(nodeID: RuntimeOpaqueIdentifier) throws -> RuntimeNodeDetailPayload {
        calls.append("nodeDetail:\(nodeID.rawValue)")
        guard let nodeDetailValue else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "Test client has no nodeDetailValue"
            )
        }
        return nodeDetailValue
    }

    func applyAttributePatch(
        _ request: RuntimeApplyAttributePatchParameters
    ) throws -> RuntimeAttributePatch {
        calls.append("applyAttributePatch:\(request.nodeID.rawValue):\(request.attributeIdentifier.rawValue)")
        guard let attributePatchValue else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "Test client has no attributePatchValue"
            )
        }
        return attributePatchValue
    }

    func patchableAttributes() throws -> RuntimePatchableAttributesPayload {
        calls.append("patchableAttributes")
        return patchableAttributeCatalogValue
    }

    func attributePatches() throws -> RuntimeAttributePatchListPayload {
        calls.append("attributePatches")
        return attributePatchListValue
    }

    func revertAttributePatch(
        _ request: RuntimeRevertAttributePatchParameters
    ) throws -> RuntimeRevertAttributePatchPayload {
        calls.append("revertAttributePatch:\(request.patchID.rawValue)")
        guard let attributePatchRevertValue else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "Test client has no attributePatchRevertValue"
            )
        }
        return attributePatchRevertValue
    }

    func clearAttributePatches() throws -> RuntimeClearAttributePatchesPayload {
        calls.append("clearAttributePatches")
        return attributePatchClearValue
    }

    func close() {
        calls.append("close")
    }
}

private final class ScriptedAstrolabeRuntimeTransport:
    AstrolabeRuntimeTransport {
    private let handshake: RuntimeHandshakePayload
    private let appInfo: RuntimeApplicationInfoPayload
    private let responseProtocolVersion: RuntimeProtocolVersion?
    private let responseMethod: RuntimeMethod?
    private let messageCodec = RuntimeMessageCodec()
    private let frameCodec = RuntimeFrameCodec()
    private var incomingData = Data()
    private(set) var requestMethods = [RuntimeMethod]()
    private(set) var didConnect = false

    init(
        handshake: RuntimeHandshakePayload,
        appInfo: RuntimeApplicationInfoPayload,
        responseProtocolVersion: RuntimeProtocolVersion? = nil,
        responseMethod: RuntimeMethod? = nil
    ) {
        self.handshake = handshake
        self.appInfo = appInfo
        self.responseProtocolVersion = responseProtocolVersion
        self.responseMethod = responseMethod
    }

    func connect() throws {
        didConnect = true
    }

    func send(_ data: Data) throws {
        let payload = data.dropFirst(MemoryLayout<UInt32>.size)
        let header = try messageCodec.decode(
            RuntimeRequestHeader.self,
            from: Data(payload)
        )
        requestMethods.append(header.method)
        let responsePayload: Data
        if header.method == .handshake {
            responsePayload = try messageCodec.encode(
                RuntimeResponse.success(
                    requestID: header.requestID,
                    method: header.method,
                    payload: handshake
                )
            )
        } else if header.method == .applicationInfo {
            responsePayload = try messageCodec.encode(
                RuntimeResponse.success(
                    requestID: header.requestID,
                    method: header.method,
                    payload: appInfo
                )
            )
        } else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "Test transport received an unsupported method"
            )
        }
        var responseObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: responsePayload) as? [String: Any]
        )
        if let responseProtocolVersion {
            responseObject["protocolVersion"] = [
                "major": responseProtocolVersion.major,
                "minor": responseProtocolVersion.minor
            ]
        }
        if let responseMethod {
            responseObject["method"] = responseMethod.rawValue
        }
        let encodedResponse = try JSONSerialization.data(withJSONObject: responseObject)
        incomingData.append(try frameCodec.encode(payload: encodedResponse))
    }

    func receive(byteCount: Int) throws -> Data {
        guard incomingData.count >= byteCount else {
            throw AstrolabeRuntimeClientError.connectionClosed
        }
        let result = incomingData.prefix(byteCount)
        incomingData.removeFirst(byteCount)
        return Data(result)
    }

    func close() {
        didConnect = false
    }
}
