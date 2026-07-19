//
//  CaptureHierarchyCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/13.
//

struct CaptureHierarchyCommand {
    /// Maximum number of nodes returned in the hierarchy; nil disables count-based truncation.
    let nodeLimit: Int?

    /// Maximum hierarchy depth, where the root is depth 0; nil disables depth-based truncation.
    let maxDepth: Int?
}

struct CaptureHierarchyCommandParser {
    func parse(arguments: [String]) throws -> CaptureHierarchyCommand {
        var nodeLimit: Int?
        var maxDepth: Int?
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--node-limit":
                guard index + 1 < arguments.count,
                      let value = Int(arguments[index + 1]),
                      (1...HierarchyOutputLimits.maximumCaptureNodeLimit).contains(value) else {
                    throw CLIError.missingArgument("valid node-limit")
                }
                nodeLimit = value
                index += 2
            case "--max-depth":
                guard index + 1 < arguments.count,
                      let value = Int(arguments[index + 1]),
                      value >= 0 else {
                    throw CLIError.missingArgument("valid max-depth")
                }
                maxDepth = value
                index += 2
            case "--json":
                index += 1
            default:
                throw CLIError.unsupportedCommand(arguments[index])
            }
        }

        return CaptureHierarchyCommand(nodeLimit: nodeLimit, maxDepth: maxDepth)
    }
}
