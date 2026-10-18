//
//  AstrolabeRuntimeSessionStore.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeCLI
import AstrolabeProtocol
import Foundation

package final class AstrolabeRuntimeSessionStore {
    private let clientFactory: any AstrolabeRuntimeClientCreating
    private let compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy
    private let lock = NSLock()
    private var sessions = [AstrolabeRuntimeSessionTarget: AstrolabeRuntimeClientSession]()

    package init(
        clientFactory: any AstrolabeRuntimeClientCreating,
        compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy
    ) {
        self.clientFactory = clientFactory
        self.compatibilityPolicy = compatibilityPolicy
    }

    deinit {
        close()
    }

    package func close() {
        lock.lock()
        let sessions = Array(sessions.values)
        self.sessions.removeAll()
        lock.unlock()
        sessions.forEach { $0.close() }
    }

    package func session(
        for target: AstrolabeRuntimeSessionTarget
    ) throws -> AstrolabeRuntimeClientSession {
        lock.lock()
        if let session = sessions[target] {
            lock.unlock()
            return session
        }
        lock.unlock()

        let newSession = try AstrolabeRuntimeClientSession(
            target: target,
            client: try clientFactory.makeClient(endpoint: target.endpoint),
            compatibilityPolicy: compatibilityPolicy
        )
        lock.lock()
        if let existingSession = sessions[target] {
            lock.unlock()
            newSession.close()
            return existingSession
        }
        sessions[target] = newSession
        lock.unlock()
        return newSession
    }

    package func removeSessions(
        excluding targets: Set<AstrolabeRuntimeSessionTarget>
    ) {
        lock.lock()
        let removedTargets = sessions.keys.filter { !targets.contains($0) }
        let removedSessions = removedTargets.compactMap { sessions.removeValue(forKey: $0) }
        lock.unlock()
        removedSessions.forEach { $0.close() }
    }
}

package final class AstrolabeRuntimeClientSession {
    /// Runtime information returned by the handshake.
    package let handshake: RuntimeHandshakePayload

    /// App and device information associated with the Runtime process.
    package let appInfo: RuntimeApplicationInfoPayload

    private let client: any AstrolabeRuntimeClient
    private let compatibility: AstrolabeRuntimeCompatibility
    private let compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy
    private var didCaptureHierarchy = false

    init(
        target: AstrolabeRuntimeSessionTarget,
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
            guard handshake.runtime.instanceID.rawValue == target.runtimeInstanceIdentifier else {
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

    package func hierarchySnapshot(semanticCapture: RuntimeSemanticCaptureOptions? = nil) throws -> RuntimeHierarchySnapshotPayload {
        try compatibilityPolicy.require(.hierarchy, compatibility: compatibility)
        if semanticCapture != nil { try requireSemanticInspection() }
        let snapshot = try client.hierarchySnapshot(semanticCapture: semanticCapture)
        guard semanticCapture == nil || snapshot.semanticCapture != nil else {
            throw AstrolabeRuntimeClientError.invalidResponse("Semantic capture response is missing semanticCapture")
        }
        if let requestedWindow = semanticCapture?.windowID,
           snapshot.semanticCapture?.windowID != requestedWindow {
            throw AstrolabeRuntimeClientError.invalidResponse("Semantic capture response changed the requested window")
        }
        didCaptureHierarchy = true
        return snapshot
    }

    package func nodeDetail(
        nodeID: RuntimeOpaqueIdentifier,
        snapshotID: RuntimeOpaqueIdentifier? = nil
    ) throws -> RuntimeNodeDetailPayload {
        try compatibilityPolicy.require(.nodeDetail, compatibility: compatibility)
        if snapshotID != nil {
            try requireSemanticInspection()
        } else if !compatibility.runtimeCapabilities.contains(.semanticInspection) {
            try captureHierarchyIfNeeded()
        }
        let detail = try client.nodeDetail(nodeID: nodeID, snapshotID: snapshotID)
        guard snapshotID != nil || detail.semanticContext == nil else {
            throw AstrolabeRuntimeClientError.invalidResponse("Semantic detail requires a saved page snapshot context")
        }
        return detail
    }

    package func preflightNativeNode(nodeID: RuntimeOpaqueIdentifier) throws {
        guard compatibility.runtimeCapabilities.contains(.semanticInspection) else { return }
        _ = try nodeDetail(nodeID: nodeID)
    }

    package func applyAttributePatch(
        nodeID: RuntimeOpaqueIdentifier,
        attributeIdentifier: RuntimeAttributeIdentifier,
        value: RuntimeAttributeValue
    ) throws -> RuntimeAttributePatch {
        try compatibilityPolicy.require(
            .attributePatching,
            compatibility: compatibility
        )
        try captureHierarchyIfNeeded()
        return try client.applyAttributePatch(RuntimeApplyAttributePatchParameters(
            nodeID: nodeID,
            attributeIdentifier: attributeIdentifier,
            value: value
        ))
    }

    package func patchableAttributes() throws -> RuntimePatchableAttributesPayload {
        try compatibilityPolicy.require(
            .attributePatchDiscovery,
            compatibility: compatibility
        )
        return try client.patchableAttributes()
    }

    package func attributePatches() throws -> RuntimeAttributePatchListPayload {
        try compatibilityPolicy.require(
            .attributePatching,
            compatibility: compatibility
        )
        return try client.attributePatches()
    }

    package func revertAttributePatch(
        patchID: String
    ) throws -> RuntimeRevertAttributePatchPayload {
        try compatibilityPolicy.require(
            .attributePatching,
            compatibility: compatibility
        )
        return try client.revertAttributePatch(RuntimeRevertAttributePatchParameters(
            patchID: try RuntimeOpaqueIdentifier(rawValue: patchID)
        ))
    }

    package func clearAttributePatches() throws -> RuntimeClearAttributePatchesPayload {
        try compatibilityPolicy.require(
            .attributePatching,
            compatibility: compatibility
        )
        return try client.clearAttributePatches()
    }

    package func close() {
        client.close()
    }

    private func captureHierarchyIfNeeded() throws {
        if !didCaptureHierarchy {
            _ = try hierarchySnapshot()
        }
    }

    private func requireSemanticInspection() throws {
        guard compatibility.runtimeCapabilities.contains(.semanticInspection) else {
            throw AstrolabeRuntimeClientError.remote(RuntimeError(code: .capabilityUnavailable, message: "Runtime does not advertise semanticInspection", recoverySuggestion: "Update the target Runtime"))
        }
    }
}
