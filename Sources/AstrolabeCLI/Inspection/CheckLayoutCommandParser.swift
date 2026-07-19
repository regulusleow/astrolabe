//
//  CheckLayoutCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

enum LayoutRelation: String {
    case verticalSpacing = "vertical-spacing"
    case horizontalSpacing = "horizontal-spacing"
    case sameLeft = "same-left"
    case sameRight = "same-right"
    case sameTop = "same-top"
    case sameBottom = "same-bottom"
    case sameCenterX = "same-center-x"
    case sameCenterY = "same-center-y"
    case sameWidth = "same-width"
    case sameHeight = "same-height"
}

struct CheckLayoutCommand {
    /// Query used to locate the first node.
    let fromQuery: HierarchyNodeQuery

    /// Query used to locate the second node.
    let toQuery: HierarchyNodeQuery

    /// Layout relation to check.
    let relation: LayoutRelation

    /// Expected relation value.
    let expectedValue: Double

    /// Tolerance allowed for numeric comparison.
    let tolerance: Double
}

struct CheckLayoutCommandParser {
    func parse(arguments: [String]) throws -> CheckLayoutCommand {
        var fromOid: String?
        var fromClassName: String?
        var fromText: String?
        var fromVisibleOnly = false
        var toOid: String?
        var toClassName: String?
        var toText: String?
        var toVisibleOnly = false
        var relation: LayoutRelation?
        var expectedValue: Double?
        var tolerance = 0.0
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--from-oid":
                guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("valid from oid")
                }
                fromOid = arguments[index + 1]
                index += 2
            case "--from-class":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("from className")
                }
                fromClassName = arguments[index + 1]
                index += 2
            case "--from-text":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("from text")
                }
                fromText = arguments[index + 1]
                index += 2
            case "--from-visible-only":
                fromVisibleOnly = true
                index += 1
            case "--to-oid":
                guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("valid to oid")
                }
                toOid = arguments[index + 1]
                index += 2
            case "--to-class":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("to className")
                }
                toClassName = arguments[index + 1]
                index += 2
            case "--to-text":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("to text")
                }
                toText = arguments[index + 1]
                index += 2
            case "--to-visible-only":
                toVisibleOnly = true
                index += 1
            case "--relation":
                guard index + 1 < arguments.count, let parsedRelation = LayoutRelation(rawValue: arguments[index + 1]) else {
                    throw CLIError.missingArgument("valid relation")
                }
                relation = parsedRelation
                index += 2
            case "--expect":
                guard index + 1 < arguments.count, let value = Double(arguments[index + 1]) else {
                    throw CLIError.missingArgument("valid expected value")
                }
                expectedValue = value
                index += 2
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

        guard hasSelector(oid: fromOid, className: fromClassName, text: fromText) else {
            throw CLIError.missingArgument("from-node query")
        }
        guard hasSelector(oid: toOid, className: toClassName, text: toText) else {
            throw CLIError.missingArgument("to-node query")
        }
        guard let relation else {
            throw CLIError.missingArgument("--relation")
        }
        guard let expectedValue else {
            throw CLIError.missingArgument("--expect")
        }

        return CheckLayoutCommand(
            fromQuery: HierarchyNodeQuery(oid: fromOid, className: fromClassName, text: fromText, visibleOnly: fromVisibleOnly, limit: nil),
            toQuery: HierarchyNodeQuery(oid: toOid, className: toClassName, text: toText, visibleOnly: toVisibleOnly, limit: nil),
            relation: relation,
            expectedValue: expectedValue,
            tolerance: tolerance
        )
    }

    private func hasSelector(oid: String?, className: String?, text: String?) -> Bool {
        if oid != nil {
            return true
        }
        if let className, !className.isEmpty {
            return true
        }
        if let text, !text.isEmpty {
            return true
        }
        return false
    }
}
