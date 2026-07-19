//
//  HierarchyNodeSearchProjectionBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

struct HierarchyNodeSearchProjectionBuilder {
    private let extractor: HierarchyNodeExtractor

    init(extractor: HierarchyNodeExtractor = HierarchyNodeExtractor()) {
        self.extractor = extractor
    }

    func buildProjection(from record: HierarchyNodeRecord) -> [String: Any] {
        var projection: [String: Any] = [
            "oid": extractor.nodeIdentifier(from: record.node["oid"]) ?? "",
            "detailOid": extractor.nodeIdentifier(from: record.node["detailOid"])
                ?? extractor.nodeIdentifier(from: record.node["oid"])
                ?? "",
            "className": record.node["className"] as? String ?? "",
            "frame": record.node["frame"] ?? [:],
            "visible": extractor.isVisibleNode(record.node),
            "semanticRoles": extractor.semanticRoles(from: record.node).map(\.rawValue).sorted(),
            "hierarchyPath": record.hierarchyPath
        ]
        if let text = extractor.text(from: record.node) {
            projection["text"] = text
        }
        return projection
    }
}
