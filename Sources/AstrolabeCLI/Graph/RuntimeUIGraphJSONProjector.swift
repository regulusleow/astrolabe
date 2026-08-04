//
//  RuntimeUIGraphJSONProjector.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/4.
//

import AstrolabeProtocol
import Foundation

enum RuntimeUIGraphProjectionError: Error, Equatable {
    case invalidByteLimit
    case minimumPayloadExceedsByteLimit
}

struct RuntimeUIGraphJSONProjector {
    private let valueMapper = RuntimeAttributeValueOutputMapper()

    func project(
        query: RuntimeUIGraphQuery,
        result: RuntimeUIGraphQueryResult,
        appID: String,
        snapshotID: String,
        capturedAtUnixTime: Double,
        hierarchySource: PageHierarchySource,
        byteLimit: Int
    ) throws -> [String: Any] {
        guard RuntimeUIGraphProjectionLimits.byteCountRange.contains(byteLimit) else {
            throw RuntimeUIGraphProjectionError.invalidByteLimit
        }

        var nodes = result.nodes
        var relations = result.relations
        var reasons = result.truncationReasons.map(\.rawValue)
        var frontierOIDs = uniqueRawIdentifiers(result.frontierNodeIDs)
        var omittedFrontierCount = 0

        func currentProjection() -> [String: Any] {
            makeProjection(
                query: query,
                appID: appID,
                snapshotID: snapshotID,
                capturedAtUnixTime: capturedAtUnixTime,
                hierarchySource: hierarchySource,
                byteLimit: byteLimit,
                nodes: nodes,
                relations: relations,
                reasons: reasons,
                frontierOIDs: frontierOIDs,
                omittedFrontierCount: omittedFrontierCount
            )
        }

        var projection = currentProjection()

        func trimFrontierToFit() throws {
            while try byteCount(of: projection) > byteLimit,
                  !frontierOIDs.isEmpty {
                frontierOIDs.removeLast()
                omittedFrontierCount += 1
                projection = currentProjection()
            }
        }

        guard try byteCount(of: projection) > byteLimit else {
            return projection
        }

        appendUnique("byteLimit", to: &reasons)
        projection = currentProjection()
        try trimFrontierToFit()

        while try byteCount(of: projection) > byteLimit,
              nodes.count > 1 {
            let removedNode = nodes.removeLast()
            let retainedNodeIDs = Set(nodes.map(\.identifier.rawValue))
            relations.removeAll {
                !retainedNodeIDs.contains($0.sourceNodeID.rawValue)
                    || !retainedNodeIDs.contains($0.targetNodeID.rawValue)
            }
            frontierOIDs.append(removedNode.identifier.rawValue)
            projection = currentProjection()
            try trimFrontierToFit()
        }

        while try byteCount(of: projection) > byteLimit,
              !relations.isEmpty {
            relations.removeLast()
            projection = currentProjection()
        }

        guard try byteCount(of: projection) <= byteLimit else {
            throw RuntimeUIGraphProjectionError.minimumPayloadExceedsByteLimit
        }
        return projection
    }

    private func makeProjection(
        query: RuntimeUIGraphQuery,
        appID: String,
        snapshotID: String,
        capturedAtUnixTime: Double,
        hierarchySource: PageHierarchySource,
        byteLimit: Int,
        nodes: [RuntimeUIGraphNode],
        relations: [RuntimeUIGraphRelation],
        reasons: [String],
        frontierOIDs: [String],
        omittedFrontierCount: Int
    ) -> [String: Any] {
        [
            "appId": appID,
            "snapshotId": snapshotID,
            "capturedAtUnixTime": capturedAtUnixTime,
            "hierarchySource": hierarchySource.rawValue,
            "rootOid": query.rootNodeID.rawValue,
            "relationTypes": query.relationTypes.map(\.rawValue).sorted(),
            "direction": query.direction.rawValue,
            "maxDepth": query.maximumDepth,
            "limits": [
                "nodeCount": query.nodeLimit,
                "relationCount": query.relationLimit,
                "byteCount": byteLimit
            ],
            "nodes": nodes.map(nodeDictionary),
            "relations": relations.map(relationDictionary),
            "truncated": !reasons.isEmpty,
            "truncationReasons": reasons,
            "frontierOids": frontierOIDs,
            "omittedFrontierCount": omittedFrontierCount
        ]
    }

    private func nodeDictionary(
        _ node: RuntimeUIGraphNode
    ) -> [String: Any] {
        [
            "oid": node.identifier.rawValue,
            "className": node.className,
            "runtimeRole": node.role,
            "kind": node.kind.rawValue
        ]
    }

    private func relationDictionary(
        _ relation: RuntimeUIGraphRelation
    ) -> [String: Any] {
        [
            "type": relation.type.rawValue,
            "sourceNodeID": relation.sourceNodeID.rawValue,
            "targetNodeID": relation.targetNodeID.rawValue,
            "extensions": relation.extensions.values.mapValues(
                valueMapper.jsonValue
            )
        ]
    }

    private func byteCount(
        of object: [String: Any]
    ) throws -> Int {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw CLIError.invalidJSONObject
        }
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        ).count
    }

    private func uniqueRawIdentifiers(
        _ identifiers: [RuntimeOpaqueIdentifier]
    ) -> [String] {
        var seen = Set<String>()
        return identifiers
            .map(\.rawValue)
            .filter { seen.insert($0).inserted }
    }

    private func appendUnique(
        _ reason: String,
        to reasons: inout [String]
    ) {
        guard !reasons.contains(reason) else {
            return
        }
        reasons.append(reason)
    }
}
