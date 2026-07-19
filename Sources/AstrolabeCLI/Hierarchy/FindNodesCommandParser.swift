//
//  FindNodesCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct FindNodesCommand {
    /// Node filters and per-page result limit.
    let query: HierarchyNodeQuery

    /// Snapshot validation cursor returned by the previous page.
    let cursor: String?
}

struct FindNodesCommandParser {
    func parse(arguments: [String]) throws -> FindNodesCommand {
        var oid: String?
        var className: String?
        var text: String?
        var semanticRole: NodeSemanticRole?
        var visibleOnly = false
        var limit: Int?
        var cursor: String?
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
            case "--role":
                guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("semantic role")
                }
                semanticRole = try NodeSemanticRole.parse(arguments[index + 1])
                index += 2
            case "--visible-only":
                visibleOnly = true
                index += 1
            case "--limit":
                guard index + 1 < arguments.count,
                      let parsedLimit = Int(arguments[index + 1]),
                      (1...HierarchyOutputLimits.maximumFindNodeLimit).contains(parsedLimit) else {
                    throw CLIError.missingArgument("valid limit")
                }
                limit = parsedLimit
                index += 2
            case "--cursor":
                guard index + 1 < arguments.count,
                      !arguments[index + 1].isEmpty,
                      arguments[index + 1].count <= HierarchyOutputLimits.maximumPaginationCursorLength else {
                    throw CLIError.missingArgument("valid cursor")
                }
                cursor = arguments[index + 1]
                index += 2
            case "--json":
                index += 1
            default:
                throw CLIError.unsupportedCommand(arguments[index])
            }
        }
        return FindNodesCommand(
            query: HierarchyNodeQuery(
                oid: oid,
                className: className,
                text: text,
                semanticRole: semanticRole,
                visibleOnly: visibleOnly,
                limit: limit
            ),
            cursor: cursor
        )
    }
}
