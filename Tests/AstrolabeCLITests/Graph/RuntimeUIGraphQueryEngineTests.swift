//
//  RuntimeUIGraphQueryEngineTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/4.
//

import AstrolabeProtocol
import XCTest
@testable import AstrolabeCLI

final class RuntimeUIGraphQueryEngineTests: XCTestCase {
    func testQueryTraversesOutgoingAndIncomingRelations() throws {
        let index = try makeIndex()
        let outgoing = try execute(
            root: "view-child",
            relationTypes: ["ios.view.backingLayer"],
            direction: .outgoing,
            in: index
        )
        let incoming = try execute(
            root: "layer-child",
            relationTypes: ["ios.view.backingLayer"],
            direction: .incoming,
            in: index
        )

        XCTAssertEqual(
            outgoing.nodes.map(\.identifier.rawValue),
            ["view-child", "layer-child"]
        )
        XCTAssertEqual(
            incoming.nodes.map(\.identifier.rawValue),
            ["layer-child", "view-child"]
        )
        XCTAssertEqual(outgoing.relations, incoming.relations)
    }

    func testQueryTraversesBothDirectionsInStableOrder() throws {
        let index = try makeIndex()

        let first = try execute(
            root: "layer-child",
            relationTypes: ["ios.view.backingLayer", "tree.layerChild"],
            direction: .both,
            in: index
        )
        let second = try execute(
            root: "layer-child",
            relationTypes: ["tree.layerChild", "ios.view.backingLayer"],
            direction: .both,
            in: index
        )

        XCTAssertEqual(
            first.nodes.map(\.identifier.rawValue),
            ["layer-child", "view-child", "gradient", "layer-root"]
        )
        XCTAssertEqual(first, second)
    }

    func testQueryAppliesTypeFilterAndMaximumDepth() throws {
        let index = try makeIndex()
        let depthOne = try execute(
            root: "layer-root",
            relationTypes: ["tree.layerChild"],
            direction: .outgoing,
            maximumDepth: 1,
            in: index
        )
        let depthTwo = try execute(
            root: "layer-root",
            relationTypes: ["tree.layerChild"],
            direction: .outgoing,
            maximumDepth: 2,
            in: index
        )

        XCTAssertEqual(
            depthOne.nodes.map(\.identifier.rawValue),
            ["layer-root", "layer-child"]
        )
        XCTAssertEqual(
            depthTwo.nodes.map(\.identifier.rawValue),
            ["layer-root", "layer-child", "gradient"]
        )
        XCTAssertTrue(
            depthTwo.relations.allSatisfy {
                $0.type.rawValue == "tree.layerChild"
            }
        )
    }

    func testQueryDoesNotRevisitNodesInCycle() throws {
        let index = try makeIndex()

        let result = try execute(
            root: "view-child",
            relationTypes: ["ios.view.backingLayer", "test.cycle"],
            direction: .outgoing,
            maximumDepth: 4,
            in: index
        )

        XCTAssertEqual(
            result.nodes.map(\.identifier.rawValue),
            ["view-child", "layer-child"]
        )
        XCTAssertEqual(result.relations.count, 2)
    }

    func testQueryRejectsUnknownRoot() throws {
        let index = try makeIndex()

        XCTAssertThrowsError(try execute(
            root: "missing",
            relationTypes: ["tree.layerChild"],
            direction: .outgoing,
            in: index
        )) { error in
            XCTAssertEqual(
                error as? RuntimeUIGraphError,
                .nodeNotFound("missing")
            )
        }
    }

    func testQueryRejectsEachInvalidLimitIndependently() throws {
        let index = try makeIndex()
        let root = try RuntimeOpaqueIdentifier(rawValue: "layer-root")
        let relationType = try RuntimeNamespacedIdentifier(
            rawValue: "tree.layerChild"
        )
        let invalidQueries = [
            RuntimeUIGraphQuery(
                rootNodeID: root,
                relationTypes: [],
                direction: .outgoing,
                maximumDepth: 1,
                nodeLimit: 1,
                relationLimit: 1
            ),
            RuntimeUIGraphQuery(
                rootNodeID: root,
                relationTypes: [relationType],
                direction: .outgoing,
                maximumDepth: 0,
                nodeLimit: 1,
                relationLimit: 1
            ),
            RuntimeUIGraphQuery(
                rootNodeID: root,
                relationTypes: [relationType],
                direction: .outgoing,
                maximumDepth: 5,
                nodeLimit: 1,
                relationLimit: 1
            ),
            RuntimeUIGraphQuery(
                rootNodeID: root,
                relationTypes: [relationType],
                direction: .outgoing,
                maximumDepth: 1,
                nodeLimit: 0,
                relationLimit: 1
            ),
            RuntimeUIGraphQuery(
                rootNodeID: root,
                relationTypes: [relationType],
                direction: .outgoing,
                maximumDepth: 1,
                nodeLimit: 101,
                relationLimit: 1
            ),
            RuntimeUIGraphQuery(
                rootNodeID: root,
                relationTypes: [relationType],
                direction: .outgoing,
                maximumDepth: 1,
                nodeLimit: 1,
                relationLimit: 0
            ),
            RuntimeUIGraphQuery(
                rootNodeID: root,
                relationTypes: [relationType],
                direction: .outgoing,
                maximumDepth: 1,
                nodeLimit: 1,
                relationLimit: 201
            )
        ]

        for query in invalidQueries {
            XCTAssertThrowsError(
                try RuntimeUIGraphQueryEngine().execute(query, in: index)
            ) { error in
                XCTAssertEqual(error as? RuntimeUIGraphError, .invalidQuery)
            }
        }
    }

