//
//  HierarchySummaryBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct HierarchySummaryBuilder {
    private let extractor: HierarchyNodeExtractor
    private let visibleNodeLimit: Int
    private let textNodeLimit: Int

    init(
        extractor: HierarchyNodeExtractor = HierarchyNodeExtractor(),
        visibleNodeLimit: Int = 12,
        textNodeLimit: Int = 20
    ) {
        self.extractor = extractor
        self.visibleNodeLimit = max(1, visibleNodeLimit)
        self.textNodeLimit = max(1, textNodeLimit)
    }

    func buildSummary(from hierarchy: [String: Any]) -> [String: Any] {
        let records = extractor.collectNodeRecords(in: hierarchy)
        let visibleRecords = records.filter { extractor.isVisibleNode($0.node) }
        let textNodes = visibleRecords.compactMap { extractor.textNodeSnapshot(from: $0) }

        var summary: [String: Any] = [
            "appId": hierarchy["appId"] as? String ?? "",
            "nodeCount": Int(extractor.numericValue(from: hierarchy["nodeCount"]) ?? Double(records.count)),
            "visibleNodeCount": visibleRecords.count,
            "returnedVisibleNodeCount": min(visibleRecords.count, visibleNodeLimit),
            "omittedVisibleNodeCount": max(0, visibleRecords.count - visibleNodeLimit),
            "visibleNodeLimit": visibleNodeLimit,
            "visibleNodes": visibleRecords.prefix(visibleNodeLimit).map {
                extractor.nodeSnapshot(from: $0)
            },
            "textNodeCount": textNodes.count,
            "returnedTextNodeCount": min(textNodes.count, textNodeLimit),
            "omittedTextNodeCount": max(0, textNodes.count - textNodeLimit),
            "textNodeLimit": textNodeLimit,
            "textNodes": textNodes.prefix(textNodeLimit).map { $0 }
        ]
        if let app = hierarchy["app"] as? [String: Any] {
            summary["app"] = app
        }
        if let serverVersion = hierarchy["serverVersion"] {
            summary["serverVersion"] = serverVersion
        }
        if let hierarchyServerVersion = hierarchy["hierarchyServerVersion"] {
            summary["hierarchyServerVersion"] = hierarchyServerVersion
        }
        return summary
    }
}
