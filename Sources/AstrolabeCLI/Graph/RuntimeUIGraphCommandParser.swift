//
//  RuntimeUIGraphCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/4.
//

import AstrolabeProtocol

enum RuntimeUIGraphProjectionLimits {
    /// Allowed inclusive compact JSON byte range.
    static let byteCountRange = 1_024 ... 262_144

    /// Default compact JSON byte budget.
    static let defaultByteLimit = 32_768
}

struct RuntimeUIGraphCommand {
    /// Starting node in the frozen page snapshot.
    let rootNodeID: RuntimeOpaqueIdentifier

    /// Open relation identifiers allowed during traversal.
    let relationTypes: Set<RuntimeNamespacedIdentifier>

    /// Direction applied to every traversal hop.
    let direction: RuntimeUIGraphDirection

    /// Maximum BFS hop count.
    let maximumDepth: Int

    /// Maximum returned node count, including the root.
    let nodeLimit: Int

    /// Maximum returned relation count.
    let relationLimit: Int

    /// Maximum compact JSON byte count for the command data object.
    let byteLimit: Int

    var query: RuntimeUIGraphQuery {
        RuntimeUIGraphQuery(
            rootNodeID: rootNodeID,
            relationTypes: relationTypes,
            direction: direction,
            maximumDepth: maximumDepth,
            nodeLimit: nodeLimit,
            relationLimit: relationLimit
        )
    }
}

struct RuntimeUIGraphCommandParser {
    func parse(arguments: [String]) throws -> RuntimeUIGraphCommand {
        var rootNodeID: RuntimeOpaqueIdentifier?
        var relationTypes = Set<RuntimeNamespacedIdentifier>()
        var direction = RuntimeUIGraphDirection.outgoing
        var maximumDepth = 2
        var nodeLimit = 20
        var relationLimit = 30
        var byteLimit = RuntimeUIGraphProjectionLimits.defaultByteLimit
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--root-oid":
                guard index + 1 < arguments.count,
                      let identifier = try? RuntimeOpaqueIdentifier(
                          rawValue: arguments[index + 1]
                      )
                else {
                    throw CLIError.missingArgument("valid root-oid")
                }
                rootNodeID = identifier
                index += 2
            case "--relation":
                guard index + 1 < arguments.count,
                      let relationType = try? RuntimeNamespacedIdentifier(
                          rawValue: arguments[index + 1]
                      )
                else {
                    throw CLIError.missingArgument("valid relation")
                }
                relationTypes.insert(relationType)
                index += 2
            case "--direction":
                guard index + 1 < arguments.count,
                      let value = RuntimeUIGraphDirection(
                          rawValue: arguments[index + 1]
                      )
                else {
                    throw CLIError.missingArgument("valid direction")
                }
                direction = value
                index += 2
            case "--max-depth":
                maximumDepth = try integer(
                    after: index,
                    in: arguments,
                    range: RuntimeUIGraphQueryLimits.maximumDepthRange,
                    name: "valid max-depth"
                )
                index += 2
            case "--node-limit":
                nodeLimit = try integer(
                    after: index,
                    in: arguments,
                    range: RuntimeUIGraphQueryLimits.nodeCountRange,
                    name: "valid node-limit"
                )
                index += 2
            case "--relation-limit":
                relationLimit = try integer(
                    after: index,
                    in: arguments,
                    range: RuntimeUIGraphQueryLimits.relationCountRange,
                    name: "valid relation-limit"
                )
                index += 2
            case "--byte-limit":
                byteLimit = try integer(
                    after: index,
                    in: arguments,
                    range: RuntimeUIGraphProjectionLimits.byteCountRange,
                    name: "valid byte-limit"
                )
                index += 2
            case "--json":
                index += 1
            default:
                throw CLIError.unsupportedCommand(arguments[index])
            }
        }

        guard let rootNodeID else {
            throw CLIError.missingArgument("--root-oid")
        }
        guard !relationTypes.isEmpty else {
            throw CLIError.missingArgument("--relation")
        }
        return RuntimeUIGraphCommand(
            rootNodeID: rootNodeID,
            relationTypes: relationTypes,
            direction: direction,
            maximumDepth: maximumDepth,
            nodeLimit: nodeLimit,
            relationLimit: relationLimit,
            byteLimit: byteLimit
        )
    }

    private func integer(
        after index: Int,
        in arguments: [String],
        range: ClosedRange<Int>,
        name: String
    ) throws -> Int {
        guard index + 1 < arguments.count,
              let value = Int(arguments[index + 1]),
              range.contains(value)
        else {
            throw CLIError.missingArgument(name)
        }
        return value
    }
}
