//
//  InMemoryHierarchyPaginationSnapshotStore.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

@testable import AstrolabeCLI

final class InMemoryHierarchyPaginationSnapshotStore: HierarchyPaginationSnapshotStoring {
    private var snapshots = [String: HierarchyNodeSearchSnapshot]()

    func save(_ snapshot: HierarchyNodeSearchSnapshot) throws {
        snapshots[snapshot.identifier] = snapshot
    }

    func load(identifier: String) throws -> HierarchyNodeSearchSnapshot {
        guard let snapshot = snapshots[identifier] else {
            throw CLIError.paginationSnapshotExpired
        }
        return snapshot
    }
}
