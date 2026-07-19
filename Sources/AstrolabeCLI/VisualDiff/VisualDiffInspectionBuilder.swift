//
//  VisualDiffInspectionBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct VisualDiffInspectionBuilder {
    private let issueInterpreter: any VisualDiffIssueInterpreting

    init(
        issueInterpreter: any VisualDiffIssueInterpreting =
            PlatformNeutralVisualDiffIssueInterpreter()
    ) {
        self.issueInterpreter = issueInterpreter
    }

    func buildInspection(comparison: [String: Any], appId: String? = nil) -> [String: Any] {
        let baselineComparisons = baselineComparisons(from: comparison)
        let affectedNodes = (comparison["affectedNodes"] as? [[String: Any]] ?? []).map {
            enrichedNode($0, baselineComparisons: baselineComparisons)
        }
        let likelyCauses = affectedNodes
            .map { likelyCause(from: $0, appId: appId ?? "") }
            .sorted { sortLikelyCauses($0, $1, appId: appId ?? "") }
        let regionSummaries = regionSummaries(
            regions: comparison["mismatchRegions"] as? [[String: Any]] ?? [],
            likelyCauses: likelyCauses
        )
        let followUpCommands = followUpCommands(appId: appId, likelyCauses: likelyCauses)

        return [
            "passed": comparison["passed"] as? Bool ?? false,
            "reason": comparison["reason"] as? String ?? "unknown",
            "mismatchRatio": comparison["mismatchRatio"] ?? 0,
            "mismatchPixels": comparison["mismatchPixels"] ?? 0,
            "mismatchBounds": comparison["mismatchBounds"] ?? NSNull(),
            "mismatchRegionCount": comparison["mismatchRegionCount"] ?? 0,
            "omittedMismatchRegionCount": comparison["omittedMismatchRegionCount"] ?? 0,
            "ignoredRegionCount": comparison["ignoredRegionCount"] ?? 0,
            "ignoredPixels": comparison["ignoredPixels"] ?? 0,
            "ignoredNodeRegionCount": comparison["ignoredNodeRegionCount"] ?? 0,
            "ignoredNodeRegions": comparison["ignoredNodeRegions"] ?? [],
            "unresolvedIgnoreNodeOids": comparison["unresolvedIgnoreNodeOids"] ?? [],
            "ignoredMaskRegionCount": comparison["ignoredMaskRegionCount"] ?? 0,
            "ignoredMaskRegions": comparison["ignoredMaskRegions"] ?? [],
            "unresolvedIgnoreMasks": comparison["unresolvedIgnoreMasks"] ?? [],
            "ignoredQueryRegionCount": comparison["ignoredQueryRegionCount"] ?? 0,
            "ignoredQueryRegions": comparison["ignoredQueryRegions"] ?? [],
            "unresolvedIgnoreQueries": comparison["unresolvedIgnoreQueries"] ?? [],
            "affectedNodeCount": comparison["affectedNodeCount"] ?? 0,
            "omittedAffectedNodeCount": comparison["omittedAffectedNodeCount"] ?? 0,
            "regionSummaries": regionSummaries,
            "likelyCauses": likelyCauses,
            "primaryAffectedNode": likelyCauses.first ?? NSNull(),
            "recommendedNextTools": recommendedNextTools(likelyCauses: likelyCauses, regionSummaries: regionSummaries),
            "followUpCommands": followUpCommands,
            "baselineNodeComparison": comparison["baselineNodeComparison"] ?? NSNull(),
            "comparison": compactComparison(from: comparison)
        ]
    }

    private func regionSummaries(regions: [[String: Any]], likelyCauses: [[String: Any]]) -> [[String: Any]] {
        regions.enumerated().map { index, region in
            let nodes = likelyCauses.filter { node in
                (node["regionIndex"] as? Int ?? -1) == index
            }
            return [
                "regionIndex": index,
                "bounds": region,
                "pixelCount": region["pixelCount"] ?? NSNull(),
                "likelyNodeCount": nodes.count,
                "dominantIssue": dominantIssue(from: nodes),
                "dominantCategory": dominantCategory(from: nodes),
                "likelyNodes": nodes.map(compactNode(_:)),
                "summary": summary(regionIndex: index, region: region, nodes: nodes)
            ]
        }
    }

    private func likelyCause(from node: [String: Any], appId: String) -> [String: Any] {
        var result = compactNode(node)
        result["regionIndex"] = node["regionIndex"] ?? NSNull()
        result["overlapArea"] = node["overlapArea"] ?? 0
        result["regionOverlapRatio"] = node["regionOverlapRatio"] ?? 0
        result["confidenceScore"] = confidenceScore(for: node, appId: appId)
        result["confidence"] = confidenceLabel(score: result["confidenceScore"] as? Double ?? 0)
        let suspectedIssues = issueInterpreter.suspectedIssues(
            for: node,
            appId: appId
        )
        let interpretation = issueInterpreter.interpretation(
            for: node,
            suspectedIssues: suspectedIssues,
            appId: appId
        )
        result["suspectedIssues"] = suspectedIssues
        result.merge(interpretation.dictionary) { _, new in new }
        result["summary"] = nodeSummary(node)
        appendBaselineFields(from: node, to: &result)
        return result
    }

    private func compactNode(_ node: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [
            "oid": nodeIdentifier(from: node["oid"]) ?? "",
            "detailOid": nodeIdentifier(from: node["detailOid"])
                ?? nodeIdentifier(from: node["oid"])
                ?? "",
            "className": node["className"] as? String ?? "",
            "text": node["text"] as? String ?? "",
            "frame": node["frame"] ?? [:],
            "hierarchyPath": node["hierarchyPath"] as? String ?? ""
        ]
        if let frameInPixels = node["frameInPixels"] {
            result["frameInPixels"] = frameInPixels
        }
        if let dominantCategory = node["dominantCategory"] {
            result["dominantCategory"] = dominantCategory
        }
        if let issueCategories = node["issueCategories"] {
            result["issueCategories"] = issueCategories
        }
        return result
    }

    private func sortLikelyCauses(
        _ lhs: [String: Any],
        _ rhs: [String: Any],
        appId: String
    ) -> Bool {
        let lhsBaselineChangeCount = numericValue(from: lhs["baselineChangeCount"])
        let rhsBaselineChangeCount = numericValue(from: rhs["baselineChangeCount"])
        if lhsBaselineChangeCount > 0, rhsBaselineChangeCount == 0 {
            return true
        }
        if rhsBaselineChangeCount > 0, lhsBaselineChangeCount == 0 {
            return false
        }
        let lhsCategoryRank = issueInterpreter.categoryRank(
            for: lhs["dominantCategory"] as? String ?? "",
            appId: appId
        )
        let rhsCategoryRank = issueInterpreter.categoryRank(
            for: rhs["dominantCategory"] as? String ?? "",
            appId: appId
        )
        if lhsBaselineChangeCount > 0,
           rhsBaselineChangeCount > 0,
           lhsCategoryRank != rhsCategoryRank {
            return lhsCategoryRank < rhsCategoryRank
        }
        let lhsScore = lhs["confidenceScore"] as? Double ?? 0
        let rhsScore = rhs["confidenceScore"] as? Double ?? 0
        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }
        let lhsRegion = lhs["regionIndex"] as? Int ?? 0
        let rhsRegion = rhs["regionIndex"] as? Int ?? 0
        if lhsRegion != rhsRegion {
            return lhsRegion < rhsRegion
        }
        return (nodeIdentifier(from: lhs["oid"]) ?? "") < (nodeIdentifier(from: rhs["oid"]) ?? "")
    }

    private func confidenceScore(for node: [String: Any], appId: String) -> Double {
        let overlapRatio = doubleValue(from: node["regionOverlapRatio"])
        let overlapArea = min(doubleValue(from: node["overlapArea"]) / 10, 1)
        let semanticWeight = issueInterpreter.semanticWeight(
            for: node,
            appId: appId
        )
        let visualScore = min(1, overlapRatio * 0.6 + overlapArea * 0.2 + semanticWeight * 0.2)
        let baselineSignal = min(Double(numericValue(from: node["baselineChangeCount"])) / 3, 1)
        guard baselineSignal > 0 else {
            return visualScore
        }
        return min(1, visualScore + baselineSignal * 0.2)
    }

    private func confidenceLabel(score: Double) -> String {
        if score >= 0.75 {
            return "high"
        }
        if score >= 0.4 {
            return "medium"
        }
        return "low"
    }

    private func dominantIssue(from nodes: [[String: Any]]) -> Any {
        guard let firstIssue = (nodes.first?["suspectedIssues"] as? [String])?.first else {
            return NSNull()
        }
        return firstIssue
    }

    private func dominantCategory(from nodes: [[String: Any]]) -> Any {
        guard let category = nodes.first?["dominantCategory"] as? String, !category.isEmpty else {
            return NSNull()
        }
        return category
    }

    private func summary(regionIndex: Int, region: [String: Any], nodes: [[String: Any]]) -> String {
        if let firstNode = nodes.first {
            return "diff region \(regionIndex) overlaps \(nodeTitle(firstNode))"
        }
        let width = region["width"] ?? "?"
        let height = region["height"] ?? "?"
        return "diff region \(regionIndex) has no matched visible node, size \(width)x\(height)"
    }

    private func nodeSummary(_ node: [String: Any]) -> String {
        if let baselineSummary = node["baselineSummary"] as? String,
           numericValue(from: node["baselineChangeCount"]) > 0 {
            return baselineSummary
        }
        let regionIndex = node["regionIndex"] as? Int ?? 0
        return "\(nodeTitle(node)) overlaps diff region \(regionIndex)"
    }

    private func nodeTitle(_ node: [String: Any]) -> String {
        let className = node["className"] as? String ?? "Unknown"
        guard let text = node["text"] as? String, !text.isEmpty else {
            return className
        }
        return "\(className) \"\(text)\""
    }

    private func recommendedNextTools(likelyCauses: [[String: Any]], regionSummaries: [[String: Any]]) -> [String] {
        if likelyCauses.isEmpty && regionSummaries.isEmpty {
            return ["compare_screenshot"]
        }
        if likelyCauses.isEmpty {
            return ["capture_hierarchy", "find_nodes", "compare_screenshot"]
        }
        return ["inspect_node", "check_style", "check_layout", "compare_screenshot"]
    }

    private func followUpCommands(appId: String?, likelyCauses: [[String: Any]]) -> [[String: Any]] {
        guard let appId, !appId.isEmpty else {
            return []
        }
        return likelyCauses.prefix(5).flatMap { node in
            commands(appId: appId, node: node)
        }
    }

    private func commands(appId: String, node: [String: Any]) -> [[String: Any]] {
        guard let oid = nodeIdentifier(from: node["oid"]) else {
            return []
        }
        let detailOid = nodeIdentifier(from: node["detailOid"])

        var commands: [[String: Any]] = [
            [
                "tool": "inspect_node",
                "reason": "Read the suspected node's runtime frame, text, and attribute details",
                "cliArguments": ["inspect-node", appId, "--oid", oid, "--json"]
            ]
        ]
        if let detailOid {
            commands.append([
                "tool": "summarize_node_detail",
                "reason": "Expand semantic attributes to evaluate color, font, corner-radius, or size differences",
                "cliArguments": ["summarize-node-detail", appId, detailOid, "--json"]
            ])
        }
        return commands
    }

    private func compactComparison(from comparison: [String: Any]) -> [String: Any] {
        [
            "expectedPath": comparison["expectedPath"] ?? NSNull(),
            "actualPath": comparison["actualPath"] ?? NSNull(),
            "diffPath": comparison["diffPath"] ?? NSNull(),
            "threshold": comparison["threshold"] ?? 0,
            "pixelTolerance": comparison["pixelTolerance"] ?? 0,
            "screenshotScale": comparison["screenshotScale"] ?? 1,
            "screenshotSource": comparison["screenshotSource"] ?? "unknown",
            "lowResolution": comparison["lowResolution"] ?? false,
            "baselinePath": comparison["baselinePath"] ?? NSNull(),
            "baselineName": comparison["baselineName"] ?? NSNull(),
            "baselineNodeIndexPath": comparison["baselineNodeIndexPath"] ?? NSNull(),
            "baselineNodeDetailIndexPath": comparison["baselineNodeDetailIndexPath"] ?? NSNull(),
            "dimensions": comparison["dimensions"] ?? [:]
        ]
    }

    private func baselineComparisons(from comparison: [String: Any]) -> [[String: Any]] {
        guard let baselineNodeComparison = comparison["baselineNodeComparison"] as? [String: Any] else {
            return []
        }
        return baselineNodeComparison["comparisons"] as? [[String: Any]] ?? []
    }

    private func enrichedNode(_ node: [String: Any], baselineComparisons: [[String: Any]]) -> [String: Any] {
        guard let comparison = matchingBaselineComparison(for: node, in: baselineComparisons) else {
            return node
        }
        var result = node
        result["baselineMatchStrategy"] = comparison["matchStrategy"] ?? "unknown"
        result["baselineChangeCount"] = comparison["changeCount"] ?? 0
        result["baselineChanges"] = comparison["changes"] ?? []
        result["baselineDetailChangeCount"] = comparison["detailChangeCount"] ?? 0
        result["baselineDetailChanges"] = comparison["detailChanges"] ?? []
        result["baselineSuspectedIssues"] = comparison["suspectedIssues"] ?? []
        result["baselineSummary"] = comparison["summary"] ?? ""
        result["baselineNode"] = comparison["baselineNode"] ?? NSNull()
        return result
    }

    private func matchingBaselineComparison(for node: [String: Any], in comparisons: [[String: Any]]) -> [String: Any]? {
        comparisons.first { comparison in
            guard let currentNode = comparison["currentNode"] as? [String: Any] else {
                return false
            }
            return nodesMatch(lhs: node, rhs: currentNode)
        }
    }

    private func nodesMatch(lhs: [String: Any], rhs: [String: Any]) -> Bool {
        let lhsHierarchyPath = lhs["hierarchyPath"] as? String ?? ""
        let rhsHierarchyPath = rhs["hierarchyPath"] as? String ?? ""
        if !lhsHierarchyPath.isEmpty, lhsHierarchyPath == rhsHierarchyPath {
            return true
        }

        let lhsOid = nodeIdentifier(from: lhs["oid"])
        let rhsOid = nodeIdentifier(from: rhs["oid"])
        if let lhsOid, lhsOid == rhsOid {
            return true
        }

        guard let lhsDetailOid = nodeIdentifier(from: lhs["detailOid"]) else {
            return false
        }
        return lhsDetailOid == nodeIdentifier(from: rhs["detailOid"])
    }

    private func appendBaselineFields(from node: [String: Any], to result: inout [String: Any]) {
        for field in [
            "baselineMatchStrategy",
            "baselineChangeCount",
            "baselineChanges",
            "baselineDetailChangeCount",
            "baselineDetailChanges",
            "baselineNode"
        ] {
            if let value = node[field] {
                result[field] = value
            }
        }
    }

    private func numericValue(from value: Any?) -> Int {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
            return Int(double)
        }
        return 0
    }

    private func nodeIdentifier(from value: Any?) -> String? {
        guard let identifier = value as? String, !identifier.isEmpty else {
            return nil
        }
        return identifier
    }

    private func doubleValue(from value: Any?) -> Double {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        return 0
    }
}
