//
//  AstrolabeIOSRuntimeProvider.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/11.
//

import AstrolabeCLI
import AstrolabeProtocol
import Foundation

package final class AstrolabeIOSRuntimeProvider:
    RuntimeUIProviderTargeting,
    RuntimeApplicationDiscovering,
    RuntimeUIHierarchyCapturing,
    RuntimeUINodeDetailProviding,
    RuntimeUIPatchCatalogProviding,
    RuntimeUIAttributePatching,
    RuntimeUIAppDiscoveryDiagnosing {
    package let descriptor = RuntimeUIProviderDescriptor(
        identifier: "astrolabe-ios-runtime",
        platform: .ios,
        capabilities: [
            .appDiscovery,
            .hierarchy,
            .nodeDetail,
            .attributePatchDiscovery,
            .attributePatching
        ]
    )

    private let endpointDiscovery: any AstrolabeRuntimeEndpointDiscovering
    private let clientFactory: any AstrolabeRuntimeClientCreating
    private let mapper: AstrolabeRuntimeResponseMapper
    private let compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy
    private let sessionStore: AstrolabeRuntimeSessionStore
    private let diagnosticLock = NSLock()
    private var diagnostics = [RuntimeAppDiscoveryDiagnostic]()

    init(
        endpointDiscovery: any AstrolabeRuntimeEndpointDiscovering =
            CompositeAstrolabeRuntimeEndpointDiscovery(
                discoveries: [
                    SimulatorAstrolabeRuntimeEndpointDiscovery(),
                    USBMuxAstrolabeRuntimeEndpointDiscovery()
                ]
            ),
        clientFactory: any AstrolabeRuntimeClientCreating =
            AstrolabeRuntimeProtocolClientFactory(),
        mapper: AstrolabeRuntimeResponseMapper = AstrolabeRuntimeResponseMapper(),
        compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy =
            AstrolabeRuntimeCompatibilityPolicy()
    ) {
        self.endpointDiscovery = endpointDiscovery
        self.clientFactory = clientFactory
        self.mapper = mapper
        self.compatibilityPolicy = compatibilityPolicy
        sessionStore = AstrolabeRuntimeSessionStore(
            clientFactory: clientFactory,
            compatibilityPolicy: compatibilityPolicy
        )
    }

    package func canHandle(appId: String) -> Bool {
        guard let appID = try? AstrolabeRuntimeAppID(rawValue: appId) else {
            return false
        }
        return appID.connectionKind == "simulator" ||
            appID.connectionKind == "usb"
    }

    package func fetchApps() throws -> [InspectableAppRecord] {
        let endpointSnapshot = endpointDiscovery.discoverEndpoints()
        var discoveredApps = [InspectableAppRecord]()
        var diagnostics = endpointSnapshot.diagnostics
        var resolvedUSBDeviceIds = Set<String>()
        for endpoint in endpointSnapshot.endpoints {
            switch discover(endpoint: endpoint) {
            case let .app(app):
                discoveredApps.append(app)
                if endpoint.connectionKind == "usb" {
                    resolvedUSBDeviceIds.insert(endpoint.deviceId)
                }
            case let .diagnostic(diagnostic):
                diagnostics.append(diagnostic)
                if endpoint.connectionKind == "usb" {
                    resolvedUSBDeviceIds.insert(endpoint.deviceId)
                }
            case .unavailable:
                break
            }
        }
        let unresolvedUSBDeviceIds = Set(
            endpointSnapshot.endpoints
                .filter { $0.connectionKind == "usb" }
                .map(\.deviceId)
        ).subtracting(resolvedUSBDeviceIds)
        diagnostics.append(contentsOf: unresolvedUSBDeviceIds.sorted().map {
            usbRuntimeUnavailableDiagnostic(deviceId: $0)
        })
        diagnosticLock.lock()
        self.diagnostics = diagnostics
        diagnosticLock.unlock()
        return discoveredApps
    }

    package func appDiscoveryDiagnostics() -> [RuntimeAppDiscoveryDiagnostic] {
        diagnosticLock.lock()
        let diagnostics = self.diagnostics
        diagnosticLock.unlock()
        return diagnostics
    }

    package func fetchHierarchy(appId: String) throws -> [String: Any] {
        let appID = try AstrolabeRuntimeAppID(rawValue: appId)
        let session = try sessionStore.session(for: appID)
        return mapper.hierarchy(
            appID: appID,
            handshake: session.handshake,
            appInfo: session.appInfo,
            snapshot: try session.hierarchySnapshot()
        )
    }

    package func fetchNodeDetail(appId: String, oid: String) throws -> [String: Any] {
        let appID = try AstrolabeRuntimeAppID(rawValue: appId)
        let session = try sessionStore.session(for: appID)
        let nodeID = try RuntimeOpaqueIdentifier(rawValue: oid)
        return mapper.nodeDetail(
            appID: appID,
            requestedNodeID: nodeID,
            detail: try session.nodeDetail(nodeID: nodeID)
        )
    }

    package func applyAttributePatch(
        appId: String,
        oid: String,
        attributeIdentifier: String,
        value: RuntimeAttributeValue
    ) throws -> [String: Any] {
        let appID = try AstrolabeRuntimeAppID(rawValue: appId)
        let session = try sessionStore.session(for: appID)
        return mapper.attributePatch(
            appID: appID,
            patch: try session.applyAttributePatch(
                nodeID: try RuntimeOpaqueIdentifier(rawValue: oid),
                attributeIdentifier: try RuntimeAttributeIdentifier(
                    rawValue: attributeIdentifier
                ),
                value: value
            )
        )
    }

    package func fetchPatchableAttributeCatalog(
        appId: String
    ) throws -> RuntimePatchableAttributesPayload {
        let appID = try AstrolabeRuntimeAppID(rawValue: appId)
        return try sessionStore.session(for: appID).patchableAttributes()
    }

    package func fetchAttributePatches(appId: String) throws -> [String: Any] {
        let appID = try AstrolabeRuntimeAppID(rawValue: appId)
        let session = try sessionStore.session(for: appID)
        return mapper.attributePatchList(
            appID: appID,
            list: try session.attributePatches()
        )
    }

    package func revertAttributePatch(appId: String, patchID: String) throws -> [String: Any] {
        let appID = try AstrolabeRuntimeAppID(rawValue: appId)
        let session = try sessionStore.session(for: appID)
        return mapper.attributePatchRevert(
            appID: appID,
            response: try session.revertAttributePatch(patchID: patchID)
        )
    }

    package func clearAttributePatches(appId: String) throws -> [String: Any] {
        let appID = try AstrolabeRuntimeAppID(rawValue: appId)
        let session = try sessionStore.session(for: appID)
        return mapper.attributePatchClear(
            appID: appID,
            response: try session.clearAttributePatches()
        )
    }

    private func discover(
        endpoint: AstrolabeRuntimeEndpoint
    ) -> AstrolabeRuntimeDiscoveryResult {
        do {
            let client = try clientFactory.makeClient(endpoint: endpoint)
            defer { client.close() }
            let handshake = try client.handshake()
            let compatibility = compatibilityPolicy.evaluate(
                handshake: handshake
            )
            let appInfo: RuntimeApplicationInfoPayload?
            if compatibility.isExpectedPlatform,
               compatibility.runtimeCapabilities.contains(.applicationInfo) {
                let value = try client.appInfo()
                guard value.target.identifier == handshake.runtime.instanceID else {
                    return .diagnostic(
                        diagnostic(
                            endpoint: endpoint,
                            error: .invalidResponse(
                                "App information does not match the handshake process identifier"
                            )
                        )
                    )
                }
                appInfo = value
            } else {
                appInfo = nil
            }
            let appID = AstrolabeRuntimeAppID(
                endpoint: endpoint,
                runtimeInstanceIdentifier: handshake.runtime.instanceID.rawValue
            )
            return .app(InspectableAppRecord(
                appId: appID.rawValue,
                platform: descriptor.platform,
                providerIdentifier: descriptor.identifier,
                capabilities: compatibility.supportedProviderCapabilities.sorted {
                    $0.rawValue < $1.rawValue
                },
                displayName: appInfo?.application.displayName ?? "",
                applicationIdentifier: appInfo?.application.identifier ?? "",
                deviceName: appInfo?.environment.deviceName ?? "",
                providerVersion: handshake.runtime.version,
                connectionKind: endpoint.connectionKind,
                deviceId: endpoint.deviceId,
                endpointPort: Int(endpoint.port),
                processIdentifier: appInfo?.target.processIdentifier ?? "",
                compatibility: compatibility.record
            ))
        } catch let error as AstrolabeRuntimeClientError {
            switch error {
            case .connectionFailed, .connectionClosed:
                return .unavailable
            case let .timeout(operation)
                where operation == "Connect to Astrolabe iOS Runtime":
                return .unavailable
            case .timeout, .invalidResponse, .protocolVersionMismatch, .updateRequired, .remote,
                 .invalidAppID, .staleApp:
                return .diagnostic(
                    diagnostic(endpoint: endpoint, error: error)
                )
            }
        } catch {
            return .unavailable
        }
    }

    private func diagnostic(
        endpoint: AstrolabeRuntimeEndpoint,
        error: AstrolabeRuntimeClientError
    ) -> RuntimeAppDiscoveryDiagnostic {
        RuntimeAppDiscoveryDiagnostic(
            providerIdentifier: descriptor.identifier,
            platform: descriptor.platform,
            connectionKind: endpoint.connectionKind,
            deviceId: endpoint.deviceId,
            endpointPort: Int(endpoint.port),
            errorCode: error.code,
            message: error.description,
            recoverySuggestion: error.recoverySuggestion
        )
    }

    private func usbRuntimeUnavailableDiagnostic(
        deviceId: String
    ) -> RuntimeAppDiscoveryDiagnostic {
        RuntimeAppDiscoveryDiagnostic(
            providerIdentifier: descriptor.identifier,
            platform: descriptor.platform,
            connectionKind: "usb",
            deviceId: deviceId,
            endpointPort: 0,
            errorCode: "usb_runtime_unavailable",
            message: "A physical USB device was found, but the Astrolabe Runtime port is unreachable",
            recoverySuggestion: "Ensure the target app is running and has integrated Astrolabe Runtime"
        )
    }
}

