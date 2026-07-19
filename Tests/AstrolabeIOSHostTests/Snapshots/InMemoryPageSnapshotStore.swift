//
//  InMemoryPageSnapshotStore.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

@testable import AstrolabeCLI

final class InMemoryPageSnapshotStore: PageSnapshotStoring {
    private var hierarchies = [String: PageHierarchySnapshot]()
    private var details = [String: [String: PageNodeDetailSnapshot]]()

    func saveHierarchy(_ snapshot: PageHierarchySnapshot) throws {
        hierarchies[snapshot.identifier] = snapshot
    }

    func loadHierarchy(identifier: String, appId: String) throws -> PageHierarchySnapshot {
        guard let snapshot = hierarchies[identifier] else {
            throw CLIError.hierarchySnapshotExpired
        }
        guard snapshot.appId == appId else {
            throw CLIError.hierarchySnapshotMismatch
        }
        return snapshot
    }

    func saveNodeDetail(_ snapshot: PageNodeDetailSnapshot) throws {
        _ = try loadHierarchy(
            identifier: snapshot.snapshotIdentifier,
            appId: snapshot.appId
        )
        details[snapshot.snapshotIdentifier, default: [:]][snapshot.oid] = snapshot
    }

    func loadNodeDetail(
        snapshotIdentifier: String,
        appId: String,
        oid: String
    ) throws -> PageNodeDetailSnapshot? {
        _ = try loadHierarchy(identifier: snapshotIdentifier, appId: appId)
        return details[snapshotIdentifier]?[oid]
    }
}
