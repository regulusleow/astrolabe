//
//  StyleExpectationChecker.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct StyleExpectationChecker {
    private let detailChecker: NodeDetailExpectationChecker

    init(detailChecker: NodeDetailExpectationChecker = NodeDetailExpectationChecker()) {
        self.detailChecker = detailChecker
    }

    func check(summary: [String: Any], node: [String: Any], command: CheckStyleCommand) -> [String: Any] {
        var checks: [[String: Any]] = []
        var failures: [[String: Any]] = []

        for expectation in command.expectations {
            let result = detailChecker.check(
                summary: summary,
                expectation: NodeDetailExpectation(
                    attribute: expectation.attribute,
                    expectedValue: expectation.expectedValue,
                    contains: command.contains,
                    tolerance: command.tolerance
                )
            )
            let attribute = result["attribute"] as? [String: Any]
            let passed = result["passed"] as? Bool ?? false
            checks.append([
                "attribute": expectation.attribute,
                "expected": expectation.expectedValue,
                "actual": actualValue(from: attribute, fallback: result),
                "passed": passed,
                "semanticPath": attribute?["semanticPath"] as? String ?? NSNull()
            ])

            let resultFailures = result["failures"] as? [[String: Any]] ?? []
            for failure in resultFailures {
                var annotatedFailure = failure
                annotatedFailure["attribute"] = expectation.attribute
                failures.append(annotatedFailure)
            }
        }

        return [
            "passed": failures.isEmpty,
            "checkedCount": command.expectations.count,
            "failures": failures,
            "checks": checks,
            "node": node
        ]
    }

    private func actualValue(from attribute: [String: Any]?, fallback result: [String: Any]) -> Any {
        if let colorHex = attribute?["colorHex"] {
            return colorHex
        }
        if let valuePreview = attribute?["valuePreview"] {
            return valuePreview
        }
        if let failure = (result["failures"] as? [[String: Any]])?.first,
           let actual = failure["actual"] {
            return actual
        }
        return NSNull()
    }
}
