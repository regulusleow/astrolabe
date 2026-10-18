//
//  NodeDetailExpectationChecker.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct NodeDetailExpectationChecker {
    func check(summary: [String: Any], expectation: NodeDetailExpectation) -> [String: Any] {
        guard let attribute = matchingAttribute(in: summary, expectation: expectation) else {
            var result: [String: Any] = [
                "passed": false,
                "checkedCount": 1,
                "failures": [
                    [
                        "field": "attribute",
                        "expected": expectation.attribute,
                        "actual": "missing"
                    ]
                ]
            ]
            if summary["semanticContext"] != nil { result["verification"] = "unableToVerify" }
            return result
        }

        guard let expectedValue = expectation.expectedValue else {
            return [
                "passed": true,
                "checkedCount": 1,
                "failures": [],
                "attribute": attribute
            ]
        }

        let actualValues = comparableValues(from: attribute, isSemanticDetail: summary["semanticContext"] != nil)
        let actualValue = actualValues.first ?? ""
        let passed = valueMatches(actualValues: actualValues, expected: expectedValue, expectation: expectation)
        return [
            "passed": passed,
            "checkedCount": 1,
            "failures": passed ? [] : [
                [
                    "field": "value",
                    "expected": expectedValue,
                    "actual": actualValue
                ]
            ],
            "attribute": attribute
        ]
    }

    private func matchingAttribute(in summary: [String: Any], expectation: NodeDetailExpectation) -> [String: Any]? {
        guard let attributes = summary["attributes"] as? [[String: Any]] else {
            return nil
        }

        let query = expectation.attribute.lowercased()
        func candidates(for attribute: [String: Any]) -> [String] {
            [
                attribute["path"],
                attribute["identifier"],
                attribute["displayTitle"],
                attribute["semanticName"],
                attribute["semanticPath"]
            ]
                .compactMap { $0 as? String }
                .map { $0.lowercased() }
        }

        let exactMatches = attributes.filter { attribute in
            candidates(for: attribute).contains(query)
        }
        let matches = exactMatches.isEmpty ? attributes.filter { attribute in
            candidates(for: attribute).contains { $0.contains(query) }
        } : exactMatches
        guard summary["semanticContext"] == nil || matches.count == 1 else { return nil }
        return matches.first
    }

    private func comparableValues(from attribute: [String: Any], isSemanticDetail: Bool) -> [String] {
        var values = [
            attribute["valuePreview"],
            attribute["colorHex"],
            attribute["extraValuePreview"]
        ]
            .compactMap { $0 as? String }
            .filter { !$0.isEmpty }
        if isSemanticDetail,
           attribute["attrTypeName"] as? String == "measurement",
           let measurement = attribute["value"] as? [String: Any],
           let value = measurement["value"] as? NSNumber {
            values.insert(value.stringValue, at: 0)
        }
        return values
    }

    private func valueMatches(actualValues: [String], expected: String, expectation: NodeDetailExpectation) -> Bool {
        if let tolerance = expectation.tolerance,
           let expectedNumber = Double(expected) {
            return actualValues.contains { actualValue in
                guard let actualNumber = Double(actualValue) else {
                    return false
                }
                return abs(actualNumber - expectedNumber) <= tolerance
            }
        }
        if expectation.contains {
            return actualValues.contains { $0.localizedCaseInsensitiveContains(expected) }
        }
        return actualValues.contains { $0.caseInsensitiveCompare(expected) == .orderedSame }
    }
}
