//
//  RuntimeUIGraphCommandTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/4.
//

import XCTest
@testable import AstrolabeCLI

private typealias Fixtures = CLICommandTestFixtures

final class RuntimeUIGraphCommandTests: XCTestCase {
    func testQueryUsesFrozenSnapshotWithoutRecapturingRuntime() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = graphHierarchy()
        let runner = Fixtures.makeRunner(service: service)
        let snapshotID = try captureSnapshot(using: runner)
        service.hierarchy = [:]

        let output = try runner.run(arguments: [
            "query-ui-graph", "app-1",
            "--snapshot-id", snapshotID,
            "--root-oid", "view-child",
            "--relation", "ios.view.backingLayer",
            "--relation", "tree.layerChild",
            "--direction", "outgoing",
            "--max-depth", "2"
        ])

        let data = try data(from: output)
        XCTAssertEqual(data["snapshotId"] as? String, snapshotID)
        XCTAssertEqual(data["hierarchySource"] as? String, "snapshot")
        let nodes = try XCTUnwrap(data["nodes"] as? [[String: Any]])
        XCTAssertEqual(
            nodes.compactMap { $0["oid"] as? String },
            ["view-child", "layer-child", "gradient"]
        )
        XCTAssertEqual(
            (data["relations"] as? [[String: Any]])?.compactMap {
                $0["type"] as? String
            },
            ["ios.view.backingLayer", "tree.layerChild"]
        )
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testQueryRequiresFrozenSnapshotIdentifier() {
        let runner = Fixtures.makeRunner(service: Fixtures.FakeInspectorService())

        XCTAssertThrowsError(try runner.run(arguments: [
            "query-ui-graph", "app-1",
            "--root-oid", "view-child",
            "--relation", "tree.viewChild"
        ])) { error in
            XCTAssertEqual(CLIError.code(for: error), "missing_argument")
        }
    }

    func testQueryReportsMissingRuntimeGraphCapability() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = graphHierarchy(
            capabilities: ["hierarchySnapshot"]
        )
        let runner = Fixtures.makeRunner(service: service)
        let snapshotID = try captureSnapshot(using: runner)

        XCTAssertThrowsError(try runQuery(
            using: runner,
            snapshotID: snapshotID,
            rootOID: "view-child"
        )) { error in
            XCTAssertEqual(CLIError.code(for: error), "ui_graph_unavailable")
        }
    }

    func testQueryReportsMalformedGraphTopology() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = graphHierarchy(targetNodeID: "missing-layer")
        let runner = Fixtures.makeRunner(service: service)
        let snapshotID = try captureSnapshot(using: runner)

        XCTAssertThrowsError(try runQuery(
            using: runner,
            snapshotID: snapshotID,
            rootOID: "view-child"
        )) { error in
            XCTAssertEqual(
                CLIError.code(for: error),
                "invalid_ui_graph_snapshot"
            )
        }
    }

    func testQueryReportsUnknownRootInSameSnapshot() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = graphHierarchy()
        let runner = Fixtures.makeRunner(service: service)
        let snapshotID = try captureSnapshot(using: runner)

        XCTAssertThrowsError(try runQuery(
            using: runner,
            snapshotID: snapshotID,
            rootOID: "missing-node"
        )) { error in
            XCTAssertEqual(
                CLIError.code(for: error),
                "ui_graph_node_not_found"
            )
        }
    }

    private func captureSnapshot(
        using runner: CLICommandRunner
    ) throws -> String {
        let output = try runner.run(arguments: ["capture-hierarchy", "app-1"])
        return try XCTUnwrap(data(from: output)["snapshotId"] as? String)
    }

    private func runQuery(
        using runner: CLICommandRunner,
        snapshotID: String,
        rootOID: String
    ) throws -> CLICommandOutput {
        try runner.run(arguments: [
            "query-ui-graph", "app-1",
            "--snapshot-id", snapshotID,
            "--root-oid", rootOID,
            "--relation", "ios.view.backingLayer"
        ])
    }

    private func data(
        from output: CLICommandOutput
    ) throws -> [String: Any] {
        guard case .jsonObject(let object) = output else {
            throw CLIError.commandFailed("Expected JSON object output")
        }
        return try XCTUnwrap(object["data"] as? [String: Any])
    }

    private func graphHierarchy(
        capabilities: [String] = ["hierarchySnapshot", "uiGraphRelations"],
        targetNodeID: String = "layer-child"
    ) -> [String: Any] {
        [
            "runtimeCapabilities": capabilities,
            "relations": [[
                "type": "ios.view.backingLayer",
                "sourceNodeID": "view-child",
                "targetNodeID": targetNodeID,
                "extensions": ["ios.verified": true]
            ]],
            "displayItems": [
                node(
                    oid: "view-root",
                    className: "UIWindow",
                    role: "window",
                    kind: "view",
                    children: [
                        node(
                            oid: "view-child",
                            className: "UIView",
                            role: "view",
                            kind: "view"
                        )
                    ]
                ),
                node(
                    oid: "layer-root",
                    className: "CALayer",
                    role: "layer",
                    kind: "layer",
                    children: [
                        node(
                            oid: "layer-child",
                            className: "CALayer",
                            role: "layer",
                            kind: "layer",
                            children: [
                                node(
                                    oid: "gradient",
                                    className: "CAGradientLayer",
                                    role: "layer",
                                    kind: "layer"
                                )
                            ]
                        )
                    ]
                )
            ]
        ]
    }

    private func node(
        oid: String,
        className: String,
        role: String,
        kind: String,
        children: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "oid": oid,
            "detailOid": oid,
            "className": className,
            "runtimeRole": role,
            "kind": kind,
            "subitems": children
        ]
    }
}
