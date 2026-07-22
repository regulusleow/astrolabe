//
//  AstrolabeAndroidRuntimeProvider.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeAndroidDeviceSupport
import AstrolabeCLI
import AstrolabeProtocol
import AstrolabeRuntimeHostCore
import Foundation

package final class AstrolabeAndroidRuntimeProvider:
    RuntimeUIProviderTargeting,
    RuntimeApplicationDiscovering,
    RuntimeUIHierarchyCapturing,
    RuntimeUINodeDetailProviding,
    RuntimeUIPatchCatalogProviding,
    RuntimeUIAttributePatching,
    RuntimeUIAppDiscoveryDiagnosing {
    package let descriptor = RuntimeUIProviderDescriptor(
        identifier: "astrolabe-android-runtime",
        platform: .android,
        capabilities: [
            .appDiscovery,
            .hierarchy,
            .nodeDetail,
            .attributePatchDiscovery,
            .attributePatching
        ]
    )

    private let connectionRegistry: AndroidRuntimeConnectionRegistry
    private let mapper: AstrolabeRuntimeResponseMapper
    private let sessionStore: AstrolabeRuntimeSessionStore
    private let diagnosticLock = NSLock()
    private var diagnostics = [RuntimeAppDiscoveryDiagnostic]()

    package init(
        adbClient: ADBClient = ADBClient(),
        clientFactory: any AstrolabeRuntimeClientCreating =
            AstrolabeRuntimeProtocolClientFactory(
                transportFactory: TCPAstrolabeRuntimeTransportFactory(),
                runtimePackageName: "astrolabe-runtime-android"
            ),
        mapper: AstrolabeRuntimeResponseMapper = AstrolabeRuntimeResponseMapper(),
        compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy =
            AstrolabeRuntimeCompatibilityPolicy(
                platform: .android,
                runtimePackageName: "astrolabe-runtime-android"
            )
    ) {
        connectionRegistry = AndroidRuntimeConnectionRegistry(
            adbClient: adbClient,
            clientFactory: clientFactory,
            compatibilityPolicy: compatibilityPolicy
        )
        self.mapper = mapper
        sessionStore = AstrolabeRuntimeSessionStore(
            clientFactory: clientFactory,
            compatibilityPolicy: compatibilityPolicy
        )
    }

    package func canHandle(appId: String) -> Bool {
        (try? AndroidRuntimeAppID(rawValue: appId)) != nil
    }

    package func fetchApps() throws -> [InspectableAppRecord] {
        let snapshot: AndroidRuntimeDiscoverySnapshot
        do {
            snapshot = try connectionRegistry.refresh()
        } catch {
            diagnosticLock.lock()
            diagnostics = [RuntimeAppDiscoveryDiagnostic(
                providerIdentifier: descriptor.identifier,
                platform: descriptor.platform,
                connectionKind: "adb",
                deviceId: "",
                endpointPort: 0,
                errorCode: "adb_unavailable",
                message: String(describing: error),
                recoverySuggestion: "Install Android platform tools, start the ADB server, and try again"
            )]
            diagnosticLock.unlock()
            return []
        }
        diagnosticLock.lock()
        diagnostics = snapshot.diagnostics
        diagnosticLock.unlock()
        let activeTargets = Set(snapshot.bindings.map(\.sessionTarget))
        sessionStore.removeSessions(excluding: activeTargets)
        return snapshot.bindings.map(appRecord)
    }

    package func appDiscoveryDiagnostics() -> [RuntimeAppDiscoveryDiagnostic] {
        diagnosticLock.lock()
        let diagnostics = self.diagnostics
        diagnosticLock.unlock()
        return diagnostics
    }

    package func fetchHierarchy(appId: String) throws -> [String: Any] {
        let binding = try resolve(appId: appId)
        let session = try sessionStore.session(for: binding.sessionTarget)
        return mapper.hierarchy(
            appID: binding.appID.rawValue,
            handshake: session.handshake,
            appInfo: session.appInfo,
            snapshot: try session.hierarchySnapshot()
        )
    }

    package func fetchNodeDetail(
        appId: String,
        oid: String
    ) throws -> [String: Any] {
        let binding = try resolve(appId: appId)
        let session = try sessionStore.session(for: binding.sessionTarget)
        let nodeID = try RuntimeOpaqueIdentifier(rawValue: oid)
        return mapper.nodeDetail(
            appID: binding.appID.rawValue,
            requestedNodeID: nodeID,
            detail: try session.nodeDetail(nodeID: nodeID)
        )
    }

    package func fetchPatchableAttributeCatalog(
        appId: String
    ) throws -> RuntimePatchableAttributesPayload {
        let binding = try resolve(appId: appId)
        return try sessionStore.session(for: binding.sessionTarget)
            .patchableAttributes()
    }

    package func applyAttributePatch(
        appId: String,
        oid: String,
        attributeIdentifier: String,
        value: RuntimeAttributeValue
    ) throws -> [String: Any] {
        let binding = try resolve(appId: appId)
        let session = try sessionStore.session(for: binding.sessionTarget)
        return mapper.attributePatch(
            appID: binding.appID.rawValue,
            patch: try session.applyAttributePatch(
                nodeID: try RuntimeOpaqueIdentifier(rawValue: oid),
                attributeIdentifier: try RuntimeAttributeIdentifier(
                    rawValue: attributeIdentifier
                ),
                value: value
            )
        )
    }

    package func fetchAttributePatches(appId: String) throws -> [String: Any] {
        let binding = try resolve(appId: appId)
        let session = try sessionStore.session(for: binding.sessionTarget)
        return mapper.attributePatchList(
            appID: binding.appID.rawValue,
            list: try session.attributePatches()
        )
    }

    package func revertAttributePatch(
        appId: String,
        patchID: String
    ) throws -> [String: Any] {
        let binding = try resolve(appId: appId)
        let session = try sessionStore.session(for: binding.sessionTarget)
        return mapper.attributePatchRevert(
            appID: binding.appID.rawValue,
            response: try session.revertAttributePatch(patchID: patchID)
        )
    }

    package func clearAttributePatches(appId: String) throws -> [String: Any] {
        let binding = try resolve(appId: appId)
        let session = try sessionStore.session(for: binding.sessionTarget)
        return mapper.attributePatchClear(
            appID: binding.appID.rawValue,
            response: try session.clearAttributePatches()
        )
    }

    private func resolve(appId: String) throws -> AndroidRuntimeBinding {
        try connectionRegistry.resolve(
            appID: AndroidRuntimeAppID(rawValue: appId)
        )
    }

    private func appRecord(
        _ binding: AndroidRuntimeBinding
    ) -> InspectableAppRecord {
        let appInfo = binding.appInfo
        return InspectableAppRecord(
            appId: binding.appID.rawValue,
            platform: descriptor.platform,
            providerIdentifier: descriptor.identifier,
            capabilities: binding.compatibility.supportedProviderCapabilities.sorted {
                $0.rawValue < $1.rawValue
            },
            displayName: appInfo.application.displayName,
            applicationIdentifier: appInfo.application.identifier,
            deviceName: appInfo.environment.deviceName
                ?? binding.device.model
                ?? binding.device.serial,
            providerVersion: binding.handshake.runtime.version,
            connectionKind: binding.device.connectionKind.rawValue,
            deviceId: binding.device.serial,
            endpointPort: Int(binding.sessionTarget.endpoint.port),
            processIdentifier: appInfo.target.processIdentifier
                ?? String(binding.appID.processIdentifier),
            compatibility: binding.compatibility.record
        )
    }
}