private enum AstrolabeRuntimeDiscoveryResult {
    case app(InspectableAppRecord)
    case diagnostic(RuntimeAppDiscoveryDiagnostic)
    case unavailable
}

private final class AstrolabeRuntimeSessionStore {
    private let clientFactory: any AstrolabeRuntimeClientCreating
    private let compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy
    private let lock = NSLock()
    private var sessions = [AstrolabeRuntimeAppID: AstrolabeRuntimeClientSession]()

    init(
        clientFactory: any AstrolabeRuntimeClientCreating,
        compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy
    ) {
        self.clientFactory = clientFactory
        self.compatibilityPolicy = compatibilityPolicy
    }

    deinit {
        lock.lock()
        let sessions = Array(sessions.values)
        self.sessions.removeAll()
        lock.unlock()
        sessions.forEach { $0.close() }
    }

    func session(
        for appID: AstrolabeRuntimeAppID
    ) throws -> AstrolabeRuntimeClientSession {
        lock.lock()
        if let session = sessions[appID] {
            lock.unlock()
            return session
        }
        lock.unlock()

        let newSession = try AstrolabeRuntimeClientSession(
            appID: appID,
            client: try clientFactory.makeClient(endpoint: appID.endpoint),
            compatibilityPolicy: compatibilityPolicy
        )
        lock.lock()
        if let existingSession = sessions[appID] {
            lock.unlock()
            newSession.close()
            return existingSession
        }
        sessions[appID] = newSession
        lock.unlock()
        return newSession
    }
}

