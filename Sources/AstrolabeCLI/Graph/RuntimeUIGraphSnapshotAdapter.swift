//
//  RuntimeUIGraphSnapshotAdapter.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/4.
//

import AstrolabeProtocol
import Foundation

struct RuntimeUIGraphSnapshotAdapter {
    func adapt(
        _ snapshot: PageHierarchySnapshot
    ) throws -> RuntimeUIGraphSnapshotInput {
        let hierarchy = snapshot.hierarchy
        guard hierarchy["snapshotId"] as? String == snapshot.identifier,
              let capabilities = hierarchy["runtimeCapabilities"] as? [String]
        else {
            throw RuntimeUIGraphError.invalidSnapshot
        }
        guard capabilities.contains(RuntimeCapability.uiGraphRelations.rawValue) else {
            throw RuntimeUIGraphError.capabilityUnavailable
        }
        guard let rootObjects = hierarchy["displayItems"] as? [[String: Any]],
              let relationObjects = hierarchy["relations"] as? [[String: Any]]
        else {
            throw RuntimeUIGraphError.invalidSnapshot
        }

        do {
            return RuntimeUIGraphSnapshotInput(
                snapshotIdentifier: snapshot.identifier,
                roots: try rootObjects.map(nodeInput),
                canonicalRelations: try relationObjects.map(relation)
            )
        } catch let error as RuntimeUIGraphError {
            throw error
        } catch {
            throw RuntimeUIGraphError.invalidSnapshot
        }
    }

    private func nodeInput(
        from object: [String: Any]
    ) throws -> RuntimeUIGraphNodeInput {
        guard let identifierValue = object["oid"] as? String,
              let className = object["className"] as? String,
              !className.isEmpty,
              let role = object["runtimeRole"] as? String,
              !role.isEmpty,
              let kindValue = object["kind"] as? String,
              let kind = RuntimeUIGraphNodeKind(rawValue: kindValue),
              let childObjects = object["subitems"] as? [[String: Any]]
        else {
            throw RuntimeUIGraphError.invalidSnapshot
        }
        return RuntimeUIGraphNodeInput(
            identifier: try RuntimeOpaqueIdentifier(rawValue: identifierValue),
            className: className,
            role: role,
            kind: kind,
            children: try childObjects.map(nodeInput)
        )
    }

    private func relation(
        from object: [String: Any]
    ) throws -> RuntimeUIGraphRelation {
        let expectedKeys: Set<String> = [
            "type",
            "sourceNodeID",
            "targetNodeID",
            "extensions"
        ]
        guard Set(object.keys) == expectedKeys,
              JSONSerialization.isValidJSONObject(object)
        else {
            throw RuntimeUIGraphError.invalidSnapshot
        }
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        let relation = try JSONDecoder().decode(
            RuntimeNodeRelation.self,
            from: data
        )
        return RuntimeUIGraphRelation(
            type: relation.type,
            sourceNodeID: relation.sourceNodeID,
            targetNodeID: relation.targetNodeID,
            extensions: relation.extensions
        )
    }
}
