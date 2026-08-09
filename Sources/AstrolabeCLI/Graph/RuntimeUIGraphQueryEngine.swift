//
//  RuntimeUIGraphQueryEngine.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/4.
//

import AstrolabeProtocol

enum RuntimeUIGraphDirection: String, Equatable {
    case outgoing
    case incoming
    case both
}

struct RuntimeUIGraphQuery: Equatable {
    /// Starting node in the immutable page snapshot.
    let rootNodeID: RuntimeOpaqueIdentifier

    /// Relation types allowed during traversal.
    let relationTypes: Set<RuntimeNamespacedIdentifier>

    /// Direction applied to every traversal hop.
    let direction: RuntimeUIGraphDirection

    /// Maximum BFS hop count, in the inclusive range 1...4.
    let maximumDepth: Int

    /// Maximum returned node count, including the root, in 1...100.
    let nodeLimit: Int

    /// Maximum returned relation count, in 1...200.
    let relationLimit: Int
}

enum RuntimeUIGraphTruncationReason: String, Equatable, Hashable {
    case nodeLimit
    case relationLimit
}

struct RuntimeUIGraphQueryResult: Equatable {
    /// Nodes in deterministic breadth-first traversal order.
    let nodes: [RuntimeUIGraphNode]

    /// Traversed relations in deterministic order.
    let relations: [RuntimeUIGraphRelation]

    /// Whether a node or relation budget stopped traversal output.
    let truncated: Bool

    /// Budgets that prevented complete traversal output.
    let truncationReasons: [RuntimeUIGraphTruncationReason]

    /// Unvisited neighboring nodes available for a follow-up query.
    let frontierNodeIDs: [RuntimeOpaqueIdentifier]
}

struct RuntimeUIGraphQueryEngine {
    func execute(
        _ query: RuntimeUIGraphQuery,
        in index: RuntimeUIGraphIndex
    ) throws -> RuntimeUIGraphQueryResult {
        try validate(query)
        guard let root = index.node(identifiedBy: query.rootNodeID) else {
            throw RuntimeUIGraphError.nodeNotFound(query.rootNodeID.rawValue)
        }

        var nodes = [root]
        var relations = [RuntimeUIGraphRelation]()
        var visitedNodeIDs: Set<String> = [root.identifier.rawValue]
        var visitedRelationIDs = Set<RuntimeUIGraphRelationIdentity>()
        var queue = [TraversalEntry(nodeID: root.identifier, depth: 0)]
        var queueIndex = 0
        var truncationReasons = [RuntimeUIGraphTruncationReason]()
        var frontierNodeIDs = [RuntimeOpaqueIdentifier]()
        var frontierRawIDs = Set<String>()

        while queueIndex < queue.count {
            let entry = queue[queueIndex]
            queueIndex += 1
            guard entry.depth < query.maximumDepth else {
                continue
            }
            for candidate in candidates(
                from: entry.nodeID,
                direction: query.direction,
                index: index
            ) where query.relationTypes.contains(candidate.relation.type) {
                guard !visitedRelationIDs.contains(
                    candidate.relation.identity
                ) else {
                    continue
                }
                let neighborRawID = candidate.neighborNodeID.rawValue
                let neighborVisited = visitedNodeIDs.contains(neighborRawID)

                guard relations.count < query.relationLimit else {
                    appendUnique(.relationLimit, to: &truncationReasons)
                    if !neighborVisited {
                        appendFrontier(
                            candidate.neighborNodeID,
                            identifiers: &frontierNodeIDs,
                            rawIdentifiers: &frontierRawIDs
                        )
                    }
                    continue
                }
                if !neighborVisited, nodes.count >= query.nodeLimit {
                    appendUnique(.nodeLimit, to: &truncationReasons)
                    appendFrontier(
                        candidate.neighborNodeID,
                        identifiers: &frontierNodeIDs,
                        rawIdentifiers: &frontierRawIDs
                    )
                    continue
                }

                visitedRelationIDs.insert(candidate.relation.identity)
                relations.append(candidate.relation)
                guard !neighborVisited,
                      let neighbor = index.node(
                          identifiedBy: candidate.neighborNodeID
                      )
                else {
                    continue
                }
                visitedNodeIDs.insert(neighborRawID)
                nodes.append(neighbor)
                queue.append(TraversalEntry(
                    nodeID: neighbor.identifier,
                    depth: entry.depth + 1
                ))
            }
        }

        return RuntimeUIGraphQueryResult(
            nodes: nodes,
            relations: relations,
            truncated: !truncationReasons.isEmpty,
            truncationReasons: truncationReasons,
            frontierNodeIDs: frontierNodeIDs
        )
    }

    private func validate(
        _ query: RuntimeUIGraphQuery
    ) throws {
        guard !query.relationTypes.isEmpty,
              RuntimeUIGraphQueryLimits.maximumDepthRange.contains(
                  query.maximumDepth
              ),
              RuntimeUIGraphQueryLimits.nodeCountRange.contains(
                  query.nodeLimit
              ),
              RuntimeUIGraphQueryLimits.relationCountRange.contains(
                  query.relationLimit
              )
        else {
            throw RuntimeUIGraphError.invalidQuery
        }
    }

    private func candidates(
        from nodeID: RuntimeOpaqueIdentifier,
        direction: RuntimeUIGraphDirection,
        index: RuntimeUIGraphIndex
    ) -> [TraversalCandidate] {
        var result = [TraversalCandidate]()
        if direction == .outgoing || direction == .both {
            result.append(contentsOf: index.outgoingRelations(from: nodeID).map {
                TraversalCandidate(
                    relation: $0,
                    neighborNodeID: $0.targetNodeID
                )
            })
        }
        if direction == .incoming || direction == .both {
            result.append(contentsOf: index.incomingRelations(to: nodeID).map {
                TraversalCandidate(
                    relation: $0,
                    neighborNodeID: $0.sourceNodeID
                )
            })
        }
        var identities = Set<RuntimeUIGraphRelationIdentity>()
        return result
            .filter { identities.insert($0.relation.identity).inserted }
            .sorted {
                RuntimeUIGraphRelation.precedes(
                    $0.relation,
                    $1.relation
                )
            }
    }

    private func appendUnique(
        _ reason: RuntimeUIGraphTruncationReason,
        to reasons: inout [RuntimeUIGraphTruncationReason]
    ) {
        guard !reasons.contains(reason) else {
            return
        }
        reasons.append(reason)
    }

    private func appendFrontier(
        _ identifier: RuntimeOpaqueIdentifier,
        identifiers: inout [RuntimeOpaqueIdentifier],
        rawIdentifiers: inout Set<String>
    ) {
        guard rawIdentifiers.insert(identifier.rawValue).inserted else {
            return
        }
        identifiers.append(identifier)
    }
}

private struct TraversalEntry {
    /// Node to expand.
    let nodeID: RuntimeOpaqueIdentifier

    /// BFS depth of the node.
    let depth: Int
}

private struct TraversalCandidate {
    /// Relation considered for traversal.
    let relation: RuntimeUIGraphRelation

    /// Neighbor reached from the current node under the selected direction.
    let neighborNodeID: RuntimeOpaqueIdentifier
}
