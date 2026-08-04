//
//  PageSnapshotStoreTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

import Foundation
import XCTest
@testable import AstrolabeCLI

final class PageSnapshotStoreTests: XCTestCase {
    func testArgumentParserExtractsAndCanonicalizesSnapshotId() throws {
        let snapshotID = UUID().uuidString.lowercased()

        let result = try PageSnapshotArgumentParser().parse(arguments: [
            "--class",
            "UILabel",
            "--snapshot-id",
            snapshotID,
            "--limit",
            "2"
        ])

        XCTAssertEqual(result.snapshotIdentifier, UUID(uuidString: snapshotID)?.uuidString)
        XCTAssertEqual(result.remainingArguments, ["--class", "UILabel", "--limit", "2"])
    }

    func testArgumentParserRejectsDuplicateSnapshotId() {
        let snapshotID = UUID().uuidString

        XCTAssertThrowsError(try PageSnapshotArgumentParser().parse(arguments: [
            "--snapshot-id",
            snapshotID,
            "--snapshot-id",
            snapshotID
        ])) { error in
            XCTAssertEqual(CLIError.code(for: error), "invalid_hierarchy_snapshot")
        }
    }

    func testStorePersistsHierarchyAndNodeDetailWithPrivatePermissions() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let snapshotID = UUID().uuidString
        let store = FilePageSnapshotStore(directoryURL: directoryURL)
        let snapshot = PageHierarchySnapshot(
            identifier: snapshotID,
            createdAt: Date(),
            appId: "app-1",
            platform: .ios,
            hierarchy: hierarchy(snapshotID: snapshotID)
        )

        try store.saveHierarchy(snapshot)
        try store.saveNodeDetail(
            PageNodeDetailSnapshot(
                snapshotIdentifier: snapshotID,
                appId: "app-1",
                oid: "node-2",
                capturedAt: Date(),
                detail: ["requestedOid": "node-2", "attributeGroups": []]
            )
        )

        let reader = FilePageSnapshotStore(directoryURL: directoryURL)
        let loadedHierarchy = try reader.loadHierarchy(
            identifier: snapshotID,
            appId: "app-1"
        )
        let loadedDetail = try XCTUnwrap(try reader.loadNodeDetail(
            snapshotIdentifier: snapshotID,
            appId: "app-1",
            oid: "node-2"
        ))
        XCTAssertEqual(loadedHierarchy.identifier, snapshotID)
        XCTAssertEqual(loadedHierarchy.platform, .ios)
        XCTAssertEqual(
            loadedHierarchy.hierarchy["runtimeCapabilities"] as? [String],
            ["hierarchySnapshot", "uiGraphRelations"]
        )
        let relations = try XCTUnwrap(
            loadedHierarchy.hierarchy["relations"] as? [[String: Any]]
        )
        XCTAssertEqual(relations.count, 1)
        XCTAssertEqual(relations[0]["type"] as? String, "ios.view.backingLayer")
        XCTAssertEqual(relations[0]["sourceNodeID"] as? String, "1")
        XCTAssertEqual(relations[0]["targetNodeID"] as? String, "2")
        XCTAssertEqual(loadedDetail.oid, "node-2")
        XCTAssertEqual(loadedDetail.detail["requestedOid"] as? String, "node-2")

