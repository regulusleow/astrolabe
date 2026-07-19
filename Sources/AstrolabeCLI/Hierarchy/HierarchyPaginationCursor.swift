//
//  HierarchyPaginationCursor.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/13.
//

import CryptoKit
import Foundation

struct HierarchyPaginationCursorPayload: Codable {
    /// Cursor schema version used to reject unsupported future formats.
    let version: Int

    /// Session-scoped app identifier bound to the cursor.
    let appId: String

    /// Identifier of the local frozen query snapshot referenced by the cursor.
    let snapshotIdentifier: String

    /// Stable fingerprint of the node query.
    let queryFingerprint: String

    /// Stable fingerprint of the matched node identities and order from the first page.
    let snapshotFingerprint: String

    /// Start index of the next page in the validated matches.
    let nextIndex: Int
}

struct HierarchyPaginationCursorCodec {
    private static let currentVersion = 2

    func encode(
        appId: String,
        snapshotIdentifier: String,
        queryFingerprint: String,
        snapshotFingerprint: String,
        nextIndex: Int
    ) throws -> String {
        let payload = HierarchyPaginationCursorPayload(
            version: Self.currentVersion,
            appId: appId,
            snapshotIdentifier: snapshotIdentifier,
            queryFingerprint: queryFingerprint,
            snapshotFingerprint: snapshotFingerprint,
            nextIndex: nextIndex
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func decode(_ cursor: String) throws -> HierarchyPaginationCursorPayload {
        var base64 = cursor
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let paddingCount = (4 - base64.count % 4) % 4
        base64.append(String(repeating: "=", count: paddingCount))
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONDecoder().decode(HierarchyPaginationCursorPayload.self, from: data),
              payload.version == Self.currentVersion,
              UUID(uuidString: payload.snapshotIdentifier) != nil,
              payload.nextIndex >= 0 else {
            throw CLIError.invalidPaginationCursor
        }
        return payload
    }

    func fingerprint(_ components: [String]) -> String {
        var hasher = SHA256()
        for component in components {
            hasher.update(data: Data(component.utf8))
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
