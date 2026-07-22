//
//  AstrolabeIOSRuntimeProvider.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/11.
//

import AstrolabeCLI
import AstrolabeProtocol
import AstrolabeRuntimeHostCore
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
            CompositeAstrolabeRuntimeEndpointDiscovery(discoveries: [
                SimulatorAstrolabeRuntimeEndpointDiscovery(),
                USBMuxAstrolabeRuntimeEndpointDiscovery()
            ]),
        clientFactory: any AstrolabeRuntimeClientCreating =
            AstrolabeRuntimeProtocolClientFactory(
                transportFactory: DefaultAstrolabeRuntimeTransportFactory(),
                runtimePackageName: "astrolabe-runtime-ios"
            ),
        mapper: AstrolabeRuntimeResponseMapper = AstrolabeRuntimeResponseMapper(),
        compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy =
            AstrolabeRuntimeCompatibilityPolicy(
                platform: .ios,
                runtimePackageName: "astrolabe-runtime-ios"
            )
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
        return appID.connectionKind == "simulator" || appID.connectionKind == "usb"
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
        let session = try sessionStore.session(for: sessionTarget(for: appID))
        return mapper.hierarchy(
            appID: appID.rawValue,
            handshake: session.handshake,
            appInfo: session.appInfo,
            snapshot: try session.hierarchySnapshot()
        )
    }

    package func fetchNodeDetail(appId: String, oid: String) throws -> [String: Any] {
        let appID = try AstrolabeRuntimeAppID(rawValue: appId)
        let session = try sessionStore.session(for: sessionTarget(for: appID))
        let nodeID = try RuntimeOpaqueIdentifier(rawValue: oid)
        return mapper.nodeDetail(
            appID: appID.rawValue,
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
        let session = try sessionStore.session(for: sessionTarget(for: appID))
        return mapper.attributePatch(
            appID: appID.rawValue,
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
        return try sessionStore.session(for: sessionTarget(for: appID))
            .patchableAttributes()
    }

    package func fetchAttributePatches(appId: String) throws -> [String: Any] {
        let appID = try AstrolabeRuntimeAppID(rawValue: appId)
        let session = try sessionStore.session(for: sessionTarget(for: appID))
        return mapper.attributePatchList(
            appID: appID.rawValue,
            list: try session.attributePatches()
        )
    }

    package func revertAttributePatch(
        appId: String,
        patchID: String
    ) throws -> [String: Any] {
        let appID = try AstrolabeRuntimeAppID(rawValue: appId)
        let session = try sessionStore.session(for: sessionTarget(for: appID))
        return mapper.attributePatchRevert(
            appID: appID.rawValue,
            response: try session.revertAttributePatch(patchID: patchID)
        )
    }

    package func clearAttributePatches(appId: String) throws -> [String: Any] {
        let appID = try AstrolabeRuntimeAppID(rawValue: appId)
        let session = try sessionStore.session(for: sessionTarget(for: appID))
        return mapper.attributePatchClear(
            appID: appID.rawValue,
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
            let compatibility = compatibilityPolicy.evaluate(handshake: handshake)
            let appInfo: RuntimeApplicationInfoPayload?
            if compatibility.isExpectedPlatform,
               compatibility.runtimeCapabilities.contains(.applicationInfo) {
                let value = try client.appInfo()
                guard value.target.identifier == handshake.runtime.instanceID else {
                    return .diagnostic(diagnostic(
                        endpoint: endpoint,
                        error: .invalidResponse(
                            "App information does not match the handshake process identifier"
                        )
                    ))
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
                where operation == "Connect to Astrolabe Runtime":
                return .unavailable
            case .timeout, .invalidResponse, .protocolVersionMismatch,
                 .updateRequired, .remote, .invalidAppID, .staleApp:
                return .diagnostic(diagnostic(endpoint: endpoint, error: error))
            }
        } catch {
            return .unavailable
        }
    }

    private func sessionTarget(
        for appID: AstrolabeRuntimeAppID
    ) -> AstrolabeRuntimeSessionTarget {
        AstrolabeRuntimeSessionTarget(
            appID: appID.rawValue,
            runtimeInstanceIdentifier: appID.runtimeInstanceIdentifier,
            endpoint: appID.endpoint
        )
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
