//
//  BaselineNodeDetailIndexBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct BaselineNodeDetailIndexBuilder {
    private let summaryBuilder: NodeDetailSummaryBuilder

    init(summaryBuilder: NodeDetailSummaryBuilder = NodeDetailSummaryBuilder()) {
        self.summaryBuilder = summaryBuilder
    }

    func buildIndex(
        nodes: [[String: Any]],
        appId: String,
        detailProvider: ([String]) throws -> RuntimeNodeDetailBatch
    ) throws -> [String: Any] {
        var summariesByDetailOid: [String: [String: Any]] = [:]
        var details: [[String: Any]] = []
        var failures: [[String: Any]] = []
        let detailOIDs = uniqueDetailOIDs(from: nodes)
        let batch = try detailProvider(detailOIDs)

        for node in nodes {
            guard let detailOid = nodeIdentifier(from: node["detailOid"]) else {
                continue
            }
            let summary: [String: Any]
            if let cachedSummary = summariesByDetailOid[detailOid] {
                summary = cachedSummary
            } else if let detail = batch.detailsByOID[detailOid] {
                summary = summaryBuilder.buildSummary(from: detail, appId: appId)
                summariesByDetailOid[detailOid] = summary
            } else {
                failures.append(
                    failureRecord(
                        node: node,
                        detailOid: detailOid,
                        error: batch.failuresByOID[detailOid] ?? "Provider did not return node details"
                    )
                )
                continue
            }
            details.append(detailRecord(node: node, detailOid: detailOid, summary: summary))
        }

        return [
            "schemaVersion": 2,
            "detailCount": details.count,
            "failedDetailCount": failures.count,
            "details": details,
            "failures": failures
        ]
    }

    private func detailRecord(node: [String: Any], detailOid: String, summary: [String: Any]) -> [String: Any] {
        let semanticAttributes = summary["semanticAttributes"] as? [String: [String: Any]] ?? [:]
        return [
            "oid": nodeIdentifier(from: node["oid"]) ?? "",
            "detailOid": detailOid,
            "className": node["className"] as? String ?? "",
            "text": node["text"] as? String ?? "",
            "hierarchyPath": node["hierarchyPath"] as? String ?? "",
            "attributeCount": summary["attributeCount"] ?? 0,
            "semanticAttributeCount": semanticAttributes.count,
            "semanticAttributes": semanticAttributes
        ]
    }

    private func failureRecord(
        node: [String: Any],
        detailOid: String,
        error: String
    ) -> [String: Any] {
        [
            "oid": nodeIdentifier(from: node["oid"]) ?? "",
            "detailOid": detailOid,
            "className": node["className"] as? String ?? "",
            "hierarchyPath": node["hierarchyPath"] as? String ?? "",
            "error": error
        ]
    }

    private func uniqueDetailOIDs(from nodes: [[String: Any]]) -> [String] {
        var seen = Set<String>()
        return nodes.reduce(into: [String]()) { result, node in
            guard let oid = nodeIdentifier(from: node["detailOid"]),
                  seen.insert(oid).inserted else {
                return
            }
            result.append(oid)
        }
    }

    private func nodeIdentifier(from value: Any?) -> String? {
        guard let identifier = value as? String, !identifier.isEmpty else {
            return nil
        }
        return identifier
    }
}
