//
//  CheckStyleCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct StyleExpectation {
    /// Style attribute semantic name, semantic path, path, identifier, or title to match.
    let attribute: String

    /// Expected style attribute value.
    let expectedValue: String
}

struct CheckStyleCommand {
    /// Query used to locate the target node.
    let query: HierarchyNodeQuery

    /// Style attribute expectations to check in a batch.
    let expectations: [StyleExpectation]

    /// Whether the actual value may contain the expected value.
    let contains: Bool

    /// Tolerance allowed for numeric comparison.
    let tolerance: Double?
}

struct CheckStyleCommandParser {
    func parse(arguments: [String]) throws -> CheckStyleCommand {
        var oid: String?
        var className: String?
        var text: String?
        var visibleOnly = false
        var expectations: [StyleExpectation] = []
        var contains = false
        var tolerance: Double?
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--oid":
                guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("valid oid")
                }
                oid = arguments[index + 1]
                index += 2
            case "--class":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("className")
                }
                className = arguments[index + 1]
                index += 2
            case "--text":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("text")
                }
                text = arguments[index + 1]
                index += 2
            case "--visible-only":
                visibleOnly = true
                index += 1
            case "--expect":
                guard index + 2 < arguments.count else {
                    throw CLIError.missingArgument("--expect in attribute-value format")
                }
                expectations.append(StyleExpectation(attribute: arguments[index + 1], expectedValue: arguments[index + 2]))
                index += 3
            case "--contains":
                contains = true
                index += 1
            case "--tolerance":
                guard index + 1 < arguments.count, let value = Double(arguments[index + 1]), value >= 0 else {
                    throw CLIError.missingArgument("valid tolerance")
                }
                tolerance = value
                index += 2
            case "--json":
                index += 1
            default:
                throw CLIError.unsupportedCommand(arguments[index])
            }
        }

        guard !expectations.isEmpty else {
            throw CLIError.missingArgument("at least one --expect")
        }

        return CheckStyleCommand(
            query: HierarchyNodeQuery(oid: oid, className: className, text: text, visibleOnly: visibleOnly, limit: nil),
            expectations: expectations,
            contains: contains,
            tolerance: tolerance
        )
    }
}
