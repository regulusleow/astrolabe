//
//  ScreenInspectionBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

package struct ScreenInspectionBuilder {
    private let extractor: HierarchyNodeExtractor
    private let targetSelector: ScreenInspectionTargetSelector

    package init(qualityPolicy: any ScreenInspectionTargetQualityEvaluating) {
        self.init(
            extractor: HierarchyNodeExtractor(),
            qualityPolicy: qualityPolicy
        )
    }

    init(
        extractor: HierarchyNodeExtractor = HierarchyNodeExtractor(),
        qualityPolicy: any ScreenInspectionTargetQualityEvaluating
    ) {
        self.extractor = extractor
        self.targetSelector = ScreenInspectionTargetSelector(
            extractor: extractor,
            qualityPolicy: qualityPolicy
        )
    }

    func buildInspection(
        from hierarchy: [String: Any],
        targetLimit: Int,
        classLimit: Int = HierarchyOutputLimits.defaultClassLimit
    ) -> [String: Any] {
        let records = extractor.collectNodeRecords(in: hierarchy)
        let visibleRecords = records.filter { extractor.isVisibleNode($0.node) }
        let visibleNodes = visibleRecords.map(\.node)
        let targets = targetSelector.rankedTargets(from: visibleRecords)
        let classHistogram = classHistogram(from: visibleNodes)
        let boundedClassLimit = min(
            max(1, classLimit),
            HierarchyOutputLimits.maximumClassLimit
        )
        let boundedTargetLimit = min(
            max(1, targetLimit),
            HierarchyOutputLimits.maximumTargetLimit
        )
        var inspection: [String: Any] = [
            "appId": hierarchy["appId"] as? String ?? "",
            "nodeCount": Int(extractor.numericValue(from: hierarchy["nodeCount"]) ?? Double(records.count)),
            "visibleNodeCount": visibleRecords.count,
            "textNodeCount": visibleRecords.reduce(into: 0) { count, record in
                if extractor.text(from: record.node) != nil {
                    count += 1
                }
            },
            "classCount": classHistogram.count,
            "returnedClassCount": min(classHistogram.count, boundedClassLimit),
            "omittedClassCount": max(0, classHistogram.count - boundedClassLimit),
            "classLimit": boundedClassLimit,
            "classHistogram": Array(classHistogram.prefix(boundedClassLimit)),
            "checkTargetCount": targets.count,
            "returnedCheckTargetCount": min(targets.count, boundedTargetLimit),
            "omittedCheckTargetCount": max(0, targets.count - boundedTargetLimit),
            "targetLimit": boundedTargetLimit,
            "checkTargets": Array(targets.prefix(boundedTargetLimit)),
            "recommendedNextTools": [
                "inspect_node",
                "summarize_node_detail",
                "check_node",
                "check_node_detail"
            ]
        ]
        copyMetadata(from: hierarchy, to: &inspection)
        return inspection
    }

    private func classHistogram(from nodes: [[String: Any]]) -> [[String: Any]] {
        let counts = nodes.reduce(into: [String: Int]()) { result, node in
            let className = node["className"] as? String ?? ""
            guard !className.isEmpty else {
                return
            }
            result[className, default: 0] += 1
        }

        return counts
            .sorted { lhs, rhs in
                if lhs.value != rhs.value {
                    return lhs.value > rhs.value
                }
                return lhs.key < rhs.key
            }
            .map { className, count in
                [
                    "className": className,
                    "visibleCount": count
                ]
            }
    }

    private func copyMetadata(from hierarchy: [String: Any], to inspection: inout [String: Any]) {
        for key in ["app", "serverVersion", "hierarchyServerVersion"] {
            if let value = hierarchy[key] {
                inspection[key] = value
            }
        }
    }

}
