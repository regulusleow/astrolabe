//
//  NodeExpectation.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct FrameExpectation {
    /// Expected x coordinate.
    let x: Double

    /// Expected y coordinate.
    let y: Double

    /// Expected width.
    let width: Double

    /// Expected height.
    let height: Double
}

struct NodeExpectation {
    /// Expected exact className.
    let className: String?

    /// Expected exact text.
    let text: String?

    /// Expected node visibility.
    let visible: Bool?

    /// Expected frame.
    let frame: FrameExpectation?

    /// Tolerance allowed for numeric comparison.
    let tolerance: Double

    var hasAnyExpectation: Bool {
        className != nil || text != nil || visible != nil || frame != nil
    }
}

struct CheckNodeCommand {
    /// Query used to locate the target node.
    let query: HierarchyNodeQuery

    /// Expectation used to check the target node.
    let expectation: NodeExpectation
}
