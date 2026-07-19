//
//  PageSnapshotWorkflow.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

import Foundation

struct PageSnapshotCommandArguments {
    /// Page snapshot identifier explicitly provided by the caller.
    let snapshotIdentifier: String?

    /// Arguments passed to the original command parser after removing page snapshot options.
    let remainingArguments: [String]
}

struct PageSnapshotArgumentParser {
    func parse(arguments: [String]) throws -> PageSnapshotCommandArguments {
        var snapshotIdentifier: String?
        var remainingArguments = [String]()
        var index = 0
        while index < arguments.count {
            guard arguments[index] == "--snapshot-id" else {
                remainingArguments.append(arguments[index])
                index += 1
                continue
            }
            guard snapshotIdentifier == nil,
                  index + 1 < arguments.count,
                  let identifier = UUID(uuidString: arguments[index + 1]) else {
                throw CLIError.invalidHierarchySnapshot
            }
            snapshotIdentifier = identifier.uuidString
            index += 2
        }
        return PageSnapshotCommandArguments(
            snapshotIdentifier: snapshotIdentifier,
            remainingArguments: remainingArguments
        )
    }
}

enum PageHierarchySource: String {
    case liveRuntime
    case snapshot
}

struct ResolvedPageHierarchy {
    /// Page hierarchy snapshot used by this command.
    let snapshot: PageHierarchySnapshot

    /// Whether the page hierarchy came from live capture or an existing snapshot.
    let source: PageHierarchySource

    func addingMetadata(to data: [String: Any]) -> [String: Any] {
        var result = data
        result["snapshotId"] = snapshot.identifier
        result["capturedAtUnixTime"] = snapshot.createdAt.timeIntervalSince1970
        result["hierarchySource"] = source.rawValue
        return result
    }
}

struct PageHierarchyResolver {
    private let service: any RuntimeUIHierarchyCapturing & RuntimeUIPlatformResolving
    private let snapshotStore: any PageSnapshotStoring
    private let now: () -> Date

    init(
        service: any RuntimeUIHierarchyCapturing & RuntimeUIPlatformResolving,
        snapshotStore: any PageSnapshotStoring,
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.snapshotStore = snapshotStore
        self.now = now
    }

    func resolve(
        appId: String,
        snapshotIdentifier: String?
    ) throws -> ResolvedPageHierarchy {
        if let snapshotIdentifier {
            return ResolvedPageHierarchy(
                snapshot: try snapshotStore.loadHierarchy(
                    identifier: snapshotIdentifier,
                    appId: appId
                ),
                source: .snapshot
            )
        }

        var hierarchy = try service.fetchHierarchy(appId: appId)
        let platform = try service.platform(for: appId)
        let identifier = UUID().uuidString
        let createdAt = now()
        hierarchy["appId"] = appId
        hierarchy["snapshotId"] = identifier
        hierarchy["capturedAtUnixTime"] = createdAt.timeIntervalSince1970
        let snapshot = PageHierarchySnapshot(
            identifier: identifier,
            createdAt: createdAt,
            appId: appId,
            platform: platform,
            hierarchy: hierarchy
        )
        try snapshotStore.saveHierarchy(snapshot)
        return ResolvedPageHierarchy(snapshot: snapshot, source: .liveRuntime)
    }
}

enum PageNodeDetailSource: String {
    case liveRuntime
    case snapshotCache
}

struct ResolvedPageNodeDetail {
    /// Node-detail dictionary.
    let detail: [String: Any]

    /// Whether node details came from the Runtime or the page snapshot cache.
    let source: PageNodeDetailSource

    /// Time at which node details were read.
    let capturedAt: Date

    /// Page snapshot identifier associated with the node details.
    let snapshotIdentifier: String?

    /// Page hierarchy capture time associated with the node details.
    let pageCapturedAt: Date?

    func addingMetadata(to data: [String: Any]) -> [String: Any] {
        var result = data
        result["detailSource"] = source.rawValue
        result["detailCapturedAtUnixTime"] = capturedAt.timeIntervalSince1970
        if let snapshotIdentifier {
            result["snapshotId"] = snapshotIdentifier
            result["hierarchySource"] = PageHierarchySource.snapshot.rawValue
        }
        if let pageCapturedAt {
            result["capturedAtUnixTime"] = pageCapturedAt.timeIntervalSince1970
        }
        return result
    }
}

struct PageNodeDetailResolver {
    private let service: any RuntimeUINodeDetailProviding
    private let snapshotStore: any PageSnapshotStoring
    private let extractor: HierarchyNodeExtractor
    private let now: () -> Date

    init(
        service: any RuntimeUINodeDetailProviding,
        snapshotStore: any PageSnapshotStoring,
        extractor: HierarchyNodeExtractor = HierarchyNodeExtractor(),
        now: @escaping () -> Date = Date.init
    ) {
        self.service = service
        self.snapshotStore = snapshotStore
        self.extractor = extractor
        self.now = now
    }

    func resolve(
        appId: String,
        oid: String,
        snapshotIdentifier: String?
    ) throws -> ResolvedPageNodeDetail {
        let snapshot = try snapshotIdentifier.map {
            try snapshotStore.loadHierarchy(identifier: $0, appId: appId)
        }
        return try resolve(appId: appId, oid: oid, snapshot: snapshot)
    }

    func resolve(
        appId: String,
        oid: String,
        snapshot: PageHierarchySnapshot?
    ) throws -> ResolvedPageNodeDetail {
        guard let snapshot else {
            let detail = try service.fetchNodeDetail(appId: appId, oid: oid)
            return ResolvedPageNodeDetail(
                detail: detail,
                source: .liveRuntime,
                capturedAt: now(),
                snapshotIdentifier: nil,
                pageCapturedAt: nil
            )
        }
        guard snapshot.appId == appId else {
            throw CLIError.hierarchySnapshotMismatch
        }
        guard let detailOID = detailOID(for: oid, hierarchy: snapshot.hierarchy) else {
            throw CLIError.snapshotNodeNotFound
        }
        if let cached = try snapshotStore.loadNodeDetail(
            snapshotIdentifier: snapshot.identifier,
            appId: appId,
            oid: detailOID
        ) {
            return ResolvedPageNodeDetail(
                detail: cached.detail,
                source: .snapshotCache,
                capturedAt: cached.capturedAt,
                snapshotIdentifier: snapshot.identifier,
                pageCapturedAt: snapshot.createdAt
            )
        }

        let detail = try service.fetchNodeDetail(appId: appId, oid: detailOID)
        let capturedAt = now()
        try snapshotStore.saveNodeDetail(PageNodeDetailSnapshot(
            snapshotIdentifier: snapshot.identifier,
            appId: appId,
            oid: detailOID,
            capturedAt: capturedAt,
            detail: detail
        ))
        return ResolvedPageNodeDetail(
            detail: detail,
            source: .liveRuntime,
            capturedAt: capturedAt,
            snapshotIdentifier: snapshot.identifier,
            pageCapturedAt: snapshot.createdAt
        )
    }

    private func detailOID(for requestedOID: String, hierarchy: [String: Any]) -> String? {
        let nodes = extractor.collectNodes(in: hierarchy)
        if nodes.contains(where: { extractor.nodeIdentifier(from: $0["detailOid"]) == requestedOID }) {
            return requestedOID
        }
        guard let node = nodes.first(where: { extractor.nodeIdentifier(from: $0["oid"]) == requestedOID }) else {
            return nil
        }
        return extractor.nodeIdentifier(from: node["detailOid"])
            ?? extractor.nodeIdentifier(from: node["oid"])
    }
}
