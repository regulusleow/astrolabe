//
//  RuntimeUIGraphIndexBuilderTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/4.
//

import AstrolabeProtocol
import Foundation
import XCTest
@testable import AstrolabeCLI

final class RuntimeUIGraphIndexBuilderTests: XCTestCase {
    func testBuilderDerivesViewChildForAndroidHierarchy() throws {
        let snapshot = makeSnapshot(
            platform: .android,
            roots: [
                node(
                    id: "android-root",
                    className: "android.widget.LinearLayout",
                    role: "window",
                    kind: "view",
                    children: [
                        node(
                            id: "android-label",
                            className: "android.widget.TextView",
                            role: "label",
                            kind: "view"
                        )
                    ]
                )
            ],
            relations: []
        )

        let index = try buildIndex(snapshot: snapshot)

        XCTAssertEqual(index.relations.map(\.type.rawValue), ["tree.viewChild"])
        XCTAssertEqual(index.relations.first?.sourceNodeID.rawValue, "android-root")
        XCTAssertEqual(index.relations.first?.targetNodeID.rawValue, "android-label")
    }

    func testBuilderIndexesCanonicalAndDerivedTreeRelations() throws {
        let index = try buildIndex(snapshot: makeSnapshot())

        XCTAssertEqual(
            index.orderedNodes.map(\.identifier.rawValue),
            ["view-root", "view-child", "layer-root", "layer-child"]
        )
        XCTAssertEqual(
            index.relations.map(\.type.rawValue),
            ["ios.view.backingLayer", "tree.layerChild", "tree.viewChild"]
        )
        XCTAssertEqual(
            index.outgoingRelations(
                from: try RuntimeOpaqueIdentifier(rawValue: "view-child")
            ).map(\.targetNodeID.rawValue),
            ["layer-child"]
        )
        XCTAssertEqual(
            index.incomingRelations(
                to: try RuntimeOpaqueIdentifier(rawValue: "layer-child")
            ).map(\.type.rawValue),
            ["ios.view.backingLayer", "tree.layerChild"]
        )
        XCTAssertEqual(
            index.relations.first?.extensions.values["ios.relation.verified"],
            .boolean(true)
        )
    }

    func testAdapterRequiresUIGraphCapability() {
        let snapshot = makeSnapshot(capabilities: ["hierarchySnapshot"])

        XCTAssertThrowsError(
            try RuntimeUIGraphSnapshotAdapter().adapt(snapshot)
        ) { error in
            XCTAssertEqual(error as? RuntimeUIGraphError, .capabilityUnavailable)
        }
    }

    func testAdapterPreservesUnknownNamespacedRelationType() throws {
        let snapshot = makeSnapshot(relations: [[
            "type": "vendor.experimentalRelation",
            "sourceNodeID": "view-root",
            "targetNodeID": "layer-root",
            "extensions": [:]
        ]])

        let input = try RuntimeUIGraphSnapshotAdapter().adapt(snapshot)

        XCTAssertEqual(
            input.canonicalRelations.map(\.type.rawValue),
            ["vendor.experimentalRelation"]
        )
    }

    func testAdapterRejectsMissingRelationsPayload() {
        let snapshot = makeSnapshot(includeRelations: false)

        XCTAssertThrowsError(
            try RuntimeUIGraphSnapshotAdapter().adapt(snapshot)
        ) { error in
            XCTAssertEqual(error as? RuntimeUIGraphError, .invalidSnapshot)
        }
    }

    func testAdapterRejectsMalformedRelation() {
        let snapshot = makeSnapshot(relations: [[
            "type": "ios.view.backingLayer",
            "sourceNodeID": "view-child",
            "targetNodeID": 42,
            "extensions": [:]
        ]])

        XCTAssertThrowsError(
            try RuntimeUIGraphSnapshotAdapter().adapt(snapshot)
        ) { error in
            XCTAssertEqual(error as? RuntimeUIGraphError, .invalidSnapshot)
        }
    }

