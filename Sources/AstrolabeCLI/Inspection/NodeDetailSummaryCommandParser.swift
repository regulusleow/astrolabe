//
//  NodeDetailSummaryCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct NodeDetailSummaryCommand {
    /// Node OID or detailOid whose details should be read.
    let oid: String

    /// Optional attribute filter keyword.
    let filter: String?
}

struct NodeDetailSummaryCommandParser {
    func parse(arguments: [String]) throws -> NodeDetailSummaryCommand {
        guard let oid = arguments.first, !oid.isEmpty else {
            throw CLIError.missingArgument("valid oid")
        }

        var filter: String?
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--filter":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("filter")
                }
                filter = arguments[index + 1]
                index += 2
            case "--json":
                index += 1
            default:
                throw CLIError.unsupportedCommand(arguments[index])
            }
        }

        return NodeDetailSummaryCommand(oid: oid, filter: filter)
    }
}
