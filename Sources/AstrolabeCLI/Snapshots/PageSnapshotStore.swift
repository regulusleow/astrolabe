//
//  PageSnapshotStore.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

import Foundation

struct PageHierarchySnapshot {
    /// Unique identifier of the Host page snapshot.
    let identifier: String

    /// Time when the Host completed hierarchy capture and the snapshot TTL began.
    let createdAt: Date

    /// App session identifier associated with the page snapshot.
    let appId: String

    /// Runtime platform associated with the page snapshot.
    let platform: RuntimeUIPlatform

    /// Immutable full hierarchy returned by the Runtime UI Provider.
    let hierarchy: [String: Any]
}

struct PageNodeDetailSnapshot {
    /// Page snapshot identifier associated with the node details.
    let snapshotIdentifier: String

    /// App session identifier associated with the node details.
    let appId: String

    /// Runtime node-detail identifier.
    let oid: String

    /// Time at which node details were read.
    let capturedAt: Date

    /// Node details returned by the Runtime UI Provider.
    let detail: [String: Any]
}

protocol PageSnapshotStoring {
    func saveHierarchy(_ snapshot: PageHierarchySnapshot) throws
    func loadHierarchy(identifier: String, appId: String) throws -> PageHierarchySnapshot
    func saveNodeDetail(_ snapshot: PageNodeDetailSnapshot) throws
    func loadNodeDetail(
        snapshotIdentifier: String,
        appId: String,
        oid: String
    ) throws -> PageNodeDetailSnapshot?
}

