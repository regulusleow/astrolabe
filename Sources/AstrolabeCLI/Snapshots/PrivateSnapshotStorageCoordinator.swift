//
//  PrivateSnapshotStorageCoordinator.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

import Darwin
import Foundation

struct SnapshotStorageLimits {
    /// Default record limit shared by page and pagination snapshots.
    static let defaultMaximumRecordCount = 20

    /// Default total capacity limit shared by page and pagination snapshots.
    static let defaultMaximumTotalByteCount = 100 * 1_024 * 1_024

    /// Maximum number of records retained by the snapshot store.
    let maximumRecordCount: Int

    /// Maximum total bytes occupied by the snapshot store.
    let maximumTotalByteCount: Int

    init(maximumRecordCount: Int, maximumTotalByteCount: Int) {
        precondition(maximumRecordCount > 0, "The snapshot count limit must be greater than zero")
        precondition(maximumTotalByteCount > 0, "The snapshot byte limit must be greater than zero")
        self.maximumRecordCount = maximumRecordCount
        self.maximumTotalByteCount = maximumTotalByteCount
    }
}

struct SnapshotStorageRecord {
    /// Unique identifier of the snapshot record.
    let identifier: String

    /// File or directory URL associated with the snapshot record.
    let url: URL

    /// Last modification time used for eviction ordering.
    let modificationDate: Date

    /// Current byte size of the snapshot record.
    let byteCount: Int
}

struct PrivateSnapshotStorageCoordinator {
    private let directoryURL: URL
    private let storageName: String
    private let fileManager: FileManager

    init(directoryURL: URL, storageName: String, fileManager: FileManager) {
        self.directoryURL = directoryURL
        self.storageName = storageName
        self.fileManager = fileManager
    }

    func withExclusiveAccess<T>(_ operation: () throws -> T) throws -> T {
        try createPrivateDirectory(directoryURL)
        let lockURL = directoryURL.appendingPathComponent(".snapshot-store.lock", isDirectory: false)
        let descriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            throw CLIError.commandFailed("Unable to create the \(storageName) storage lock")
        }
        defer {
            _ = Darwin.close(descriptor)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: lockURL.path)
        guard Darwin.lockf(descriptor, F_LOCK, 0) == 0 else {
            throw CLIError.commandFailed("Unable to lock \(storageName) storage")
        }
        defer {
            _ = Darwin.lockf(descriptor, F_ULOCK, 0)
        }
        return try operation()
    }

    func createPrivateDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    func enforceStorageLimits(
        records: [SnapshotStorageRecord],
        preservingIdentifier: String,
        preservingURL: URL,
        limits: SnapshotStorageLimits,
        limitExceededError: CLIError
    ) throws {
        var remainingCount = records.count
        var remainingByteCount = records.reduce(0) { partialResult, record in
            let addition = partialResult.addingReportingOverflow(record.byteCount)
            return addition.overflow ? Int.max : addition.partialValue
        }
        let removableRecords = records
            .filter { $0.identifier != preservingIdentifier }
            .sorted { $0.modificationDate < $1.modificationDate }
        for record in removableRecords
        where remainingCount > limits.maximumRecordCount ||
            remainingByteCount > limits.maximumTotalByteCount {
            try removeItemIfExists(at: record.url)
            remainingCount -= 1
            remainingByteCount = max(0, remainingByteCount - record.byteCount)
        }
        guard remainingCount <= limits.maximumRecordCount,
              remainingByteCount <= limits.maximumTotalByteCount else {
            try removeItemIfExists(at: preservingURL)
            throw limitExceededError
        }
    }

    func byteCount(at url: URL) throws -> Int {
        let rootValues = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        if rootValues.isRegularFile == true {
            return rootValues.fileSize ?? 0
        }
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        var result = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let fileSize = values.fileSize else {
                continue
            }
            let addition = result.addingReportingOverflow(fileSize)
            if addition.overflow {
                return Int.max
            }
            result = addition.partialValue
        }
        return result
    }

    private func removeItemIfExists(at url: URL) throws {
        do {
            try fileManager.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}
