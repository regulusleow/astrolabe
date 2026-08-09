//
//  RuntimeUIGraphJSONProjectorTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/4.
//

import AstrolabeProtocol
import Foundation
import XCTest
@testable import AstrolabeCLI

final class RuntimeUIGraphJSONProjectorTests: XCTestCase {
    func testProjectorMapsTypedGraphAndExtensions() throws {
        let fixture = try makeFixture()

        let projection = try RuntimeUIGraphJSONProjector().project(
            query: fixture.query,
            result: fixture.result,
            appID: "app-1",
            snapshotID: "snapshot-1",
            capturedAtUnixTime: 1_000,
            hierarchySource: .snapshot,
            byteLimit: 32_768
        )

        XCTAssertEqual(projection["appId"] as? String, "app-1")
        XCTAssertEqual(projection["snapshotId"] as? String, "snapshot-1")
        XCTAssertEqual(projection["capturedAtUnixTime"] as? Double, 1_000)
        XCTAssertEqual(projection["hierarchySource"] as? String, "snapshot")
        XCTAssertEqual(projection["rootOid"] as? String, "view-1")
        XCTAssertEqual(
            projection["relationTypes"] as? [String],
            ["ios.view.backingLayer", "tree.layerChild"]
        )
        XCTAssertEqual(projection["direction"] as? String, "outgoing")
        XCTAssertEqual(projection["maxDepth"] as? Int, 2)
        XCTAssertEqual(
            projection["limits"] as? [String: Int],
            ["nodeCount": 20, "relationCount": 30, "byteCount": 32_768]
        )
        let nodes = try XCTUnwrap(projection["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.count, 2)
        XCTAssertEqual(nodes[0]["oid"] as? String, "view-1")
        XCTAssertEqual(nodes[0]["className"] as? String, "UIView")
        XCTAssertEqual(nodes[0]["runtimeRole"] as? String, "view")
        XCTAssertEqual(nodes[0]["kind"] as? String, "view")
        let relations = try XCTUnwrap(
            projection["relations"] as? [[String: Any]]
        )
        XCTAssertEqual(relations.count, 1)
        XCTAssertEqual(relations[0]["type"] as? String, "ios.view.backingLayer")
        XCTAssertEqual(relations[0]["sourceNodeID"] as? String, "view-1")
        XCTAssertEqual(relations[0]["targetNodeID"] as? String, "layer-1")
        XCTAssertEqual(
            (relations[0]["extensions"] as? [String: Any])?["ios.verified"]
                as? Bool,
            true
        )
        XCTAssertEqual(projection["truncated"] as? Bool, false)
        XCTAssertEqual(projection["truncationReasons"] as? [String], [])
        XCTAssertEqual(projection["frontierOids"] as? [String], [])
        XCTAssertEqual(projection["omittedFrontierCount"] as? Int, 0)
    }

    func testProjectorPreservesQueryTruncationAndFrontier() throws {
        let fixture = try makeFixture(
            truncationReasons: [.nodeLimit],
            frontierIDs: ["layer-2"]
        )

        let projection = try project(fixture, byteLimit: 32_768)

        XCTAssertEqual(projection["truncated"] as? Bool, true)
        XCTAssertEqual(
            projection["truncationReasons"] as? [String],
            ["nodeLimit"]
        )
        XCTAssertEqual(projection["frontierOids"] as? [String], ["layer-2"])
        XCTAssertEqual(projection["omittedFrontierCount"] as? Int, 0)
    }

    func testProjectorRemovesTailSubgraphToMeetByteLimit() throws {
        let fixture = try makeFixture(
            childClassName: String(repeating: "Layer", count: 500),
            extensionValue: String(repeating: "value", count: 500)
        )

        let projection = try project(fixture, byteLimit: 1_024)

        let nodes = try XCTUnwrap(projection["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.compactMap { $0["oid"] as? String }, ["view-1"])
        XCTAssertEqual(
            (projection["relations"] as? [[String: Any]])?.count,
            0
        )
        XCTAssertEqual(projection["truncated"] as? Bool, true)
        XCTAssertEqual(
            projection["truncationReasons"] as? [String],
            ["byteLimit"]
        )
        XCTAssertEqual(projection["frontierOids"] as? [String], ["layer-1"])
        XCTAssertLessThanOrEqual(try byteCount(of: projection), 1_024)
    }

    func testProjectorReportsFrontierIdentifiersThatCannotFit() throws {
        let frontierIDs = (0 ..< 30).map {
            "frontier-\($0)-" + String(repeating: "x", count: 80)
        }
        let fixture = try makeFixture(
            includesChild: false,
            truncationReasons: [.nodeLimit],
            frontierIDs: frontierIDs
        )

        let projection = try project(fixture, byteLimit: 1_024)

        let returnedFrontier = try XCTUnwrap(
            projection["frontierOids"] as? [String]
        )
        let omittedCount = try XCTUnwrap(
            projection["omittedFrontierCount"] as? Int
        )
        XCTAssertLessThan(returnedFrontier.count, frontierIDs.count)
        XCTAssertEqual(returnedFrontier.count + omittedCount, frontierIDs.count)
        XCTAssertEqual(
            projection["truncationReasons"] as? [String],
            ["nodeLimit", "byteLimit"]
        )
        XCTAssertLessThanOrEqual(try byteCount(of: projection), 1_024)
    }

    func testProjectorRejectsMinimumPayloadLargerThanByteLimit() throws {
        let fixture = try makeFixture(
            rootClassName: String(repeating: "UIView", count: 1_000),
            includesChild: false
        )

        XCTAssertThrowsError(try project(fixture, byteLimit: 1_024)) { error in
            XCTAssertEqual(
                error as? RuntimeUIGraphProjectionError,
                .minimumPayloadExceedsByteLimit
            )
        }
    }

    private func project(
        _ fixture: Fixture,
        byteLimit: Int
    ) throws -> [String: Any] {
        try RuntimeUIGraphJSONProjector().project(
            query: fixture.query,
            result: fixture.result,
            appID: "app-1",
            snapshotID: "snapshot-1",
            capturedAtUnixTime: 1_000,
            hierarchySource: .snapshot,
            byteLimit: byteLimit
        )
    }

    private func makeFixture(
        rootClassName: String = "UIView",
        childClassName: String = "CALayer",
        extensionValue: String? = nil,
        includesChild: Bool = true,
        truncationReasons: [RuntimeUIGraphTruncationReason] = [],
        frontierIDs: [String] = []
    ) throws -> Fixture {
        let rootID = try RuntimeOpaqueIdentifier(rawValue: "view-1")
        let childID = try RuntimeOpaqueIdentifier(rawValue: "layer-1")
        let relationType = try RuntimeNamespacedIdentifier(
            rawValue: "ios.view.backingLayer"
        )
        let relationTypes: Set<RuntimeNamespacedIdentifier> = [
            relationType,
            try RuntimeNamespacedIdentifier(rawValue: "tree.layerChild")
        ]
        let query = RuntimeUIGraphQuery(
            rootNodeID: rootID,
            relationTypes: relationTypes,
            direction: .outgoing,
            maximumDepth: 2,
            nodeLimit: 20,
            relationLimit: 30
        )
        let root = RuntimeUIGraphNode(
            identifier: rootID,
            className: rootClassName,
            role: "view",
            kind: .view
        )
        var nodes = [root]
        var relations = [RuntimeUIGraphRelation]()
        if includesChild {
            nodes.append(RuntimeUIGraphNode(
                identifier: childID,
                className: childClassName,
                role: "layer",
                kind: .layer
            ))
            var extensionValues: [String: RuntimeJSONValue] = [
                "ios.verified": .boolean(true)
            ]
            if let extensionValue {
                extensionValues["ios.payload"] = .string(extensionValue)
            }
            relations.append(RuntimeUIGraphRelation(
                type: relationType,
                sourceNodeID: rootID,
                targetNodeID: childID,
                extensions: try RuntimeExtensionMap(values: extensionValues)
            ))
        }
        return Fixture(
            query: query,
            result: RuntimeUIGraphQueryResult(
                nodes: nodes,
                relations: relations,
                truncated: !truncationReasons.isEmpty,
                truncationReasons: truncationReasons,
                frontierNodeIDs: try frontierIDs.map {
                    try RuntimeOpaqueIdentifier(rawValue: $0)
                }
            )
        )
    }

    private func byteCount(of object: [String: Any]) throws -> Int {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        ).count
    }

    private struct Fixture {
        /// Query supplied to the projector.
        let query: RuntimeUIGraphQuery

        /// Typed graph result supplied to the projector.
        let result: RuntimeUIGraphQueryResult
    }
}