    func testQueryReportsNodeLimitAndFrontier() throws {
        let index = try makeIndex()

        let result = try execute(
            root: "layer-root",
            relationTypes: ["tree.layerChild"],
            direction: .outgoing,
            maximumDepth: 2,
            nodeLimit: 2,
            in: index
        )

        XCTAssertEqual(
            result.nodes.map(\.identifier.rawValue),
            ["layer-root", "layer-child"]
        )
        XCTAssertEqual(result.relations.count, 1)
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.truncationReasons, [.nodeLimit])
        XCTAssertEqual(
            result.frontierNodeIDs.map(\.rawValue),
            ["gradient"]
        )
    }

    func testQueryReportsRelationLimitAndFrontier() throws {
        let index = try makeIndex()

        let result = try execute(
            root: "view-child",
            relationTypes: ["ios.view.backingLayer", "test.secondary"],
            direction: .outgoing,
            relationLimit: 1,
            in: index
        )

        XCTAssertEqual(
            result.nodes.map(\.identifier.rawValue),
            ["view-child", "layer-child"]
        )
        XCTAssertEqual(
            result.relations.map(\.type.rawValue),
            ["ios.view.backingLayer"]
        )
        XCTAssertTrue(result.truncated)
        XCTAssertEqual(result.truncationReasons, [.relationLimit])
        XCTAssertEqual(
            result.frontierNodeIDs.map(\.rawValue),
            ["gradient"]
        )
    }

    private func execute(
        root: String,
        relationTypes: [String],
        direction: RuntimeUIGraphDirection,
        maximumDepth: Int = 1,
        nodeLimit: Int = 100,
        relationLimit: Int = 200,
        in index: RuntimeUIGraphIndex
    ) throws -> RuntimeUIGraphQueryResult {
        let query = RuntimeUIGraphQuery(
            rootNodeID: try RuntimeOpaqueIdentifier(rawValue: root),
            relationTypes: Set(try relationTypes.map {
                try RuntimeNamespacedIdentifier(rawValue: $0)
            }),
            direction: direction,
            maximumDepth: maximumDepth,
            nodeLimit: nodeLimit,
            relationLimit: relationLimit
        )
        return try RuntimeUIGraphQueryEngine().execute(query, in: index)
    }

    private func makeIndex() throws -> RuntimeUIGraphIndex {
        let input = RuntimeUIGraphSnapshotInput(
            snapshotIdentifier: "snapshot-1",
            roots: [
                node(
                    id: "view-root",
                    className: "UIWindow",
                    role: "window",
                    kind: .view,
                    children: [
                        node(
                            id: "view-child",
                            className: "UIView",
                            role: "view",
                            kind: .view
                        )
                    ]
                ),
                node(
                    id: "layer-root",
                    className: "CALayer",
                    role: "layer",
                    kind: .layer,
                    children: [
                        node(
                            id: "layer-child",
                            className: "CALayer",
                            role: "layer",
                            kind: .layer,
                            children: [
                                node(
                                    id: "gradient",
                                    className: "CAGradientLayer",
                                    role: "layer",
                                    kind: .layer
                                )
                            ]
                        )
                    ]
                )
            ],
            canonicalRelations: [
                try relation(
                    type: "ios.view.backingLayer",
                    source: "view-child",
                    target: "layer-child"
                ),
                try relation(
                    type: "test.cycle",
                    source: "layer-child",
                    target: "view-child"
                ),
                try relation(
                    type: "test.secondary",
                    source: "view-child",
                    target: "gradient"
                )
            ]
        )
        return try RuntimeUIGraphIndexBuilder().build(from: input)
    }

    private func node(
        id: String,
        className: String,
        role: String,
        kind: RuntimeUIGraphNodeKind,
        children: [RuntimeUIGraphNodeInput] = []
    ) -> RuntimeUIGraphNodeInput {
        RuntimeUIGraphNodeInput(
            identifier: try! RuntimeOpaqueIdentifier(rawValue: id),
            className: className,
            role: role,
            kind: kind,
            children: children
        )
    }

    private func relation(
        type: String,
        source: String,
        target: String
    ) throws -> RuntimeUIGraphRelation {
        RuntimeUIGraphRelation(
            type: try RuntimeNamespacedIdentifier(rawValue: type),
            sourceNodeID: try RuntimeOpaqueIdentifier(rawValue: source),
            targetNodeID: try RuntimeOpaqueIdentifier(rawValue: target),
            extensions: try RuntimeExtensionMap()
        )
    }
}
