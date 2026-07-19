//
//  BaselineNodeComparisonBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct BaselineNodeComparisonBuilder {
    private let detailComparisonBuilder: BaselineNodeDetailComparisonBuilder

    init(detailComparisonBuilder: BaselineNodeDetailComparisonBuilder = BaselineNodeDetailComparisonBuilder()) {
        self.detailComparisonBuilder = detailComparisonBuilder
    }

    func buildComparison(
        appId: String,
        baselineNodes: [[String: Any]],
        currentNodes: [[String: Any]],
        baselineNodeDetails: [[String: Any]] = [],
        currentNodeDetails: [[String: Any]] = []
    ) -> [String: Any] {
        var usedBaselineIndexes = Set<Int>()
        let comparisons = currentNodes.map { currentNode in
            comparison(
                for: currentNode,
                appId: appId,
                baselineNodes: baselineNodes,
                baselineNodeDetails: baselineNodeDetails,
                currentNodeDetails: currentNodeDetails,
                usedBaselineIndexes: &usedBaselineIndexes
            )
        }
        let matchedCount = comparisons.filter { $0["matched"] as? Bool == true }.count
        let changedCount = comparisons.filter { ($0["changeCount"] as? Int ?? 0) > 0 }.count
        return [
            "baselineNodeCount": baselineNodes.count,
            "baselineNodeDetailCount": baselineNodeDetails.count,
            "currentNodeDetailCount": currentNodeDetails.count,
            "affectedNodeCount": currentNodes.count,
            "matchedNodeCount": matchedCount,
            "unmatchedAffectedNodeCount": max(0, currentNodes.count - matchedCount),
            "changedNodeCount": changedCount,
            "comparisons": comparisons
        ]
    }

    private func comparison(
        for currentNode: [String: Any],
        appId: String,
        baselineNodes: [[String: Any]],
        baselineNodeDetails: [[String: Any]],
        currentNodeDetails: [[String: Any]],
        usedBaselineIndexes: inout Set<Int>
    ) -> [String: Any] {
        guard let match = matchBaselineNode(
            for: currentNode,
            in: baselineNodes,
            excluding: usedBaselineIndexes
        ) else {
            return [
                "matched": false,
                "matchStrategy": "unmatched",
                "currentNode": compactNode(currentNode),
                "baselineNode": NSNull(),
                "changeCount": 0,
                "changes": [],
                "detailChangeCount": 0,
                "detailChanges": [],
                "suspectedIssues": [],
                "summary": "No baseline node matched \(nodeTitle(currentNode))"
            ]
        }
        usedBaselineIndexes.insert(match.baselineIndex)

        let nodeChanges = changes(from: match.baselineNode, to: currentNode)
        let detailChanges = detailComparisonBuilder.compare(
            appId: appId,
            baselineDetail: matchingDetail(for: match.baselineNode, in: baselineNodeDetails),
            currentDetail: matchingDetail(for: currentNode, in: currentNodeDetails)
        )
        let changes = nodeChanges + detailChanges
        let suspectedIssues = uniqueIssues(from: changes)
        return [
            "matched": true,
            "matchStrategy": match.strategy,
            "currentNode": compactNode(currentNode),
            "baselineNode": compactNode(match.baselineNode),
            "changeCount": changes.count,
            "changes": changes,
            "detailChangeCount": detailChanges.count,
            "detailChanges": detailChanges,
            "suspectedIssues": suspectedIssues,
            "summary": summary(currentNode: currentNode, changes: changes)
        ]
    }

    private func matchBaselineNode(
        for currentNode: [String: Any],
        in baselineNodes: [[String: Any]],
        excluding usedIndexes: Set<Int>
    ) -> BaselineNodeMatch? {
        let hierarchyPath = currentNode["hierarchyPath"] as? String ?? ""
        if !hierarchyPath.isEmpty,
           let match = baselineNodes.enumerated().first(where: { index, node in
               !usedIndexes.contains(index) &&
                   node["hierarchyPath"] as? String == hierarchyPath &&
                   hasCompatibleIdentity(node, currentNode)
           }) {
            return BaselineNodeMatch(
                baselineIndex: match.offset,
                baselineNode: match.element,
                strategy: "hierarchyPath"
            )
        }

        let className = currentNode["className"] as? String ?? ""
        let text = currentNode["text"] as? String ?? ""
        let classAndTextCandidates = baselineNodes
            .enumerated()
            .filter { index, node in
                !usedIndexes.contains(index) &&
                    node["className"] as? String == className &&
                    node["text"] as? String == text
            }
            .map { index, node in
                (
                    index: index,
                    node: node,
                    distance: frameDistance(from: currentNode, to: node)
                )
            }
        if !className.isEmpty,
           !text.isEmpty,
           let match = classAndTextCandidates.min(by: {
               $0.distance < $1.distance
           }) {
            return BaselineNodeMatch(
                baselineIndex: match.index,
                baselineNode: match.node,
                strategy: "classAndText"
            )
        }

        guard !className.isEmpty else {
            return nil
        }
        let candidates = baselineNodes
            .enumerated()
            .filter { index, node in
                !usedIndexes.contains(index) &&
                    node["className"] as? String == className
            }
            .map { index, node in
                (
                    index: index,
                    node: node,
                    distance: frameDistance(from: currentNode, to: node)
                )
            }
        guard let best = candidates.min(by: { $0.distance < $1.distance }),
              best.distance.isFinite else {
            return nil
        }
        return BaselineNodeMatch(
            baselineIndex: best.index,
            baselineNode: best.node,
            strategy: "classAndFrame"
        )
    }

    private func hasCompatibleIdentity(
        _ baselineNode: [String: Any],
        _ currentNode: [String: Any]
    ) -> Bool {
        let baselineClass = baselineNode["className"] as? String ?? ""
        let currentClass = currentNode["className"] as? String ?? ""
        guard !baselineClass.isEmpty,
              baselineClass == currentClass else {
            return false
        }
        let baselineRoles = Set(baselineNode["semanticRoles"] as? [String] ?? [])
        let currentRoles = Set(currentNode["semanticRoles"] as? [String] ?? [])
        return baselineRoles.isEmpty ||
            currentRoles.isEmpty ||
            !baselineRoles.isDisjoint(with: currentRoles)
    }

    private func matchingDetail(for node: [String: Any], in details: [[String: Any]]) -> [String: Any]? {
        let hierarchyPath = node["hierarchyPath"] as? String ?? ""
        if !hierarchyPath.isEmpty,
           let detail = details.first(where: { $0["hierarchyPath"] as? String == hierarchyPath }) {
            return detail
        }
        if let detailOid = nodeIdentifier(from: node["detailOid"]),
           let detail = details.first(where: { nodeIdentifier(from: $0["detailOid"]) == detailOid }) {
            return detail
        }
        return nil
    }

    private func changes(from baselineNode: [String: Any], to currentNode: [String: Any]) -> [[String: Any]] {
        var changes: [[String: Any]] = []
        appendStringChange(field: "className", issue: "classChanged", baselineNode: baselineNode, currentNode: currentNode, changes: &changes)
        appendStringChange(field: "text", issue: "textChanged", baselineNode: baselineNode, currentNode: currentNode, changes: &changes)
        appendStringChange(field: "backgroundColorHex", issue: "backgroundColorChanged", baselineNode: baselineNode, currentNode: currentNode, changes: &changes)
        appendBoolChange(field: "visible", issue: "visibilityChanged", baselineNode: baselineNode, currentNode: currentNode, changes: &changes)
        appendNumberChange(field: "alpha", issue: "opacityChanged", baselineNode: baselineNode, currentNode: currentNode, tolerance: 0.01, changes: &changes)
        appendFrameChanges(baselineNode: baselineNode, currentNode: currentNode, changes: &changes)
        return changes
    }

    private func appendStringChange(
        field: String,
        issue: String,
        baselineNode: [String: Any],
        currentNode: [String: Any],
        changes: inout [[String: Any]]
    ) {
        let expected = baselineNode[field] as? String ?? ""
        let actual = currentNode[field] as? String ?? ""
        guard expected != actual, !expected.isEmpty || !actual.isEmpty else {
            return
        }
        changes.append([
            "field": field,
            "issue": issue,
            "expected": expected,
            "actual": actual
        ])
    }

    private func appendBoolChange(
        field: String,
        issue: String,
        baselineNode: [String: Any],
        currentNode: [String: Any],
        changes: inout [[String: Any]]
    ) {
        guard let expected = baselineNode[field] as? Bool,
              let actual = currentNode[field] as? Bool,
              expected != actual else {
            return
        }
        changes.append([
            "field": field,
            "issue": issue,
            "expected": expected,
            "actual": actual
        ])
    }

    private func appendNumberChange(
        field: String,
        issue: String,
        baselineNode: [String: Any],
        currentNode: [String: Any],
        tolerance: Double,
        changes: inout [[String: Any]]
    ) {
        guard let expected = numericValue(from: baselineNode[field]),
              let actual = numericValue(from: currentNode[field]),
              abs(actual - expected) > tolerance else {
            return
        }
        changes.append([
            "field": field,
            "issue": issue,
            "expected": expected,
            "actual": actual,
            "delta": actual - expected
        ])
    }

    private func appendFrameChanges(
        baselineNode: [String: Any],
        currentNode: [String: Any],
        changes: inout [[String: Any]]
    ) {
        guard let expectedFrame = baselineNode["frame"] as? [String: Any],
              let actualFrame = currentNode["frame"] as? [String: Any] else {
            return
        }
        for key in ["x", "y", "width", "height"] {
            guard let expected = numericValue(from: expectedFrame[key]),
                  let actual = numericValue(from: actualFrame[key]),
                  abs(actual - expected) > 0.5 else {
                continue
            }
            changes.append([
                "field": "frame.\(key)",
                "issue": "frameChanged",
                "expected": expected,
                "actual": actual,
                "delta": actual - expected
            ])
        }
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
        for field in ["visible", "alpha", "backgroundColorHex"] {
            if let value = node[field] {
                result[field] = value
            }
        }
        return result
    }

    private func summary(currentNode: [String: Any], changes: [[String: Any]]) -> String {
        guard !changes.isEmpty else {
            return "\(nodeTitle(currentNode)) matches baseline node"
        }
        let fields = changes
            .prefix(4)
            .compactMap { $0["field"] as? String }
            .joined(separator: ", ")
        return "\(nodeTitle(currentNode)) differs from baseline: \(fields)"
    }

    private func uniqueIssues(from changes: [[String: Any]]) -> [String] {
        changes.reduce(into: [String]()) { result, change in
            guard let issue = change["issue"] as? String, !result.contains(issue) else {
                return
            }
            result.append(issue)
        }
    }

    private func nodeTitle(_ node: [String: Any]) -> String {
        let className = node["className"] as? String ?? "Unknown"
        guard let text = node["text"] as? String, !text.isEmpty else {
            return className
        }
        return "\(className) \"\(text)\""
    }

    private func frameDistance(from lhs: [String: Any], to rhs: [String: Any]) -> Double {
        guard let lhsFrame = frame(from: lhs),
              let rhsFrame = frame(from: rhs) else {
            return Double.greatestFiniteMagnitude
        }
        let centerDistance = abs(lhsFrame.centerX - rhsFrame.centerX) + abs(lhsFrame.centerY - rhsFrame.centerY)
        let sizeDistance = abs(lhsFrame.width - rhsFrame.width) + abs(lhsFrame.height - rhsFrame.height)
        return centerDistance + sizeDistance
    }

    private func frame(from node: [String: Any]) -> BaselineNodeFrame? {
        guard let frame = node["frame"] as? [String: Any],
              let x = numericValue(from: frame["x"]),
              let y = numericValue(from: frame["y"]),
              let width = numericValue(from: frame["width"]),
              let height = numericValue(from: frame["height"]) else {
            return nil
        }
        return BaselineNodeFrame(x: x, y: y, width: width, height: height)
    }

    private func numericValue(from value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        return nil
    }

    private func nodeIdentifier(from value: Any?) -> String? {
        guard let identifier = value as? String, !identifier.isEmpty else {
            return nil
        }
        return identifier
    }
}

private struct BaselineNodeMatch {
    /// Position of the baseline node in the recorded index.
    let baselineIndex: Int

    /// Matched node snapshot from the baseline.
    let baselineNode: [String: Any]

    /// Match strategy explaining how the current node aligns with the baseline node.
    let strategy: String
}

private struct BaselineNodeFrame {
    /// Top-left x coordinate.
    let x: Double

    /// Top-left y coordinate.
    let y: Double

    /// Node width.
    let width: Double

    /// Node height.
    let height: Double

    var centerX: Double {
        x + width / 2
    }

    var centerY: Double {
        y + height / 2
    }
}
