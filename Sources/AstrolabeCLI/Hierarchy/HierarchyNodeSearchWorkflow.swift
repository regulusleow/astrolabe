//
//  HierarchyNodeSearchWorkflow.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

struct HierarchyNodeSearchWorkflow {
    private let hierarchyResolver: PageHierarchyResolver
    private let nodeFinder: HierarchyNodeFinder
    private let snapshotStore: any HierarchyPaginationSnapshotStoring

    init(
        hierarchyResolver: PageHierarchyResolver,
        nodeFinder: HierarchyNodeFinder = HierarchyNodeFinder(),
        snapshotStore: any HierarchyPaginationSnapshotStoring
    ) {
        self.hierarchyResolver = hierarchyResolver
        self.nodeFinder = nodeFinder
        self.snapshotStore = snapshotStore
    }

    func findNodes(
        appId: String,
        query: HierarchyNodeQuery,
        cursor: String?,
        snapshotIdentifier: String?
    ) throws -> [String: Any] {
        if let cursor {
            let identifier = try nodeFinder.snapshotIdentifier(from: cursor)
            let snapshot = try snapshotStore.load(identifier: identifier)
            guard snapshot.appId == appId else {
                throw CLIError.paginationCursorMismatch
            }
            if let snapshotIdentifier,
               snapshot.pageSnapshotIdentifier != snapshotIdentifier {
                throw CLIError.paginationCursorMismatch
            }
            var result = try nodeFinder.findNodes(in: snapshot, query: query, cursor: cursor)
            result["hierarchySource"] = PageHierarchySource.snapshot.rawValue
            return result
        }

        let resolvedHierarchy = try hierarchyResolver.resolve(
            appId: appId,
            snapshotIdentifier: snapshotIdentifier
        )
        let snapshot = nodeFinder.makeSearchSnapshot(
            in: resolvedHierarchy.snapshot.hierarchy,
            appId: appId,
            query: query,
            pageSnapshotIdentifier: resolvedHierarchy.snapshot.identifier,
            pageCapturedAt: resolvedHierarchy.snapshot.createdAt
        )
        var result = try nodeFinder.findNodes(in: snapshot, query: query)
        result["hierarchySource"] = resolvedHierarchy.source.rawValue
        if result["hasMore"] as? Bool == true {
            try snapshotStore.save(snapshot)
        }
        return result
    }
}