    func testBuilderRejectsDuplicateNodeIdentifiers() {
        let duplicate = node(
            id: "view-root",
            className: "DuplicateView",
            role: "view",
            kind: "view"
        )
        let snapshot = makeSnapshot(
            roots: defaultRoots() + [duplicate],
            relations: []
        )

        XCTAssertThrowsError(try buildIndex(snapshot: snapshot)) { error in
            XCTAssertEqual(
                error as? RuntimeUIGraphError,
                .duplicateNodeIdentifier("view-root")
            )
        }
    }

    func testBuilderRejectsDanglingCanonicalRelation() {
        let snapshot = makeSnapshot(relations: [[
            "type": "ios.view.backingLayer",
            "sourceNodeID": "view-child",
            "targetNodeID": "missing-layer",
            "extensions": [:]
        ]])

        XCTAssertThrowsError(try buildIndex(snapshot: snapshot)) { error in
            XCTAssertEqual(
                error as? RuntimeUIGraphError,
                .danglingRelation(
                    sourceNodeID: "view-child",
                    targetNodeID: "missing-layer"
                )
            )
        }
    }

    func testBuilderRejectsDuplicateRelations() {
        let relation = canonicalRelation()
        let snapshot = makeSnapshot(relations: [relation, relation])

        XCTAssertThrowsError(try buildIndex(snapshot: snapshot)) { error in
            XCTAssertEqual(
                error as? RuntimeUIGraphError,
                .duplicateRelation(
                    type: "ios.view.backingLayer",
                    sourceNodeID: "view-child",
                    targetNodeID: "layer-child"
                )
            )
        }
    }

    private func buildIndex(
        snapshot: PageHierarchySnapshot
    ) throws -> RuntimeUIGraphIndex {
        let input = try RuntimeUIGraphSnapshotAdapter().adapt(snapshot)
        return try RuntimeUIGraphIndexBuilder().build(from: input)
    }

    private func makeSnapshot(
        platform: RuntimeUIPlatform = .ios,
        capabilities: [String] = ["hierarchySnapshot", "uiGraphRelations"],
        roots: [[String: Any]]? = nil,
        relations: [[String: Any]]? = nil,
        includeRelations: Bool = true
    ) -> PageHierarchySnapshot {
        let identifier = UUID().uuidString
        var hierarchy: [String: Any] = [
            "appId": "app-1",
            "snapshotId": identifier,
            "runtimeCapabilities": capabilities,
            "displayItems": roots ?? defaultRoots()
        ]
        if includeRelations {
            hierarchy["relations"] = relations ?? [canonicalRelation()]
        }
        return PageHierarchySnapshot(
            identifier: identifier,
            createdAt: Date(timeIntervalSince1970: 1_000),
            appId: "app-1",
            platform: platform,
            hierarchy: hierarchy
        )
    }

    private func defaultRoots() -> [[String: Any]] {
        [
            node(
                id: "view-root",
                className: "UIWindow",
                role: "window",
                kind: "view",
                children: [
                    node(
                        id: "view-child",
                        className: "UIView",
                        role: "view",
                        kind: "view"
                    )
                ]
            ),
            node(
                id: "layer-root",
                className: "CALayer",
                role: "layer",
                kind: "layer",
                children: [
                    node(
                        id: "layer-child",
                        className: "CAGradientLayer",
                        role: "layer",
                        kind: "layer"
                    )
                ]
            )
        ]
    }

    private func node(
        id: String,
        className: String,
        role: String,
        kind: String,
        children: [[String: Any]] = []
    ) -> [String: Any] {
        [
            "oid": id,
            "detailOid": id,
            "className": className,
            "runtimeRole": role,
            "kind": kind,
            "subitems": children
        ]
    }

    private func canonicalRelation() -> [String: Any] {
        [
            "type": "ios.view.backingLayer",
            "sourceNodeID": "view-child",
            "targetNodeID": "layer-child",
            "extensions": ["ios.relation.verified": true]
        ]
    }
}