struct FilePageSnapshotStore: PageSnapshotStoring {
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
            .appendingPathComponent("astrolabe-page-snapshots", isDirectory: true),
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
            storageName: "page snapshot",
            fileManager: fileManager
        )
    }

    func saveHierarchy(_ snapshot: PageHierarchySnapshot) throws {
        try storageCoordinator.withExclusiveAccess {
            removeExpiredSnapshots()
            let snapshotDirectory = try snapshotDirectoryURL(identifier: snapshot.identifier)
            try storageCoordinator.createPrivateDirectory(snapshotDirectory)
            let object: [String: Any] = [
                "schemaVersion": Self.schemaVersion,
                "identifier": snapshot.identifier,
                "createdAtUnixTime": snapshot.createdAt.timeIntervalSince1970,
                "appId": snapshot.appId,
                "platform": snapshot.platform.rawValue,
                "hierarchy": snapshot.hierarchy
            ]
            try writeJSONObject(
                object,
                to: snapshotDirectory.appendingPathComponent("hierarchy.json", isDirectory: false)
            )
            try enforceStorageLimits(preserving: snapshot.identifier)
        }
    }

    func loadHierarchy(identifier: String, appId: String) throws -> PageHierarchySnapshot {
        return try storageCoordinator.withExclusiveAccess {
            removeExpiredSnapshots()
            return try loadHierarchyWithoutLock(identifier: identifier, appId: appId)
        }
    }

    private func loadHierarchyWithoutLock(
        identifier: String,
        appId: String
    ) throws -> PageHierarchySnapshot {
        let hierarchyURL = try snapshotDirectoryURL(identifier: identifier)
            .appendingPathComponent("hierarchy.json", isDirectory: false)
        guard fileManager.fileExists(atPath: hierarchyURL.path) else {
            throw CLIError.hierarchySnapshotExpired
        }
        let object = try readJSONObject(from: hierarchyURL)
        guard object["schemaVersion"] as? Int == Self.schemaVersion,
              let storedIdentifier = object["identifier"] as? String,
              storedIdentifier == identifier,
              let createdAtUnixTime = numericValue(from: object["createdAtUnixTime"]),
              let storedAppId = object["appId"] as? String,
              let platformValue = object["platform"] as? String,
              let platform = RuntimeUIPlatform(rawValue: platformValue),
              let hierarchy = object["hierarchy"] as? [String: Any] else {
            throw CLIError.invalidHierarchySnapshot
        }
        guard storedAppId == appId else {
            throw CLIError.hierarchySnapshotMismatch
        }
        let createdAt = Date(timeIntervalSince1970: createdAtUnixTime)
        guard now().timeIntervalSince(createdAt) <= timeToLive else {
            try? fileManager.removeItem(at: hierarchyURL.deletingLastPathComponent())
            throw CLIError.hierarchySnapshotExpired
        }
        return PageHierarchySnapshot(
            identifier: storedIdentifier,
            createdAt: createdAt,
            appId: storedAppId,
            platform: platform,
            hierarchy: hierarchy
        )
    }

    func saveNodeDetail(_ snapshot: PageNodeDetailSnapshot) throws {
        try storageCoordinator.withExclusiveAccess {
            removeExpiredSnapshots()
            _ = try loadHierarchyWithoutLock(
                identifier: snapshot.snapshotIdentifier,
                appId: snapshot.appId
            )
            let detailsDirectory = try snapshotDirectoryURL(identifier: snapshot.snapshotIdentifier)
                .appendingPathComponent("details", isDirectory: true)
            try storageCoordinator.createPrivateDirectory(detailsDirectory)
            let object: [String: Any] = [
                "schemaVersion": Self.schemaVersion,
                "snapshotIdentifier": snapshot.snapshotIdentifier,
                "appId": snapshot.appId,
                "oid": snapshot.oid,
                "capturedAtUnixTime": snapshot.capturedAt.timeIntervalSince1970,
                "detail": snapshot.detail
            ]
            try writeJSONObject(
                object,
                to: detailsDirectory.appendingPathComponent(detailFileName(for: snapshot.oid), isDirectory: false)
            )
            try enforceStorageLimits(preserving: snapshot.snapshotIdentifier)
        }
    }

    func loadNodeDetail(
        snapshotIdentifier: String,
        appId: String,
        oid: String
    ) throws -> PageNodeDetailSnapshot? {
        return try storageCoordinator.withExclusiveAccess {
            removeExpiredSnapshots()
            _ = try loadHierarchyWithoutLock(identifier: snapshotIdentifier, appId: appId)
            return try loadNodeDetailWithoutLock(
                snapshotIdentifier: snapshotIdentifier,
                appId: appId,
                oid: oid
            )
        }
    }

    private func loadNodeDetailWithoutLock(
        snapshotIdentifier: String,
        appId: String,
        oid: String
    ) throws -> PageNodeDetailSnapshot? {
        let detailURL = try snapshotDirectoryURL(identifier: snapshotIdentifier)
            .appendingPathComponent("details", isDirectory: true)
            .appendingPathComponent(detailFileName(for: oid), isDirectory: false)
        guard fileManager.fileExists(atPath: detailURL.path) else {
            return nil
        }
        let object = try readJSONObject(from: detailURL)
        guard object["schemaVersion"] as? Int == Self.schemaVersion,
              object["snapshotIdentifier"] as? String == snapshotIdentifier,
              object["appId"] as? String == appId,
              let storedOID = object["oid"] as? String,
              !storedOID.isEmpty,
              storedOID == oid,
              let capturedAtUnixTime = numericValue(from: object["capturedAtUnixTime"]),
              let detail = object["detail"] as? [String: Any] else {
            throw CLIError.invalidHierarchySnapshot
        }
        return PageNodeDetailSnapshot(
            snapshotIdentifier: snapshotIdentifier,
            appId: appId,
            oid: storedOID,
            capturedAt: Date(timeIntervalSince1970: capturedAtUnixTime),
            detail: detail
        )
    }

    private func snapshotDirectoryURL(identifier: String) throws -> URL {
        guard let uuid = UUID(uuidString: identifier) else {
            throw CLIError.invalidHierarchySnapshot
        }
        return directoryURL.appendingPathComponent(uuid.uuidString, isDirectory: true)
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw CLIError.invalidJSONObject
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func readJSONObject(from url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIError.invalidHierarchySnapshot
        }
        return object
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
        for url in urls where UUID(uuidString: url.lastPathComponent) != nil {
            let hierarchyURL = url.appendingPathComponent("hierarchy.json", isDirectory: false)
            let dateSourceURL = fileManager.fileExists(atPath: hierarchyURL.path) ? hierarchyURL : url
            guard let values = try? dateSourceURL.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modificationDate = values.contentModificationDate,
                  modificationDate < expirationDate else {
                continue
            }
            try? fileManager.removeItem(at: url)
        }
    }

    private func enforceStorageLimits(preserving identifier: String) throws {
        guard let preservingIdentifier = UUID(uuidString: identifier)?.uuidString else {
            throw CLIError.invalidHierarchySnapshot
        }
        try storageCoordinator.enforceStorageLimits(
            records: try snapshotDirectoryRecords(),
            preservingIdentifier: preservingIdentifier,
            preservingURL: directoryURL.appendingPathComponent(
                preservingIdentifier,
                isDirectory: true
            ),
            limits: storageLimits,
            limitExceededError: .hierarchySnapshotStorageLimitExceeded
        )
    }

    private func snapshotDirectoryRecords() throws -> [SnapshotStorageRecord] {
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url in
            guard let identifier = UUID(uuidString: url.lastPathComponent)?.uuidString else {
                return nil
            }
            let hierarchyURL = url.appendingPathComponent("hierarchy.json", isDirectory: false)
            let dateSourceURL = fileManager.fileExists(atPath: hierarchyURL.path) ? hierarchyURL : url
            let values = try dateSourceURL.resourceValues(forKeys: [.contentModificationDateKey])
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

    private func detailFileName(for oid: String) -> String {
        let encoded = Data(oid.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "\(encoded).json"
    }
}
