//
//  BaselineNodeIndexBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct BaselineNodeIndexBuilder {
    private let extractor: HierarchyNodeExtractor

    init(extractor: HierarchyNodeExtractor = HierarchyNodeExtractor()) {
        self.extractor = extractor
    }

    func buildIndex(from hierarchy: [String: Any]) -> [String: Any] {
        let nodes = extractor.collectNodeRecords(in: hierarchy)
            .filter { extractor.isVisibleNode($0.node) }
            .map { extractor.nodeSnapshot(from: $0) }
        return [
            "schemaVersion": 2,
            "nodeCount": nodes.count,
            "nodes": nodes
        ]
    }
}
