//
//  VisualDiffIssueInterpreting.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

package struct VisualDiffIssueInterpretation {
    /// Most important issue category, used by AI to prioritize the UI diff type.
    package let dominantCategory: String

    /// Deduplicated issue categories.
    package let issueCategories: [String]

    /// Summary of baseline semantic changes.
    package let semanticChangeSummary: String

    /// Suggested next inspection step for UI review.
    package let reviewHint: String

    package init(
        dominantCategory: String,
        issueCategories: [String],
        semanticChangeSummary: String,
        reviewHint: String
    ) {
        self.dominantCategory = dominantCategory
        self.issueCategories = issueCategories
        self.semanticChangeSummary = semanticChangeSummary
        self.reviewHint = reviewHint
    }

    var dictionary: [String: Any] {
        [
            "dominantCategory": dominantCategory,
            "issueCategories": issueCategories,
            "semanticChangeSummary": semanticChangeSummary,
            "reviewHint": reviewHint
        ]
    }
}

package protocol VisualDiffIssueInterpreting {
    func interpretation(
        for node: [String: Any],
        suspectedIssues: [String],
        appId: String
    ) -> VisualDiffIssueInterpretation
    func categoryRank(for category: String, appId: String) -> Int
    func semanticWeight(for node: [String: Any], appId: String) -> Double
    func suspectedIssues(for node: [String: Any], appId: String) -> [String]
}

struct PlatformNeutralVisualDiffIssueInterpreter: VisualDiffIssueInterpreting {
    func interpretation(
        for node: [String: Any],
        suspectedIssues: [String],
        appId: String
    ) -> VisualDiffIssueInterpretation {
        let category = suspectedIssues.first ?? "unknown"
        return VisualDiffIssueInterpretation(
            dominantCategory: category,
            issueCategories: suspectedIssues,
            semanticChangeSummary: "",
            reviewHint: "Check this node against the expected UI"
        )
    }

    func categoryRank(for category: String, appId: String) -> Int {
        0
    }

    func semanticWeight(for node: [String: Any], appId: String) -> Double {
        0.5
    }

    func suspectedIssues(for node: [String: Any], appId: String) -> [String] {
        node["baselineSuspectedIssues"] as? [String] ?? []
    }
}
