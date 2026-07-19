//
//  ScreenshotIgnoreNodeQueryParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct ScreenshotIgnoreNodeQueryParser {
    func parse(arguments: [String], from startIndex: Int) throws -> (query: HierarchyNodeQuery, nextIndex: Int) {
        var oid: String?
        var className: String?
        var text: String?
        var semanticRole: NodeSemanticRole?
        var visibleOnly = false
        var limit: Int?
        var index = startIndex
        var consumedQueryFlag = false

        while index < arguments.count {
            switch arguments[index] {
            case "--query-oid":
                guard index + 1 < arguments.count,
                      !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("valid --query-oid")
                }
                oid = arguments[index + 1]
                consumedQueryFlag = true
                index += 2
            case "--query-class":
                guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("non-empty --query-class")
                }
                className = arguments[index + 1]
                consumedQueryFlag = true
                index += 2
            case "--query-text":
                guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("non-empty --query-text")
                }
                text = arguments[index + 1]
                consumedQueryFlag = true
                index += 2
            case "--query-role":
                guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("non-empty --query-role")
                }
                semanticRole = try NodeSemanticRole.parse(arguments[index + 1])
                consumedQueryFlag = true
                index += 2
            case "--query-visible-only":
                visibleOnly = true
                consumedQueryFlag = true
                index += 1
            case "--query-limit":
                guard index + 1 < arguments.count,
                      let parsedLimit = Int(arguments[index + 1]),
                      parsedLimit > 0 else {
                    throw CLIError.missingArgument("positive integer --query-limit")
                }
                limit = parsedLimit
                consumedQueryFlag = true
                index += 2
            default:
                let query = HierarchyNodeQuery(
                    oid: oid,
                    className: className,
                    text: text,
                    semanticRole: semanticRole,
                    visibleOnly: visibleOnly,
                    limit: limit
                )
                guard consumedQueryFlag, query.hasSelector else {
                    throw CLIError.missingArgument("--ignore-node-query containing at least one of --query-oid, --query-class, --query-text, or --query-role")
                }
                return (query, index)
            }
        }

        let query = HierarchyNodeQuery(
            oid: oid,
            className: className,
            text: text,
            semanticRole: semanticRole,
            visibleOnly: visibleOnly,
            limit: limit
        )
        guard consumedQueryFlag, query.hasSelector else {
            throw CLIError.missingArgument("--ignore-node-query containing at least one of --query-oid, --query-class, --query-text, or --query-role")
        }
        return (query, index)
    }
}
