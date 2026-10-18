//
//  PageSnapshotWorkflow.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

import Foundation
import AstrolabeProtocol

struct PageSnapshotCommandArguments {
    /// Page snapshot identifier explicitly provided by the caller.
    let snapshotIdentifier: String?

    /// Explicit semantic capture scope; nil preserves ordinary render capture.
    let semanticCapture: RuntimeSemanticCaptureOptions?

    /// Arguments passed to the original command parser after removing page snapshot options.
    let remainingArguments: [String]
}

struct PageSnapshotArgumentParser {
    func parse(arguments: [String]) throws -> PageSnapshotCommandArguments {
        var snapshotIdentifier: String?
        var includeSemantics = false
        var windowID: RuntimeOpaqueIdentifier?
        var remainingArguments = [String]()
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--include-semantics" {
                guard !includeSemantics else { throw CLIError.invalidArgument("duplicate include-semantics") }
                includeSemantics = true
                index += 1
                continue
            }
            if arguments[index] == "--window-id" {
                guard windowID == nil, index + 1 < arguments.count else {
                    throw CLIError.missingArgument("valid window-id")
                }
                windowID = try RuntimeOpaqueIdentifier(rawValue: arguments[index + 1])
                index += 2
                continue
            }
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
        guard windowID == nil || includeSemantics,
              snapshotIdentifier == nil || !includeSemantics else {
            throw CLIError.invalidArgument("capture selectors require a new semantic capture")
        }
        return PageSnapshotCommandArguments(
            snapshotIdentifier: snapshotIdentifier,
            semanticCapture: includeSemantics ? RuntimeSemanticCaptureOptions(windowID: windowID) : nil,
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
        for key in ["runtimeSnapshotId", "runtimeCapturedAtUnixTime", "semanticCapture"] {
            result[key] = snapshot.hierarchy[key]
        }
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
        snapshotIdentifier: String?,
        semanticCapture: RuntimeSemanticCaptureOptions? = nil
    ) throws -> ResolvedPageHierarchy {
        if let snapshotIdentifier {
            guard semanticCapture == nil else { throw CLIError.invalidArgument("historical snapshot cannot change capture scope") }
            return ResolvedPageHierarchy(
                snapshot: try snapshotStore.loadHierarchy(
                    identifier: snapshotIdentifier,
                    appId: appId
                ),
                source: .snapshot
            )
        }

        var hierarchy = try service.fetchHierarchy(appId: appId, semanticCapture: semanticCapture)
        let platform = try service.platform(for: appId)
        let identifier = UUID().uuidString
        let createdAt = now()
        if hierarchy["semanticCapture"] != nil {
            guard hierarchy["snapshotId"] is String,
                  hierarchy["capturedAtUnixTime"] is NSNumber else {
                throw CLIError.invalidHierarchySnapshot
            }
            hierarchy["runtimeSnapshotId"] = hierarchy["snapshotId"]
            hierarchy["runtimeCapturedAtUnixTime"] = hierarchy["capturedAtUnixTime"]
        }
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
    case runtimeSnapshot
}

struct ResolvedPageNodeDetail {
    /// Node-detail dictionary.
    let detail: [String: Any]

    /// Whether node details came from the Runtime or the page snapshot cache.
    let source: PageNodeDetailSource

    /// Original Runtime capture time for semantic detail; read time for native detail.
    let capturedAt: Date

    /// Page snapshot identifier associated with the node details.
    let snapshotIdentifier: String?

    /// Page hierarchy capture time associated with the node details.
    let pageCapturedAt: Date?

    func addingMetadata(to data: [String: Any]) -> [String: Any] {
        var result = data
        result["detailSource"] = source.rawValue
        result["detailCapturedAtUnixTime"] = capturedAt.timeIntervalSince1970
        result["semanticContext"] = detail["semanticContext"]
        result["extensions"] = detail["extensions"]
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
        let semantic = extractor.collectNodes(in: snapshot.hierarchy).contains {
            $0["kind"] as? String == "semantic" && extractor.nodeIdentifier(from: $0["oid"]) == detailOID
        }
        if let cached = try snapshotStore.loadNodeDetail(
            snapshotIdentifier: snapshot.identifier,
            appId: appId,
            oid: detailOID
        ) {
            if semantic {
                try validateSemanticDetail(cached.detail, oid: detailOID, snapshot: snapshot)
                guard cached.capturedAt == (try semanticCaptureDate(snapshot)) else { throw CLIError.invalidHierarchySnapshot }
            }
            return ResolvedPageNodeDetail(
                detail: cached.detail,
                source: semantic ? .runtimeSnapshot : .snapshotCache,
                capturedAt: semantic ? try semanticCaptureDate(snapshot) : cached.capturedAt,
                snapshotIdentifier: snapshot.identifier,
                pageCapturedAt: snapshot.createdAt
            )
        }

        let detail: [String: Any]
        let capturedAt: Date
        if semantic {
            guard let runtimeID = snapshot.hierarchy["runtimeSnapshotId"] as? String else { throw CLIError.invalidHierarchySnapshot }
            detail = try service.fetchNodeDetail(appId: appId, oid: detailOID, runtimeSnapshotID: runtimeID)
            try validateSemanticDetail(detail, oid: detailOID, snapshot: snapshot)
            capturedAt = try semanticCaptureDate(snapshot)
        } else {
            detail = try service.fetchNodeDetail(appId: appId, oid: detailOID)
            capturedAt = now()
        }
        try snapshotStore.saveNodeDetail(PageNodeDetailSnapshot(
            snapshotIdentifier: snapshot.identifier,
            appId: appId,
            oid: detailOID,
            capturedAt: capturedAt,
            detail: detail
        ))
        return ResolvedPageNodeDetail(
            detail: detail,
            source: semantic ? .runtimeSnapshot : .liveRuntime,
            capturedAt: capturedAt,
            snapshotIdentifier: snapshot.identifier,
            pageCapturedAt: snapshot.createdAt
        )
    }

    func preflightNativeNode(appId: String, oid: String) throws {
        try service.preflightNativeNode(appId: appId, oid: oid)
    }

    private func semanticCaptureDate(_ snapshot: PageHierarchySnapshot) throws -> Date {
        guard let time = extractor.numericValue(from: snapshot.hierarchy["runtimeCapturedAtUnixTime"]), time.isFinite else { throw CLIError.invalidHierarchySnapshot }
        return Date(timeIntervalSince1970: time)
    }

    private func validateSemanticDetail(_ detail: [String: Any], oid: String, snapshot: PageHierarchySnapshot) throws {
        guard let contextObject = detail["semanticContext"] as? [String: Any],
              let runtimeID = snapshot.hierarchy["runtimeSnapshotId"] as? String,
              JSONSerialization.isValidJSONObject(contextObject),
              detail["resolvedOid"] as? String == oid,
              let source = (snapshot.hierarchy["semanticCapture"] as? [String: Any])?["source"] as? String,
              let context = try? JSONDecoder().decode(RuntimeSemanticDetailContext.self, from: JSONSerialization.data(withJSONObject: contextObject)),
              context.snapshotID.rawValue == runtimeID,
              context.source.rawValue == source,
              context.capturedAtUnixTime == (try semanticCaptureDate(snapshot)).timeIntervalSince1970 else {
            throw CLIError.invalidHierarchySnapshot
        }
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
