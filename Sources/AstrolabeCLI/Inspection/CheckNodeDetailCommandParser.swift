//
//  CheckNodeDetailCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct CheckNodeDetailCommandParser {
    func parse(arguments: [String]) throws -> CheckNodeDetailCommand {
        guard let oid = arguments.first, !oid.isEmpty else {
            throw CLIError.missingArgument("valid oid")
        }

        var attribute: String?
        var expectedValue: String?
        var contains = false
        var tolerance: Double?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--attribute":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("attribute")
                }
                attribute = arguments[index + 1]
                index += 2
            case "--expect-value":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("expectedValue")
                }
                expectedValue = arguments[index + 1]
                index += 2
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

        guard let attribute, !attribute.isEmpty else {
            throw CLIError.missingArgument("attribute")
        }

        return CheckNodeDetailCommand(
            oid: oid,
            expectation: NodeDetailExpectation(
                attribute: attribute,
                expectedValue: expectedValue,
                contains: contains,
                tolerance: tolerance
            )
        )
    }
}
