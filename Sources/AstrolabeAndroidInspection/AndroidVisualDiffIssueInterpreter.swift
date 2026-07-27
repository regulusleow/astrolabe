//
//  AndroidVisualDiffIssueInterpreter.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeCLI

package struct AndroidVisualDiffIssueInterpreter:
    VisualDiffIssueInterpreting {
    package init() {}

    package func interpretation(
        for node: [String: Any],
        suspectedIssues: [String],
        appId: String
    ) -> VisualDiffIssueInterpretation {
        let issues = baselineIssues(from: node).isEmpty
            ? suspectedIssues
            : baselineIssues(from: node)
        let categories = unique(issues.map(category))
        let dominantCategory = categories.first ?? "unknown"
        let fields = changedFields(from: node)
        return VisualDiffIssueInterpretation(
            dominantCategory: dominantCategory,
            issueCategories: categories,
            semanticChangeSummary: fields.isEmpty
                ? ""
                : "\(dominantCategory): \(fields.prefix(4).joined(separator: ", "))",
            reviewHint: reviewHint(
                category: dominantCategory,
                className: node["className"] as? String ?? "Android View",
                fields: fields
            )
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

    package func semanticWeight(
        for node: [String: Any],
        appId: String
    ) -> Double {
        let className = (node["className"] as? String ?? "").lowercased()
        if className.contains("text") || className.contains("button") {
            return 1
        }
        if className.contains("image") || className.contains("compoundbutton") {
            return 0.8
        }
        if className.contains("view") {
            return 0.6
        }
        return 0.4
    }

    package func suspectedIssues(
        for node: [String: Any],
        appId: String
    ) -> [String] {
        let baseline = baselineIssues(from: node)
        guard baseline.isEmpty else {
            return baseline
        }
        let className = (node["className"] as? String ?? "").lowercased()
        if className.contains("text") {
            return [
                "textOrTypographyMismatch",
                "styleMismatchCandidate",
                "layoutMismatchCandidate"
            ]
        }
        if className.contains("image") {
            return ["imageMismatchCandidate", "layoutMismatchCandidate"]
        }
        return ["styleMismatchCandidate", "layoutMismatchCandidate"]
    }

    private func baselineIssues(from node: [String: Any]) -> [String] {
        node["baselineSuspectedIssues"] as? [String] ?? []
    }

    private func category(_ issue: String) -> String {
        let lowercased = issue.lowercased()
        if lowercased.contains("font")
            || lowercased.contains("textcolor")
            || lowercased.contains("typography") {
            return "typography"
        }
        if lowercased.contains("frame")
            || lowercased.contains("layout")
            || lowercased.contains("size") {
            return "layout"
        }
        if lowercased.contains("image") || lowercased.contains("scaletype") {
            return "image"
        }
        if lowercased.contains("control")
            || lowercased.contains("checked")
            || lowercased.contains("interaction") {
            return "controlState"
        }
        if lowercased.contains("background")
            || lowercased.contains("alpha")
            || lowercased.contains("style") {
            return "visualStyle"
        }
        return "unknown"
    }

    private func changedFields(from node: [String: Any]) -> [String] {
        let hierarchyChanges = node["baselineChanges"] as? [[String: Any]] ?? []
        let detailChanges = node["baselineDetailChanges"] as? [[String: Any]] ?? []
        return unique((detailChanges + hierarchyChanges).compactMap {
            $0["field"] as? String
        })
    }

    private func reviewHint(
        category: String,
        className: String,
        fields: [String]
    ) -> String {
        let subject = fields.isEmpty
            ? className
            : "\(className): \(fields.prefix(4).joined(separator: ", "))"
        switch category {
        case "typography":
            return "Check Android text and typography values for \(subject)"
        case "layout":
            return "Check Android layout, spacing, and size values for \(subject)"
        case "image":
            return "Check Android image resource and scaleType for \(subject)"
        case "controlState":
            return "Check Android control state and interaction values for \(subject)"
        case "visualStyle":
            return "Check Android visual style values for \(subject)"
        default:
            return "Check this Android View against the expected UI"
        }
    }

    private func unique(_ values: [String]) -> [String] {
        values.reduce(into: [String]()) { result, value in
            if !result.contains(value) {
                result.append(value)
            }
        }
    }
}
