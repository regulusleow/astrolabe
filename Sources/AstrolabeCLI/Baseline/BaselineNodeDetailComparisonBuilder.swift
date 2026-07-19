//
//  BaselineNodeDetailComparisonBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct BaselineNodeDetailComparisonBuilder {
    private let issueClassifier: any NodeDetailSemanticIssueInterpreting

    init(
        issueClassifier: any NodeDetailSemanticIssueInterpreting =
            PlatformNeutralNodeDetailSemanticIssueInterpreter()
    ) {
        self.issueClassifier = issueClassifier
    }

    func compare(
        appId: String,
        baselineDetail: [String: Any]?,
        currentDetail: [String: Any]?
    ) -> [[String: Any]] {
        guard let baselineAttributes = semanticAttributes(from: baselineDetail),
              let currentAttributes = semanticAttributes(from: currentDetail) else {
            return []
        }

        let semanticNames = Set(baselineAttributes.keys).union(currentAttributes.keys).sorted()
        return semanticNames.compactMap { semanticName in
            change(
                semanticName: semanticName,
                appId: appId,
                baselineAttribute: baselineAttributes[semanticName],
                currentAttribute: currentAttributes[semanticName]
            )
        }
    }

    private func semanticAttributes(from detail: [String: Any]?) -> [String: [String: Any]]? {
        guard let detail else {
            return nil
        }
        return detail["semanticAttributes"] as? [String: [String: Any]]
    }

    private func change(
        semanticName: String,
        appId: String,
        baselineAttribute: [String: Any]?,
        currentAttribute: [String: Any]?
    ) -> [String: Any]? {
        guard let baselineAttribute else {
            return presenceChange(semanticName: semanticName, issue: "semanticAttributeAdded", attribute: currentAttribute)
        }
        guard let currentAttribute else {
            return presenceChange(semanticName: semanticName, issue: "semanticAttributeRemoved", attribute: baselineAttribute)
        }
        guard !valuesMatch(baselineAttribute, currentAttribute) else {
            return nil
        }
        return [
            "field": "semantic.\(semanticName)",
            "issue": issueClassifier.issueName(for: semanticName, appId: appId),
            "semanticName": semanticName,
            "semanticPath": currentAttribute["semanticPath"] ?? baselineAttribute["semanticPath"] ?? NSNull(),
            "expected": comparisonValue(from: baselineAttribute),
            "actual": comparisonValue(from: currentAttribute),
            "expectedPreview": baselineAttribute["valuePreview"] as? String ?? "",
            "actualPreview": currentAttribute["valuePreview"] as? String ?? ""
        ]
    }

    private func presenceChange(semanticName: String, issue: String, attribute: [String: Any]?) -> [String: Any]? {
        guard let attribute else {
            return nil
        }
        return [
            "field": "semantic.\(semanticName)",
            "issue": issue,
            "semanticName": semanticName,
            "semanticPath": attribute["semanticPath"] ?? NSNull(),
            issue == "semanticAttributeAdded" ? "actual" : "expected": comparisonValue(from: attribute),
            issue == "semanticAttributeAdded" ? "actualPreview" : "expectedPreview": attribute["valuePreview"] as? String ?? ""
        ]
    }

    private func valuesMatch(_ baselineAttribute: [String: Any], _ currentAttribute: [String: Any]) -> Bool {
        if let baselineNumber = numericValue(from: baselineAttribute["value"]),
           let currentNumber = numericValue(from: currentAttribute["value"]) {
            return abs(baselineNumber - currentNumber) <= 0.01
        }
        return previewValue(from: baselineAttribute) == previewValue(from: currentAttribute)
    }

    private func previewValue(from attribute: [String: Any]) -> String {
        if let colorHex = attribute["colorHex"] as? String {
            return colorHex
        }
        if let valuePreview = attribute["valuePreview"] as? String {
            return valuePreview
        }
        return String(describing: attribute["value"] ?? NSNull())
    }

    private func comparisonValue(from attribute: [String: Any]) -> Any {
        if let colorHex = attribute["colorHex"] {
            return colorHex
        }
        return attribute["value"] ?? attribute["valuePreview"] ?? NSNull()
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
}
