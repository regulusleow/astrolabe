//
//  LayoutExpectationChecker.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct LayoutExpectationChecker {
    private let finder: HierarchyNodeFinder
    private let extractor: HierarchyNodeExtractor

    init(
        finder: HierarchyNodeFinder = HierarchyNodeFinder(),
        extractor: HierarchyNodeExtractor = HierarchyNodeExtractor()
    ) {
        self.finder = finder
        self.extractor = extractor
    }

    func check(hierarchy: [String: Any], command: CheckLayoutCommand) throws -> [String: Any] {
        guard let fromNode = finder.firstNodeSnapshot(in: hierarchy, query: command.fromQuery),
              let toNode = finder.firstNodeSnapshot(in: hierarchy, query: command.toQuery) else {
            throw CLIError.nodeNotFound
        }
        let fromFrame = try frame(from: fromNode)
        let toFrame = try frame(from: toNode)
        let actual = value(for: command.relation, from: fromFrame, to: toFrame)
        let passed = abs(actual - command.expectedValue) <= command.tolerance

        return [
            "passed": passed,
            "checkedCount": 1,
            "relation": command.relation.rawValue,
            "expected": command.expectedValue,
            "actual": actual,
            "tolerance": command.tolerance,
            "failures": passed ? [] : [
                [
                    "field": command.relation.rawValue,
                    "expected": command.expectedValue,
                    "actual": actual
                ]
            ],
            "fromNode": fromNode,
            "toNode": toNode
        ]
    }

    private func frame(from node: [String: Any]) throws -> LayoutFrame {
        guard let frame = node["frame"] as? [String: Any],
              let x = extractor.numericValue(from: frame["x"]),
              let y = extractor.numericValue(from: frame["y"]),
              let width = extractor.numericValue(from: frame["width"]),
              let height = extractor.numericValue(from: frame["height"]) else {
            throw CLIError.invalidJSONObject
        }
        return LayoutFrame(x: x, y: y, width: width, height: height)
    }

    private func value(for relation: LayoutRelation, from: LayoutFrame, to: LayoutFrame) -> Double {
        switch relation {
        case .verticalSpacing:
            return to.y - from.maxY
        case .horizontalSpacing:
            return to.x - from.maxX
        case .sameLeft:
            return to.x - from.x
        case .sameRight:
            return to.maxX - from.maxX
        case .sameTop:
            return to.y - from.y
        case .sameBottom:
            return to.maxY - from.maxY
        case .sameCenterX:
            return to.centerX - from.centerX
        case .sameCenterY:
            return to.centerY - from.centerY
        case .sameWidth:
            return to.width - from.width
        case .sameHeight:
            return to.height - from.height
        }
    }
}

private struct LayoutFrame {
    /// Top-left x coordinate.
    let x: Double

    /// Top-left y coordinate.
    let y: Double

    /// Width.
    let width: Double

    /// Height.
    let height: Double

    var maxX: Double {
        x + width
    }

    var maxY: Double {
        y + height
    }

    var centerX: Double {
        x + width / 2
    }

    var centerY: Double {
        y + height / 2
    }
}
