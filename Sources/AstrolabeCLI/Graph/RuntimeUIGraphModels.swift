//
//  RuntimeUIGraphModels.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/4.
//

import AstrolabeProtocol

enum RuntimeUIGraphNodeKind: String, Equatable {
    case view
    case layer
}

struct RuntimeUIGraphNodeInput: Equatable {
    /// Runtime node identifier scoped to the captured process.
    let identifier: RuntimeOpaqueIdentifier

    /// Runtime class name retained for later semantic projection.
    let className: String

    /// Open Runtime semantic role.
    let role: String

    /// Host-normalized tree kind used only to derive tree edge types.
    let kind: RuntimeUIGraphNodeKind

    /// Ordered child nodes from the authoritative Runtime tree.
    let children: [RuntimeUIGraphNodeInput]
}

struct RuntimeUIGraphNode: Equatable {
    /// Runtime node identifier scoped to the captured process.
    let identifier: RuntimeOpaqueIdentifier

    /// Runtime class name retained for later semantic projection.
    let className: String

    /// Open Runtime semantic role.
    let role: String

    /// Host-normalized tree kind used only to derive tree edge types.
    let kind: RuntimeUIGraphNodeKind
}

struct RuntimeUIGraphRelation: Equatable {
    /// Open namespaced relation identifier.
    let type: RuntimeNamespacedIdentifier

    /// Source node identifier in the same page snapshot.
    let sourceNodeID: RuntimeOpaqueIdentifier

    /// Target node identifier in the same page snapshot.
    let targetNodeID: RuntimeOpaqueIdentifier

    /// Namespaced producer-specific relation facts.
    let extensions: RuntimeExtensionMap

    var identity: RuntimeUIGraphRelationIdentity {
        RuntimeUIGraphRelationIdentity(
            type: type.rawValue,
            sourceNodeID: sourceNodeID.rawValue,
            targetNodeID: targetNodeID.rawValue
        )
    }

    static func precedes(
        _ lhs: RuntimeUIGraphRelation,
        _ rhs: RuntimeUIGraphRelation
    ) -> Bool {
        let lhsKey = (
            lhs.type.rawValue,
            lhs.sourceNodeID.rawValue,
            lhs.targetNodeID.rawValue
        )
        let rhsKey = (
            rhs.type.rawValue,
            rhs.sourceNodeID.rawValue,
            rhs.targetNodeID.rawValue
        )
        if lhsKey.0 != rhsKey.0 {
            return lhsKey.0 < rhsKey.0
        }
        if lhsKey.1 != rhsKey.1 {
            return lhsKey.1 < rhsKey.1
        }
        return lhsKey.2 < rhsKey.2
    }
}

struct RuntimeUIGraphRelationIdentity: Hashable {
    /// Raw open relation identifier.
    let type: String

    /// Raw source node identifier.
    let sourceNodeID: String

    /// Raw target node identifier.
    let targetNodeID: String
}

struct RuntimeUIGraphSnapshotInput: Equatable {
    /// Host page snapshot identifier that owns this graph input.
    let snapshotIdentifier: String

    /// Ordered roots from the authoritative Runtime trees.
    let roots: [RuntimeUIGraphNodeInput]

    /// Canonical directed relations supplied by the Runtime.
    let canonicalRelations: [RuntimeUIGraphRelation]
}

struct RuntimeUIGraphIndex {
    /// Host page snapshot identifier that owns this graph index.
    let snapshotIdentifier: String

    /// Nodes in stable Runtime preorder.
    let orderedNodes: [RuntimeUIGraphNode]

    /// Canonical and derived relations in stable order.
    let relations: [RuntimeUIGraphRelation]

    /// Nodes keyed by raw Runtime identifier.
    private let nodesByIdentifier: [String: RuntimeUIGraphNode]

    /// Outgoing adjacency keyed by raw source identifier.
    private let outgoingRelationsByNodeID: [String: [RuntimeUIGraphRelation]]

    /// Incoming adjacency keyed by raw target identifier.
    private let incomingRelationsByNodeID: [String: [RuntimeUIGraphRelation]]

    init(
        snapshotIdentifier: String,
        orderedNodes: [RuntimeUIGraphNode],
        relations: [RuntimeUIGraphRelation],
        nodesByIdentifier: [String: RuntimeUIGraphNode],
        outgoingRelationsByNodeID: [String: [RuntimeUIGraphRelation]],
        incomingRelationsByNodeID: [String: [RuntimeUIGraphRelation]]
    ) {
        self.snapshotIdentifier = snapshotIdentifier
        self.orderedNodes = orderedNodes
        self.relations = relations
        self.nodesByIdentifier = nodesByIdentifier
        self.outgoingRelationsByNodeID = outgoingRelationsByNodeID
        self.incomingRelationsByNodeID = incomingRelationsByNodeID
    }

    func node(
        identifiedBy identifier: RuntimeOpaqueIdentifier
    ) -> RuntimeUIGraphNode? {
        nodesByIdentifier[identifier.rawValue]
    }

    func outgoingRelations(
        from identifier: RuntimeOpaqueIdentifier
    ) -> [RuntimeUIGraphRelation] {
        outgoingRelationsByNodeID[identifier.rawValue] ?? []
    }

    func incomingRelations(
        to identifier: RuntimeOpaqueIdentifier
    ) -> [RuntimeUIGraphRelation] {
        incomingRelationsByNodeID[identifier.rawValue] ?? []
    }
}

enum RuntimeUIGraphError: Error, Equatable {
    case capabilityUnavailable
    case invalidSnapshot
    case duplicateNodeIdentifier(String)
    case danglingRelation(sourceNodeID: String, targetNodeID: String)
    case duplicateRelation(type: String, sourceNodeID: String, targetNodeID: String)
    case nodeNotFound(String)
    case invalidQuery
}

enum RuntimeUIGraphBuiltInRelation {
    static let viewChild = identifier("tree.viewChild")
    static let layerChild = identifier("tree.layerChild")

    private static func identifier(
        _ rawValue: String
    ) -> RuntimeNamespacedIdentifier {
        do {
            return try RuntimeNamespacedIdentifier(rawValue: rawValue)
        } catch {
            preconditionFailure("Invalid built-in graph relation identifier: \(rawValue)")
        }
    }
}
