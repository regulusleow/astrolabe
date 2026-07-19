//
//  HierarchyNodeFinder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct HierarchyNodeQuery {
    /// Exact node OID to match.
    let oid: String?

    /// className substring to match.
    let className: String?

    /// Text substring to match.
    let text: String?

    /// Stable semantic role to match.
    let semanticRole: NodeSemanticRole?

    /// Whether to return only nodes that intersect the screen and are not clipped by ancestors.
    let visibleOnly: Bool

    /// Maximum number of nodes returned per page.
    let limit: Int?

    init(
        oid: String?,
        className: String?,
        text: String?,
        semanticRole: NodeSemanticRole? = nil,
        visibleOnly: Bool,
        limit: Int?
    ) {
        self.oid = oid
        self.className = className
        self.text = text
        self.semanticRole = semanticRole
        self.visibleOnly = visibleOnly
        self.limit = limit
    }

    var hasSelector: Bool {
        if oid != nil {
            return true
        }
        if let className, !className.isEmpty {
            return true
        }
        if let text, !text.isEmpty {
            return true
        }
        if semanticRole != nil {
            return true
        }
        return false
    }

    var dictionary: [String: Any] {
        var result: [String: Any] = [
            "visibleOnly": visibleOnly
        ]
        if let oid {
            result["oid"] = oid
        }
        if let className, !className.isEmpty {
            result["className"] = className
        }
        if let text, !text.isEmpty {
            result["text"] = text
        }
        if let semanticRole {
            result["semanticRole"] = semanticRole.rawValue
        }
        if let limit {
            result["limit"] = limit
        }
        return result
    }
}

struct HierarchyNodeFinder {
    private let extractor: HierarchyNodeExtractor
    private let projectionBuilder: HierarchyNodeSearchProjectionBuilder
    private let cursorCodec: HierarchyPaginationCursorCodec

    init(
        extractor: HierarchyNodeExtractor = HierarchyNodeExtractor(),
        projectionBuilder: HierarchyNodeSearchProjectionBuilder = HierarchyNodeSearchProjectionBuilder(),
        cursorCodec: HierarchyPaginationCursorCodec = HierarchyPaginationCursorCodec()
    ) {
        self.extractor = extractor
        self.projectionBuilder = projectionBuilder
        self.cursorCodec = cursorCodec
    }

    func makeSearchSnapshot(
        in hierarchy: [String: Any],
        appId: String,
        query: HierarchyNodeQuery,
        pageSnapshotIdentifier: String? = nil,
        pageCapturedAt: Date? = nil
    ) -> HierarchyNodeSearchSnapshot {
        let records = matchingRecords(in: hierarchy, query: query)
        let queryFingerprint = paginationQueryFingerprint(appId: appId, query: query)
        let snapshotFingerprint = paginationSnapshotFingerprint(records: records)
        let capturedAt = pageCapturedAt ?? Date()
        return HierarchyNodeSearchSnapshot(
            identifier: UUID().uuidString,
            createdAt: capturedAt,
            appId: appId,
            pageSnapshotIdentifier: pageSnapshotIdentifier
                ?? (hierarchy["snapshotId"] as? String)
                ?? UUID().uuidString,
            pageCapturedAt: capturedAt,
            queryFingerprint: queryFingerprint,
            snapshotFingerprint: snapshotFingerprint,
            nodes: records.map { projectionBuilder.buildProjection(from: $0) }
        )
    }

    func findNodes(
        in hierarchy: [String: Any],
        query: HierarchyNodeQuery
    ) throws -> [String: Any] {
        let appId = hierarchy["appId"] as? String ?? ""
        return try findNodes(
            in: makeSearchSnapshot(in: hierarchy, appId: appId, query: query),
            query: query
        )
    }

