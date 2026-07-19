//
//  HierarchyPaginationSnapshotStoreTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

import Foundation
import XCTest
@testable import AstrolabeCLI

final class HierarchyPaginationSnapshotStoreTests: XCTestCase {
    func testStorePersistsSnapshotWithPrivatePermissions() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let identifier = UUID().uuidString
        let snapshot = makeSnapshot(identifier: identifier, createdAt: Date())
        let store = FileHierarchyPaginationSnapshotStore(directoryURL: directoryURL)

        try store.save(snapshot)
        let loaded = try store.load(identifier: identifier)

        XCTAssertEqual(loaded.identifier, identifier)
        XCTAssertEqual(loaded.appId, "app-1")
        XCTAssertEqual(loaded.nodes.first?["oid"] as? String, "1")
        let fileURL = directoryURL.appendingPathComponent("\(identifier).json")
        let lockURL = directoryURL.appendingPathComponent(".snapshot-store.lock")
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        let lockAttributes = try FileManager.default.attributesOfItem(atPath: lockURL.path)
        XCTAssertEqual((lockAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testStoreRejectsExpiredSnapshot() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let identifier = UUID().uuidString
        let store = FileHierarchyPaginationSnapshotStore(
            directoryURL: directoryURL,
            timeToLive: 60,
            now: { currentDate }
        )
        try store.save(makeSnapshot(identifier: identifier, createdAt: currentDate))
        currentDate = currentDate.addingTimeInterval(61)

        XCTAssertThrowsError(try store.load(identifier: identifier)) { error in
            XCTAssertEqual(CLIError.code(for: error), "pagination_snapshot_expired")
        }
    }

    func testStoreRejectsInvalidSnapshotIdentifier() {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let store = FileHierarchyPaginationSnapshotStore(directoryURL: directoryURL)

        XCTAssertThrowsError(try store.load(identifier: "../snapshot")) { error in
            XCTAssertEqual(CLIError.code(for: error), "invalid_pagination_cursor")
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
        let store = FileHierarchyPaginationSnapshotStore(
            directoryURL: directoryURL,
            maximumSnapshotCount: 2
        )
        try store.save(makeSnapshot(identifier: firstID, createdAt: Date()))
        try setModificationDate(
            Date().addingTimeInterval(-2),
            identifier: firstID,
            directoryURL: directoryURL
        )
        try store.save(makeSnapshot(identifier: secondID, createdAt: Date()))
        try setModificationDate(
            Date().addingTimeInterval(-1),
            identifier: secondID,
            directoryURL: directoryURL
        )

        try store.save(makeSnapshot(identifier: currentID, createdAt: Date()))

        XCTAssertThrowsError(try store.load(identifier: firstID)) { error in
            XCTAssertEqual(CLIError.code(for: error), "pagination_snapshot_expired")
        }
        XCTAssertNoThrow(try store.load(identifier: secondID))
        XCTAssertNoThrow(try store.load(identifier: currentID))
    }

    func testStoreRejectsSnapshotLargerThanTotalByteLimit() {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let identifier = UUID().uuidString
        let store = FileHierarchyPaginationSnapshotStore(
            directoryURL: directoryURL,
            maximumTotalByteCount: 64
        )

        XCTAssertThrowsError(try store.save(makeSnapshot(
            identifier: identifier,
            createdAt: Date()
        ))) { error in
            XCTAssertEqual(
                CLIError.code(for: error),
                "pagination_snapshot_storage_limit_exceeded"
            )
        }
        let fileURL = directoryURL.appendingPathComponent("\(identifier).json")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testStoreEvictsOldestSnapshotWhenByteLimitIsExceeded() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let firstID = UUID().uuidString
        let secondID = UUID().uuidString
        let currentID = UUID().uuidString
        let bootstrapStore = FileHierarchyPaginationSnapshotStore(
            directoryURL: directoryURL,
            now: { createdAt }
        )
        try bootstrapStore.save(makeSnapshot(identifier: firstID, createdAt: createdAt))
        let firstURL = directoryURL.appendingPathComponent("\(firstID).json")
        let firstByteCount = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: firstURL.path)[.size] as? NSNumber
        ).intValue
        let store = FileHierarchyPaginationSnapshotStore(
            directoryURL: directoryURL,
            maximumTotalByteCount: firstByteCount * 2,
            now: { createdAt }
        )
        try setModificationDate(
            createdAt.addingTimeInterval(-2),
            identifier: firstID,
            directoryURL: directoryURL
        )
        try store.save(makeSnapshot(identifier: secondID, createdAt: createdAt))
        try setModificationDate(
            createdAt.addingTimeInterval(-1),
            identifier: secondID,
            directoryURL: directoryURL
        )

        try store.save(makeSnapshot(identifier: currentID, createdAt: createdAt))

        XCTAssertThrowsError(try store.load(identifier: firstID)) { error in
            XCTAssertEqual(CLIError.code(for: error), "pagination_snapshot_expired")
        }
        XCTAssertNoThrow(try store.load(identifier: secondID))
        XCTAssertNoThrow(try store.load(identifier: currentID))
    }

    private func makeSnapshot(identifier: String, createdAt: Date) -> HierarchyNodeSearchSnapshot {
        HierarchyNodeSearchSnapshot(
            identifier: identifier,
            createdAt: createdAt,
            appId: "app-1",
            pageSnapshotIdentifier: UUID().uuidString,
            pageCapturedAt: createdAt,
            queryFingerprint: "query",
            snapshotFingerprint: "snapshot",
            nodes: [[
                "oid": "1",
                "detailOid": "1",
                "className": "UILabel",
                "frame": ["x": 0, "y": 0, "width": 10, "height": 10],
                "visible": true,
                "semanticRoles": ["text"],
                "hierarchyPath": "UILabel[0]"
            ]]
        )
    }

    private func setModificationDate(
        _ date: Date,
        identifier: String,
        directoryURL: URL
    ) throws {
        let fileURL = directoryURL.appendingPathComponent("\(identifier).json")
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: fileURL.path
        )
    }
}
