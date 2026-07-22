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

    package func hierarchySnapshot() throws -> RuntimeHierarchySnapshotPayload {
        try compatibilityPolicy.require(.hierarchy, compatibility: compatibility)
        let snapshot = try client.hierarchySnapshot()
        didCaptureHierarchy = true
        return snapshot
    }

    package func nodeDetail(
        nodeID: RuntimeOpaqueIdentifier
    ) throws -> RuntimeNodeDetailPayload {
        try compatibilityPolicy.require(.nodeDetail, compatibility: compatibility)
        try captureHierarchyIfNeeded()
        return try client.nodeDetail(nodeID: nodeID)
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
}