    func findNodes(
        in snapshot: HierarchyNodeSearchSnapshot,
        query: HierarchyNodeQuery,
        cursor: String? = nil
    ) throws -> [String: Any] {
        let limit = min(max(1, query.limit ?? 50), HierarchyOutputLimits.maximumFindNodeLimit)
        let offset = try pageOffset(
            cursor: cursor,
            snapshot: snapshot,
            query: query
        )
        let page = Array(snapshot.nodes.dropFirst(offset).prefix(limit))
        let nextOffset = offset + page.count
        var result: [String: Any] = [
            "appId": snapshot.appId,
            "totalCount": snapshot.nodes.count,
            "returnedCount": page.count,
            "limit": limit,
            "hasMore": nextOffset < snapshot.nodes.count,
            "paginationSnapshotId": snapshot.identifier,
            "snapshotId": snapshot.pageSnapshotIdentifier,
            "capturedAtUnixTime": snapshot.pageCapturedAt.timeIntervalSince1970,
            "nodes": page
        ]
        if nextOffset < snapshot.nodes.count {
            result["nextCursor"] = try cursorCodec.encode(
                appId: snapshot.appId,
                snapshotIdentifier: snapshot.identifier,
                queryFingerprint: snapshot.queryFingerprint,
                snapshotFingerprint: snapshot.snapshotFingerprint,
                nextIndex: nextOffset
            )
        }
        return result
    }

    func snapshotIdentifier(from cursor: String) throws -> String {
        try cursorCodec.decode(cursor).snapshotIdentifier
    }

    func firstNodeSnapshot(in hierarchy: [String: Any], query: HierarchyNodeQuery) -> [String: Any]? {
        guard let record = matchingRecords(in: hierarchy, query: query).first else {
            return nil
        }
        return extractor.nodeSnapshot(from: record)
    }

    func findRecords(in hierarchy: [String: Any], query: HierarchyNodeQuery) -> [HierarchyNodeRecord] {
        matchingRecords(in: hierarchy, query: query)
    }

    func detailOid(from snapshot: [String: Any]) -> String? {
        extractor.nodeIdentifier(from: snapshot["detailOid"])
    }

    private func matchingRecords(in hierarchy: [String: Any], query: HierarchyNodeQuery) -> [HierarchyNodeRecord] {
        extractor.collectNodeRecords(in: hierarchy).filter { record in
            matches(node: record.node, query: query)
        }
    }

    private func pageOffset(
        cursor: String?,
        snapshot: HierarchyNodeSearchSnapshot,
        query: HierarchyNodeQuery
    ) throws -> Int {
        guard let cursor else {
            return 0
        }
        let payload = try cursorCodec.decode(cursor)
        let queryFingerprint = paginationQueryFingerprint(appId: snapshot.appId, query: query)
        guard payload.appId == snapshot.appId,
              payload.snapshotIdentifier == snapshot.identifier,
              payload.queryFingerprint == queryFingerprint,
              snapshot.queryFingerprint == queryFingerprint else {
            throw CLIError.paginationCursorMismatch
        }
        guard payload.snapshotFingerprint == snapshot.snapshotFingerprint,
              payload.nextIndex <= snapshot.nodes.count else {
            throw CLIError.paginationSnapshotChanged
        }
        return payload.nextIndex
    }

    private func paginationQueryFingerprint(appId: String, query: HierarchyNodeQuery) -> String {
        cursorCodec.fingerprint([
            "appId:\(appId)",
            "oid:\(query.oid ?? "")",
            "className:\(query.className?.lowercased() ?? "")",
            "text:\(query.text?.lowercased() ?? "")",
            "semanticRole:\(query.semanticRole?.rawValue ?? "")",
            "visibleOnly:\(query.visibleOnly)"
        ])
    }

    private func paginationSnapshotFingerprint(records: [HierarchyNodeRecord]) -> String {
        cursorCodec.fingerprint(records.map { record in
            let oid = extractor.nodeIdentifier(from: record.node["oid"]) ?? ""
            let detailOid = extractor.nodeIdentifier(from: record.node["detailOid"]) ?? ""
            let className = record.node["className"] as? String ?? ""
            return "\(oid)|\(detailOid)|\(className)|\(record.hierarchyPath)"
        })
    }

    private func matches(node: [String: Any], query: HierarchyNodeQuery) -> Bool {
        if let oid = query.oid {
            guard extractor.nodeIdentifier(from: node["oid"]) == oid else {
                return false
            }
        }
        if query.visibleOnly && !extractor.isVisibleNode(node) {
            return false
        }
        if let className = query.className, !className.isEmpty {
            let nodeClassName = node["className"] as? String ?? ""
            if nodeClassName.range(of: className, options: [.caseInsensitive]) == nil {
                return false
            }
        }
        if let text = query.text, !text.isEmpty {
            let nodeText = extractor.text(from: node) ?? ""
            if nodeText.range(of: text, options: [.caseInsensitive]) == nil {
                return false
            }
        }
        if let semanticRole = query.semanticRole,
           !extractor.semanticRoles(from: node).contains(semanticRole) {
            return false
        }
        return true
    }
}
