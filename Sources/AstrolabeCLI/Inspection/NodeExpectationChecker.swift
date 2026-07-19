//
//  NodeExpectationChecker.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct NodeExpectationChecker {
    private let extractor: HierarchyNodeExtractor

    init(extractor: HierarchyNodeExtractor = HierarchyNodeExtractor()) {
        self.extractor = extractor
    }

    func check(node: [String: Any], expectation: NodeExpectation) -> [String: Any] {
        var failures: [[String: Any]] = []
        var checkedCount = 0

        if let expected = expectation.className {
            checkedCount += 1
            let actual = node["className"] as? String ?? ""
            appendFailureIfNeeded(
                to: &failures,
                field: "className",
                expected: expected,
                actual: actual,
                passed: actual == expected
            )
        }

        if let expected = expectation.text {
            checkedCount += 1
            let actual = node["text"] as? String ?? ""
            appendFailureIfNeeded(
                to: &failures,
                field: "text",
                expected: expected,
                actual: actual,
                passed: actual == expected
            )
        }

        if let expected = expectation.visible {
            checkedCount += 1
            let actual = node["visible"] as? Bool ?? false
            appendFailureIfNeeded(
                to: &failures,
                field: "visible",
                expected: expected,
                actual: actual,
                passed: actual == expected
            )
        }

        if let frame = expectation.frame {
            let actualFrame = node["frame"] as? [String: Any] ?? [:]
            checkedCount += checkFrame(
                actualFrame: actualFrame,
                expectedFrame: frame,
                tolerance: expectation.tolerance,
                failures: &failures
            )
        }

        return [
            "passed": failures.isEmpty,
            "checkedCount": checkedCount,
            "failures": failures,
            "node": node
        ]
    }

    private func checkFrame(
        actualFrame: [String: Any],
        expectedFrame: FrameExpectation,
        tolerance: Double,
        failures: inout [[String: Any]]
    ) -> Int {
        checkNumber(actualFrame["x"], expected: expectedFrame.x, field: "frame.x", tolerance: tolerance, failures: &failures)
        checkNumber(actualFrame["y"], expected: expectedFrame.y, field: "frame.y", tolerance: tolerance, failures: &failures)
        checkNumber(actualFrame["width"], expected: expectedFrame.width, field: "frame.width", tolerance: tolerance, failures: &failures)
        checkNumber(actualFrame["height"], expected: expectedFrame.height, field: "frame.height", tolerance: tolerance, failures: &failures)
        return 4
    }

    private func checkNumber(
        _ actualValue: Any?,
        expected: Double,
        field: String,
        tolerance: Double,
        failures: inout [[String: Any]]
    ) {
        guard let actual = extractor.numericValue(from: actualValue) else {
            appendFailureIfNeeded(
                to: &failures,
                field: field,
                expected: expected,
                actual: "missing",
                passed: false
            )
            return
        }
        appendFailureIfNeeded(
            to: &failures,
            field: field,
            expected: expected,
            actual: actual,
            passed: abs(actual - expected) <= tolerance
        )
    }

    private func appendFailureIfNeeded(
        to failures: inout [[String: Any]],
        field: String,
        expected: Any,
        actual: Any,
        passed: Bool
    ) {
        guard !passed else {
            return
        }
        failures.append([
            "field": field,
            "expected": expected,
            "actual": actual
        ])
    }
}