        let snapshotDirectory = directoryURL.appendingPathComponent(snapshotID, isDirectory: true)
        let hierarchyURL = snapshotDirectory.appendingPathComponent("hierarchy.json")
        let detailURL = snapshotDirectory
            .appendingPathComponent("details", isDirectory: true)
            .appendingPathComponent("bm9kZS0y.json")
        let lockURL = directoryURL.appendingPathComponent(".snapshot-store.lock")
        XCTAssertEqual(permissions(at: snapshotDirectory), 0o700)
        XCTAssertEqual(permissions(at: hierarchyURL), 0o600)
        XCTAssertEqual(permissions(at: detailURL), 0o600)
        XCTAssertEqual(permissions(at: lockURL), 0o600)
    }

    func testStoreRejectsExpiredHierarchySnapshot() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let snapshotID = UUID().uuidString
        let store = FilePageSnapshotStore(
            directoryURL: directoryURL,
            timeToLive: 60,
            now: { currentDate }
        )
        try store.saveHierarchy(PageHierarchySnapshot(
            identifier: snapshotID,
            createdAt: currentDate,
            appId: "app-1",
            platform: .ios,
            hierarchy: hierarchy(snapshotID: snapshotID)
        ))
        currentDate = currentDate.addingTimeInterval(61)

        XCTAssertThrowsError(try store.loadHierarchy(
            identifier: snapshotID,
            appId: "app-1"
        )) { error in
            XCTAssertEqual(CLIError.code(for: error), "hierarchy_snapshot_expired")
        }
    }

    func testStoreRejectsSnapshotForDifferentApp() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let snapshotID = UUID().uuidString
        let store = FilePageSnapshotStore(directoryURL: directoryURL)
        try store.saveHierarchy(PageHierarchySnapshot(
            identifier: snapshotID,
            createdAt: Date(),
            appId: "app-1",
            platform: .ios,
            hierarchy: hierarchy(snapshotID: snapshotID)
        ))

        XCTAssertThrowsError(try store.loadHierarchy(
            identifier: snapshotID,
            appId: "app-2"
        )) { error in
            XCTAssertEqual(CLIError.code(for: error), "hierarchy_snapshot_mismatch")
        }
    }

    func testStoreEvictsOldestSnapshotWhenCountLimitIsExceeded() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let firstID = UUID().uuidString
        let secondID = UUID().uuidString
        let currentID = UUID().uuidString
        let store = FilePageSnapshotStore(
            directoryURL: directoryURL,
            maximumSnapshotCount: 2
        )
        try store.saveHierarchy(PageHierarchySnapshot(
            identifier: firstID,
            createdAt: Date(),
            appId: "app-1",
            platform: .ios,
            hierarchy: hierarchy(snapshotID: firstID)
        ))
        try setHierarchyModificationDate(
            Date().addingTimeInterval(-2),
            snapshotID: firstID,
            directoryURL: directoryURL
        )
        try store.saveHierarchy(PageHierarchySnapshot(
            identifier: secondID,
            createdAt: Date(),
            appId: "app-1",
            platform: .ios,
            hierarchy: hierarchy(snapshotID: secondID)
        ))
        try setHierarchyModificationDate(
            Date().addingTimeInterval(-1),
            snapshotID: secondID,
            directoryURL: directoryURL
        )

        try store.saveHierarchy(PageHierarchySnapshot(
            identifier: currentID,
            createdAt: Date(),
            appId: "app-1",
            platform: .ios,
            hierarchy: hierarchy(snapshotID: currentID)
        ))

        XCTAssertThrowsError(try store.loadHierarchy(identifier: firstID, appId: "app-1")) { error in
            XCTAssertEqual(CLIError.code(for: error), "hierarchy_snapshot_expired")
        }
        XCTAssertNoThrow(try store.loadHierarchy(identifier: secondID, appId: "app-1"))
        XCTAssertNoThrow(try store.loadHierarchy(identifier: currentID, appId: "app-1"))
    }

    func testStoreRejectsSnapshotLargerThanTotalByteLimit() {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let snapshotID = UUID().uuidString
        let store = FilePageSnapshotStore(
            directoryURL: directoryURL,
            maximumTotalByteCount: 64
        )

        XCTAssertThrowsError(try store.saveHierarchy(PageHierarchySnapshot(
            identifier: snapshotID,
            createdAt: Date(),
            appId: "app-1",
            platform: .ios,
            hierarchy: hierarchy(snapshotID: snapshotID)
        ))) { error in
            XCTAssertEqual(
                CLIError.code(for: error),
                "hierarchy_snapshot_storage_limit_exceeded"
            )
        }
        let snapshotDirectory = directoryURL.appendingPathComponent(snapshotID, isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotDirectory.path))
    }

    private func hierarchy(snapshotID: String) -> [String: Any] {
        [
            "appId": "app-1",
            "snapshotId": snapshotID,
            "runtimeCapabilities": ["hierarchySnapshot", "uiGraphRelations"],
            "relations": [[
                "type": "ios.view.backingLayer",
                "sourceNodeID": "1",
                "targetNodeID": "2",
                "extensions": [:]
            ]],
            "displayItems": [[
                "oid": "2",
                "detailOid": "2",
                "className": "UILabel",
                "frame": ["x": 0, "y": 0, "width": 80, "height": 20],
                "visible": true
            ]]
        ]
    }

    private func permissions(at url: URL) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }

    private func setHierarchyModificationDate(
        _ date: Date,
        snapshotID: String,
        directoryURL: URL
    ) throws {
        let hierarchyURL = directoryURL
            .appendingPathComponent(snapshotID, isDirectory: true)
            .appendingPathComponent("hierarchy.json", isDirectory: false)
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: hierarchyURL.path
        )
    }
}
