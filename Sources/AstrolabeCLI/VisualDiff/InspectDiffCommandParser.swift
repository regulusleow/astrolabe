//
//  InspectDiffCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct InspectDiffCommand {
    /// Optional baseline manifest JSON path.
    let baselinePath: String?

    /// Arguments forwarded to the screenshot comparison parser.
    let comparisonArguments: [String]
}

struct InspectDiffCommandParser {
    func parse(arguments: [String]) throws -> InspectDiffCommand {
        var baselinePath: String?
        var comparisonArguments: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--baseline":
                guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("--baseline path")
                }
                baselinePath = arguments[index + 1]
                index += 2
            default:
                comparisonArguments.append(argument)
                index += 1
            }
        }

        return InspectDiffCommand(baselinePath: baselinePath, comparisonArguments: comparisonArguments)
    }
}
