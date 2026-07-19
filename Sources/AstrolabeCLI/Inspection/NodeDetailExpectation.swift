//
//  NodeDetailExpectation.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct NodeDetailExpectation {
    /// Attribute path, identifier, or displayTitle to match.
    let attribute: String

    /// Expected attribute value preview string.
    let expectedValue: String?

    /// Whether the actual value may contain the expected value.
    let contains: Bool

    /// Tolerance allowed for numeric comparison.
    let tolerance: Double?
}

struct CheckNodeDetailCommand {
    /// Node OID or detailOid whose details should be read.
    let oid: String

    /// Attribute expectation to check.
    let expectation: NodeDetailExpectation
}
