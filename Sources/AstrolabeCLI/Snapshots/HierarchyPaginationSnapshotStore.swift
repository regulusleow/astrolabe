//
//  HierarchyPaginationSnapshotStore.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

import Foundation

struct HierarchyNodeSearchSnapshot {
    /// Unique identifier of this frozen query snapshot.
    let identifier: String

    /// Snapshot creation time used to bound the local lifetime of sensitive hierarchy data.
    let createdAt: Date

    /// App session identifier bound to the snapshot.
    let appId: String

    /// Page hierarchy snapshot identifier used by this paginated query.
    let pageSnapshotIdentifier: String

    /// Capture time of the page hierarchy snapshot.
    let pageCapturedAt: Date

    /// Node-query fingerprint bound to the snapshot.
    let queryFingerprint: String

    /// Content fingerprint that freezes node identities and order.
    let snapshotFingerprint: String

    /// Immutable node list after filtering and compression.
    let nodes: [[String: Any]]
}

protocol HierarchyPaginationSnapshotStoring {
    func save(_ snapshot: HierarchyNodeSearchSnapshot) throws
    func load(identifier: String) throws -> HierarchyNodeSearchSnapshot
}

struct FileHierarchyPaginationSnapshotStore: HierarchyPaginationSnapshotStoring {
    private static let schemaVersion = 3
    private static let defaultTimeToLive: TimeInterval = 5 * 60

    private let directoryURL: URL
    private let timeToLive: TimeInterval
    private let storageLimits: SnapshotStorageLimits
    private let now: () -> Date
    private let fileManager: FileManager
    private let storageCoordinator: PrivateSnapshotStorageCoordinator

    init(
        directoryURL: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("astrolabe-hierarchy-pagination", isDirectory: true),
        timeToLive: TimeInterval = Self.defaultTimeToLive,
        maximumSnapshotCount: Int = SnapshotStorageLimits.defaultMaximumRecordCount,
        maximumTotalByteCount: Int = SnapshotStorageLimits.defaultMaximumTotalByteCount,
        now: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.timeToLive = timeToLive
        storageLimits = SnapshotStorageLimits(
            maximumRecordCount: maximumSnapshotCount,
            maximumTotalByteCount: maximumTotalByteCount
        )
        self.now = now
        self.fileManager = fileManager
        storageCoordinator = PrivateSnapshotStorageCoordinator(
            directoryURL: directoryURL,
            storageName: "pagination snapshot",
            fileManager: fileManager
        )
    }

    func save(_ snapshot: HierarchyNodeSearchSnapshot) throws {
        try storageCoordinator.withExclusiveAccess {
            removeExpiredSnapshots()
            let object: [String: Any] = [
                "schemaVersion": Self.schemaVersion,
                "identifier": snapshot.identifier,
                "createdAtUnixTime": snapshot.createdAt.timeIntervalSince1970,
                "appId": snapshot.appId,
                "pageSnapshotIdentifier": snapshot.pageSnapshotIdentifier,
                "pageCapturedAtUnixTime": snapshot.pageCapturedAt.timeIntervalSince1970,
                "queryFingerprint": snapshot.queryFingerprint,
                "snapshotFingerprint": snapshot.snapshotFingerprint,
                "nodes": snapshot.nodes
            ]
            guard JSONSerialization.isValidJSONObject(object) else {
                throw CLIError.invalidJSONObject
            }
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let url = try snapshotURL(identifier: snapshot.identifier)
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            try enforceStorageLimits(preserving: snapshot.identifier)
        }
    }

    func load(identifier: String) throws -> HierarchyNodeSearchSnapshot {
        return try storageCoordinator.withExclusiveAccess {
            removeExpiredSnapshots()
            return try loadWithoutLock(identifier: identifier)
        }
    }

    private func loadWithoutLock(identifier: String) throws -> HierarchyNodeSearchSnapshot {
        let url = try snapshotURL(identifier: identifier)
        guard fileManager.fileExists(atPath: url.path) else {
            throw CLIError.paginationSnapshotExpired
        }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["schemaVersion"] as? Int == Self.schemaVersion,
              let storedIdentifier = object["identifier"] as? String,
              storedIdentifier == identifier,
              let createdAtUnixTime = numericValue(from: object["createdAtUnixTime"]),
              let appId = object["appId"] as? String,
              let pageSnapshotIdentifier = object["pageSnapshotIdentifier"] as? String,
              UUID(uuidString: pageSnapshotIdentifier) != nil,
              let pageCapturedAtUnixTime = numericValue(from: object["pageCapturedAtUnixTime"]),
              let queryFingerprint = object["queryFingerprint"] as? String,
              let snapshotFingerprint = object["snapshotFingerprint"] as? String,
              let nodes = object["nodes"] as? [[String: Any]] else {
            throw CLIError.invalidPaginationCursor
        }
        let createdAt = Date(timeIntervalSince1970: createdAtUnixTime)
        guard now().timeIntervalSince(createdAt) <= timeToLive else {
            try? fileManager.removeItem(at: url)
            throw CLIError.paginationSnapshotExpired
        }
        return HierarchyNodeSearchSnapshot(
            identifier: storedIdentifier,
            createdAt: createdAt,
            appId: appId,
            pageSnapshotIdentifier: pageSnapshotIdentifier,
            pageCapturedAt: Date(timeIntervalSince1970: pageCapturedAtUnixTime),
            queryFingerprint: queryFingerprint,
            snapshotFingerprint: snapshotFingerprint,
            nodes: nodes
        )
    }

    private func snapshotURL(identifier: String) throws -> URL {
        guard let uuid = UUID(uuidString: identifier) else {
            throw CLIError.invalidPaginationCursor
        }
        return directoryURL.appendingPathComponent("\(uuid.uuidString).json", isDirectory: false)
    }

    private func removeExpiredSnapshots() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let expirationDate = now().addingTimeInterval(-timeToLive)
        for url in urls where url.pathExtension == "json" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modificationDate = values.contentModificationDate,
                  modificationDate < expirationDate else {
                continue
            }
            try? fileManager.removeItem(at: url)
        }
    }

    private func enforceStorageLimits(preserving identifier: String) throws {
        guard let preservingIdentifier = UUID(uuidString: identifier)?.uuidString else {
            throw CLIError.invalidPaginationCursor
        }
        try storageCoordinator.enforceStorageLimits(
            records: try snapshotRecords(),
            preservingIdentifier: preservingIdentifier,
            preservingURL: directoryURL.appendingPathComponent(
                "\(preservingIdentifier).json",
                isDirectory: false
            ),
            limits: storageLimits,
            limitExceededError: .paginationSnapshotStorageLimitExceeded
        )
    }

    private func snapshotRecords() throws -> [SnapshotStorageRecord] {
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url in
            guard url.pathExtension == "json",
                  let identifier = UUID(
                    uuidString: url.deletingPathExtension().lastPathComponent
                  )?.uuidString else {
                return nil
            }
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey])
            return SnapshotStorageRecord(
                identifier: identifier,
                url: url,
                modificationDate: values.contentModificationDate ?? .distantPast,
                byteCount: try storageCoordinator.byteCount(at: url)
            )
        }
    }

    private func numericValue(from value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        return nil
    }
}