private final class AstrolabeRuntimeClientSession {
    /// Runtime information returned after the current connection completes its handshake.
    let handshake: RuntimeHandshakePayload

    /// App and device information associated with the current connection.
    let appInfo: RuntimeApplicationInfoPayload

    private let client: any AstrolabeRuntimeClient
    private let compatibility: AstrolabeRuntimeCompatibility
    private let compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy
    private var didCaptureHierarchy = false

    init(
        appID: AstrolabeRuntimeAppID,
        client: any AstrolabeRuntimeClient,
        compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy
    ) throws {
        self.client = client
        self.compatibilityPolicy = compatibilityPolicy
        do {
            handshake = try client.handshake()
            compatibility = compatibilityPolicy.evaluate(handshake: handshake)
            try compatibilityPolicy.requireRuntimeCapabilities(
                [.applicationInfo],
                compatibility: compatibility
            )
            guard handshake.runtime.instanceID.rawValue == appID.runtimeInstanceIdentifier else {
                throw AstrolabeRuntimeClientError.staleApp(
                    runtimeInstanceIdentifier: handshake.runtime.instanceID.rawValue
                )
            }
            appInfo = try client.appInfo()
            guard appInfo.target.identifier == handshake.runtime.instanceID else {
                throw AstrolabeRuntimeClientError.invalidResponse(
                    "App information does not match the process returned by the handshake"
                )
            }
        } catch {
            client.close()
            throw error
        }
    }

