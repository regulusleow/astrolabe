//
//  ScreenInspectionCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct ScreenInspectionCommand {
    /// Maximum number of nodes recommended for further inspection.
    let targetLimit: Int

    /// Maximum number of class categories returned in the histogram.
    let classLimit: Int
}

struct ScreenInspectionCommandParser {
    func parse(arguments: [String]) throws -> ScreenInspectionCommand {
        var targetLimit = HierarchyOutputLimits.defaultTargetLimit
        var classLimit = HierarchyOutputLimits.defaultClassLimit
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--target-limit":
                guard index + 1 < arguments.count,
                      let value = Int(arguments[index + 1]),
                      (1...HierarchyOutputLimits.maximumTargetLimit).contains(value) else {
                    throw CLIError.missingArgument("valid target-limit")
                }
                targetLimit = value
                index += 2
            case "--class-limit":
                guard index + 1 < arguments.count,
                      let value = Int(arguments[index + 1]),
                      (1...HierarchyOutputLimits.maximumClassLimit).contains(value) else {
                    throw CLIError.missingArgument("valid class-limit")
                }
                classLimit = value
                index += 2
            case "--json":
                index += 1
            default:
                throw CLIError.unsupportedCommand(arguments[index])
            }
        }

        return ScreenInspectionCommand(
            targetLimit: targetLimit,
            classLimit: classLimit
        )
    }
}
