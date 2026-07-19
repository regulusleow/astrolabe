//
//  UIKitVisualDiffIssueInterpreter.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeCLI

package struct UIKitVisualDiffIssueInterpreter: VisualDiffIssueInterpreting {
    package init() {}

    package func interpretation(
        for node: [String: Any],
        suspectedIssues: [String],
        appId: String
    ) -> VisualDiffIssueInterpretation {
        let baselineIssues = node["baselineSuspectedIssues"] as? [String] ?? []
        let categories = issueCategories(from: baselineIssues.isEmpty ? suspectedIssues : baselineIssues)
        let dominantCategory = categories.first ?? "unknown"
        let changedFields = semanticChangedFields(from: node)
        return VisualDiffIssueInterpretation(
            dominantCategory: dominantCategory,
            issueCategories: categories,
            semanticChangeSummary: semanticChangeSummary(category: dominantCategory, fields: changedFields),
            reviewHint: reviewHint(category: dominantCategory, node: node, fields: changedFields)
        )
    }

    package func categoryRank(for category: String, appId: String) -> Int {
        switch category {
        case "layout":
            return 0
        case "typography":
            return 1
        case "visualStyle":
            return 2
        case "controlState":
            return 3
        case "image":
            return 4
        default:
            return 5
        }
    }

    package func semanticWeight(for node: [String: Any], appId: String) -> Double {
        let className = (node["className"] as? String ?? "").lowercased()
        if node["text"] is String || className.contains("label") || className.contains("button") {
            return 1
        }
        if className.contains("image") || className.contains("control") {
            return 0.8
        }
        if className.contains("view") {
            return 0.6
        }
        return 0.4
    }

    package func suspectedIssues(for node: [String: Any], appId: String) -> [String] {
        let className = (node["className"] as? String ?? "").lowercased()
        let baselineIssues = node["baselineSuspectedIssues"] as? [String] ?? []
        let heuristicIssues: [String]
        if node["text"] is String || className.contains("label") {
            heuristicIssues = ["textOrTypographyMismatch", "styleMismatchCandidate", "layoutMismatchCandidate"]
        } else if className.contains("image") {
            heuristicIssues = ["imageMismatchCandidate", "sizeMismatchCandidate", "layoutMismatchCandidate"]
        } else if className.contains("button") || className.contains("control") {
            heuristicIssues = ["controlStateMismatchCandidate", "styleMismatchCandidate", "layoutMismatchCandidate"]
        } else {
            heuristicIssues = ["styleMismatchCandidate", "layoutMismatchCandidate", "sizeMismatchCandidate"]
        }
        return uniqueStrings(baselineIssues + heuristicIssues)
    }

    private func issueCategories(from issues: [String]) -> [String] {
        uniqueStrings(issues.map(category(for:)))
    }

    private func category(for issue: String) -> String {
        switch issue {
        case "fontSizeChanged",
             "fontNameChanged",
             "textColorChanged",
             "textLayoutChanged",
             "attributedTextStyleChanged",
             "textOrTypographyMismatch":
            return "typography"
        case "frameChanged",
             "layoutChanged",
             "layoutInsetChanged",
             "autoLayoutChanged",
             "alignmentChanged",
             "layoutMismatchCandidate",
             "sizeMismatchCandidate":
            return "layout"
        case "backgroundColorChanged",
             "cornerRadiusChanged",
             "borderChanged",
             "shadowChanged",
             "tintColorChanged",
             "tintAdjustmentModeChanged",
             "opacityChanged",
             "clippingChanged",
             "styleMismatchCandidate":
            return "visualStyle"
        case "controlStateChanged",
             "controlStateMismatchCandidate",
             "interactionChanged",
             "outsideEdgeChanged":
            return "controlState"
        case "imageChanged",
             "contentModeChanged",
             "imageMismatchCandidate":
            return "image"
        default:
            return "unknown"
        }
    }

    private func semanticChangedFields(from node: [String: Any]) -> [String] {
        let changes = node["baselineChanges"] as? [[String: Any]] ?? []
        let detailChanges = node["baselineDetailChanges"] as? [[String: Any]] ?? []
        return uniqueStrings((detailChanges + changes).compactMap { $0["field"] as? String })
    }

    private func semanticChangeSummary(category: String, fields: [String]) -> String {
        guard !fields.isEmpty else {
            return category == "unknown" ? "" : "\(category) change candidate"
        }
        return "\(category): \(fields.prefix(4).joined(separator: ", "))"
    }

    private func reviewHint(category: String, node: [String: Any], fields: [String]) -> String {
        let title = nodeTitle(node)
        let fieldList = fields.prefix(4).joined(separator: ", ")
        switch category {
        case "typography":
            return hint("Check typography values", title: title, fields: fieldList)
        case "layout":
            return hint("Check layout, spacing, size, or Auto Layout values", title: title, fields: fieldList)
        case "visualStyle":
            return hint("Check visual style values", title: title, fields: fieldList)
        case "controlState":
            return hint("Check control state and interaction values", title: title, fields: fieldList)
        case "image":
            return hint("Check image asset, preview, or content mode", title: title, fields: fieldList)
        default:
            return hint("Check this node against the expected UI", title: title, fields: fieldList)
        }
    }

    private func hint(_ prefix: String, title: String, fields: String) -> String {
        guard !fields.isEmpty else {
            return "\(prefix) for \(title)"
        }
        return "\(prefix) for \(title): \(fields)"
    }

    private func nodeTitle(_ node: [String: Any]) -> String {
        let className = node["className"] as? String ?? "Unknown"
        guard let text = node["text"] as? String, !text.isEmpty else {
            return className
        }
        return "\(className) \"\(text)\""
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, value in
            guard !result.contains(value) else {
                return
            }
            result.append(value)
        }
    }
}