    func hierarchySnapshot() throws -> RuntimeHierarchySnapshotPayload {
        try compatibilityPolicy.require(
            .hierarchy,
            compatibility: compatibility
        )
        let snapshot = try client.hierarchySnapshot()
        didCaptureHierarchy = true
        return snapshot
    }

    func nodeDetail(nodeID: RuntimeOpaqueIdentifier) throws -> RuntimeNodeDetailPayload {
        try compatibilityPolicy.require(
            .nodeDetail,
            compatibility: compatibility
        )
        if !didCaptureHierarchy {
            _ = try hierarchySnapshot()
        }
        return try client.nodeDetail(nodeID: nodeID)
    }

    func applyAttributePatch(
        nodeID: RuntimeOpaqueIdentifier,
        attributeIdentifier: RuntimeAttributeIdentifier,
        value: RuntimeAttributeValue
    ) throws -> RuntimeAttributePatch {
        try compatibilityPolicy.require(
            .attributePatching,
            compatibility: compatibility
        )
        if !didCaptureHierarchy {
            _ = try hierarchySnapshot()
        }
        return try client.applyAttributePatch(
            RuntimeApplyAttributePatchParameters(
                nodeID: nodeID,
                attributeIdentifier: attributeIdentifier,
                value: value
            )
        )
    }

    func patchableAttributes() throws -> RuntimePatchableAttributesPayload {
        try compatibilityPolicy.require(
            .attributePatchDiscovery,
            compatibility: compatibility
        )
        return try client.patchableAttributes()
    }

    func attributePatches() throws -> RuntimeAttributePatchListPayload {
        try compatibilityPolicy.require(
            .attributePatching,
            compatibility: compatibility
        )
        return try client.attributePatches()
    }

    func revertAttributePatch(
        patchID: String
    ) throws -> RuntimeRevertAttributePatchPayload {
        try compatibilityPolicy.require(
            .attributePatching,
            compatibility: compatibility
        )
        return try client.revertAttributePatch(
            RuntimeRevertAttributePatchParameters(
                patchID: try RuntimeOpaqueIdentifier(rawValue: patchID)
            )
        )
    }

    func clearAttributePatches() throws -> RuntimeClearAttributePatchesPayload {
        try compatibilityPolicy.require(
            .attributePatching,
            compatibility: compatibility
        )
        return try client.clearAttributePatches()
    }

    func close() {
        client.close()
    }
}
