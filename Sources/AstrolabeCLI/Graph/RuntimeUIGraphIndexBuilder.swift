//
//  RuntimeUIGraphIndexBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/4.
//

import AstrolabeProtocol

struct RuntimeUIGraphIndexBuilder {
    func build(
        from input: RuntimeUIGraphSnapshotInput
    ) throws -> RuntimeUIGraphIndex {
        var orderedNodes = [RuntimeUIGraphNode]()
        var nodesByIdentifier = [String: RuntimeUIGraphNode]()
        var relations = [RuntimeUIGraphRelation]()
        for root in input.roots {
            try collect(
                root,
                parent: nil,
                orderedNodes: &orderedNodes,
                nodesByIdentifier: &nodesByIdentifier,
                relations: &relations
            )
        }
        relations.append(contentsOf: input.canonicalRelations)
        try validateRelations(
            relations,
            nodesByIdentifier: nodesByIdentifier
        )
        relations.sort(by: RuntimeUIGraphRelation.precedes)

        var outgoing = [String: [RuntimeUIGraphRelation]]()
        var incoming = [String: [RuntimeUIGraphRelation]]()
        for relation in relations {
            outgoing[relation.sourceNodeID.rawValue, default: []].append(relation)
            incoming[relation.targetNodeID.rawValue, default: []].append(relation)
        }
        return RuntimeUIGraphIndex(
            snapshotIdentifier: input.snapshotIdentifier,
            orderedNodes: orderedNodes,
            relations: relations,
            nodesByIdentifier: nodesByIdentifier,
            outgoingRelationsByNodeID: outgoing,
            incomingRelationsByNodeID: incoming
        )
    }

    private func collect(
        _ input: RuntimeUIGraphNodeInput,
        parent: RuntimeUIGraphNodeInput?,
        orderedNodes: inout [RuntimeUIGraphNode],
        nodesByIdentifier: inout [String: RuntimeUIGraphNode],
        relations: inout [RuntimeUIGraphRelation]
    ) throws {
        let rawIdentifier = input.identifier.rawValue
        guard nodesByIdentifier[rawIdentifier] == nil else {
            throw RuntimeUIGraphError.duplicateNodeIdentifier(rawIdentifier)
        }
        let node = RuntimeUIGraphNode(
            identifier: input.identifier,
            className: input.className,
            role: input.role,
            kind: input.kind
        )
        orderedNodes.append(node)
        nodesByIdentifier[rawIdentifier] = node

        if let parent {
            relations.append(RuntimeUIGraphRelation(
                type: treeRelationType(for: parent.kind),
                sourceNodeID: parent.identifier,
                targetNodeID: input.identifier,
                extensions: try RuntimeExtensionMap()
            ))
        }
        for child in input.children {
            try collect(
                child,
                parent: input,
                orderedNodes: &orderedNodes,
                nodesByIdentifier: &nodesByIdentifier,
                relations: &relations
            )
        }
    }

    private func treeRelationType(
        for kind: RuntimeUIGraphNodeKind
    ) -> RuntimeNamespacedIdentifier {
        switch kind {
        case .view:
            return RuntimeUIGraphBuiltInRelation.viewChild
        case .layer:
            return RuntimeUIGraphBuiltInRelation.layerChild
        }
    }

    private func validateRelations(
        _ relations: [RuntimeUIGraphRelation],
        nodesByIdentifier: [String: RuntimeUIGraphNode]
    ) throws {
        var identities = Set<RuntimeUIGraphRelationIdentity>()
        for relation in relations {
            let source = relation.sourceNodeID.rawValue
            let target = relation.targetNodeID.rawValue
            guard nodesByIdentifier[source] != nil,
                  nodesByIdentifier[target] != nil
            else {
                throw RuntimeUIGraphError.danglingRelation(
                    sourceNodeID: source,
                    targetNodeID: target
                )
            }
            guard identities.insert(relation.identity).inserted else {
                throw RuntimeUIGraphError.duplicateRelation(
                    type: relation.type.rawValue,
                    sourceNodeID: source,
                    targetNodeID: target
                )
            }
        }
    }

}
