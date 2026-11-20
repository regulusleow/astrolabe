//
//  AstrolabeMacOSRuntimeProvider.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/11/20.
//

import AstrolabeCLI
import AstrolabeProtocol
import AstrolabeRuntimeHostCore
import Foundation

final class AstrolabeMacOSRuntimeProvider:
    RuntimeUIProviderTargeting,
    RuntimeUIProviderLifecycle,
    RuntimeApplicationDiscovering,
    RuntimeUIAppDiscoveryDiagnosing,
    RuntimeUIHierarchyCapturing,
    RuntimeUINodeDetailProviding
{
    private static let ports: ClosedRange<UInt16> = 47_230...47_239
    private static let packageName = "astrolabe-runtime-ios"
    let descriptor = RuntimeUIProviderDescriptor(
        identifier: "astrolabe-macos-runtime",
        platform: .macos,
        capabilities: [.appDiscovery, .hierarchy, .nodeDetail]
    )

    private let discoveryClient = AstrolabeRuntimeProtocolClientFactory(
        transportFactory: TCPAstrolabeRuntimeTransportFactory(requestTimeout: 1),
        runtimePackageName: packageName
    )
    private let mapper = AstrolabeRuntimeResponseMapper()
    private let compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy
    private let sessionStore: AstrolabeRuntimeSessionStore
    private let diagnosticLock = NSLock()
    private var diagnostics = [RuntimeAppDiscoveryDiagnostic]()

    init() {
        let policy = AstrolabeRuntimeCompatibilityPolicy(descriptor: descriptor, runtimePackageName: Self.packageName)
        compatibilityPolicy = policy
        sessionStore = AstrolabeRuntimeSessionStore(
            clientFactory: AstrolabeRuntimeProtocolClientFactory(
                transportFactory: TCPAstrolabeRuntimeTransportFactory(), runtimePackageName: Self.packageName
            ),
            compatibilityPolicy: policy
        )
    }

    func canHandle(appId: String) -> Bool {
        (try? target(for: appId)) != nil
    }

    func close() {
        sessionStore.close()
    }

    func appDiscoveryDiagnostics() -> [RuntimeAppDiscoveryDiagnostic] {
        diagnosticLock.withLock { diagnostics }
    }

    func fetchApps() throws -> [InspectableAppRecord] {
        var discoveredDiagnostics = [RuntimeAppDiscoveryDiagnostic]()
        var targets = Set<AstrolabeRuntimeSessionTarget>()
        let apps = try Self.ports.compactMap { port -> InspectableAppRecord? in
            let endpoint = endpoint(port: port)
            do {
                let client = try discoveryClient.makeClient(endpoint: endpoint)
                defer { client.close() }
                let handshake = try client.handshake()
                let compatibility = compatibilityPolicy.evaluate(handshake: handshake)
                guard compatibility.isExpectedPlatform,
                      handshake.runtime.identifier.rawValue == "astrolabe.runtime-macos" else { return nil }
                let appInfo = compatibility.runtimeCapabilities.contains(.applicationInfo) ? try client.appInfo() : nil
                if let appInfo, appInfo.target.identifier != handshake.runtime.instanceID {
                    throw AstrolabeRuntimeClientError.invalidResponse("App information does not match the Runtime instance")
                }
                let appID = "macos:\(port):\(handshake.runtime.instanceID.rawValue)"
                targets.insert(try target(for: appID))
                return InspectableAppRecord(
                    appId: appID, platform: descriptor.platform, providerIdentifier: descriptor.identifier,
                    capabilities: compatibility.supportedProviderCapabilities.sorted { $0.rawValue < $1.rawValue },
                    displayName: appInfo?.application.displayName ?? "",
                    applicationIdentifier: appInfo?.application.identifier ?? "",
                    deviceName: appInfo?.environment.deviceName ?? "",
                    providerVersion: handshake.runtime.version, connectionKind: endpoint.connectionKind,
                    deviceId: endpoint.deviceId, endpointPort: Int(port),
                    processIdentifier: appInfo?.target.processIdentifier ?? "", compatibility: compatibility.record
                )
            } catch let error as AstrolabeRuntimeClientError {
                switch error {
                case .connectionFailed, .connectionClosed:
                    return nil
                case let .timeout(operation) where operation == "Connect to Astrolabe Runtime":
                    return nil
                default:
                    discoveredDiagnostics.append(RuntimeAppDiscoveryDiagnostic(
                        providerIdentifier: descriptor.identifier, platform: descriptor.platform,
                        connectionKind: endpoint.connectionKind, deviceId: endpoint.deviceId, endpointPort: Int(port),
                        errorCode: error.code, message: error.description, recoverySuggestion: error.recoverySuggestion
                    ))
                    return nil
                }
            }
        }
        diagnosticLock.withLock { diagnostics = discoveredDiagnostics }
        sessionStore.removeSessions(excluding: targets)
        return apps
    }

    func fetchHierarchy(appId: String) throws -> [String: Any] {
        let session = try sessionStore.session(for: target(for: appId))
        return mapper.hierarchy(appID: appId, handshake: session.handshake, appInfo: session.appInfo,
                                snapshot: try session.hierarchySnapshot())
    }

    func fetchNodeDetail(appId: String, oid: String) throws -> [String: Any] {
        let id = try RuntimeOpaqueIdentifier(rawValue: oid)
        let session = try sessionStore.session(for: target(for: appId))
        return mapper.nodeDetail(appID: appId, requestedNodeID: id, detail: try session.nodeDetail(nodeID: id))
    }

    private func target(for appID: String) throws -> AstrolabeRuntimeSessionTarget {
        let parts = appID.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "macos", let port = UInt16(parts[1]), Self.ports.contains(port),
              UUID(uuidString: String(parts[2])) != nil else {
            throw AstrolabeRuntimeClientError.invalidAppID(appID)
        }
        return AstrolabeRuntimeSessionTarget(appID: appID, runtimeInstanceIdentifier: String(parts[2]),
                                            endpoint: endpoint(port: port))
    }

    private func endpoint(port: UInt16) -> AstrolabeRuntimeEndpoint {
        AstrolabeRuntimeEndpoint(connectionKind: "local", deviceId: "localhost", host: "127.0.0.1", port: port)
    }
}
