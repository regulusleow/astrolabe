//
//  BaselineCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct BaselineRecordCommand {
    /// Baseline output directory.
    let outputDirectory: String

    /// Baseline name used to generate file names.
    let name: String

    /// Reusable screenshot ignore regions recorded in the baseline manifest.
    let ignoreRegions: [ScreenshotIgnoreRegion]

    /// Node OIDs ignored by UI frame while recording the baseline.
    let ignoreNodeOids: [String]

    /// Named screenshot regions ignored while recording the baseline.
    let ignoreMaskNames: [String]

    /// Node queries whose matched frames are ignored while recording the baseline.
    let ignoreNodeQueries: [HierarchyNodeQuery]

    /// Screenshot source configuration.
    let captureOptions: ScreenshotCaptureOptions

    func addingIgnoreRegions(_ additionalRegions: [ScreenshotIgnoreRegion]) -> BaselineRecordCommand {
        BaselineRecordCommand(
            outputDirectory: outputDirectory,
            name: name,
            ignoreRegions: ignoreRegions + additionalRegions,
            ignoreNodeOids: ignoreNodeOids,
            ignoreMaskNames: ignoreMaskNames,
            ignoreNodeQueries: ignoreNodeQueries,
            captureOptions: captureOptions
        )
    }
}

struct BaselineComparisonCommand {
    /// Baseline manifest JSON path.
    let baselinePath: String

    /// Arguments forwarded to the compare-screenshot parser.
    let comparisonArguments: [String]
}

struct BaselineRecordCommandParser {
    private let captureOptionsResolver: ScreenshotCaptureOptionsResolver

    init(captureOptionsResolver: ScreenshotCaptureOptionsResolver) {
        self.captureOptionsResolver = captureOptionsResolver
    }

    func parse(appId: String, arguments: [String]) throws -> BaselineRecordCommand {
        var outputDirectory: String?
        var name = "baseline"
        var sourceParser = ScreenshotCaptureSourceArgumentParser()
        var ignoreRegions: [ScreenshotIgnoreRegion] = []
        var ignoreNodeOids: [String] = []
        var ignoreMaskNames: [String] = []
        var ignoreNodeQueries: [HierarchyNodeQuery] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--json":
                index += 1
            case "--output-dir":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("--output-dir path")
                }
                outputDirectory = arguments[index + 1]
                index += 2
            case "--name":
                guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("non-empty --name")
                }
                name = arguments[index + 1]
                index += 2
            case "--ignore-region":
                ignoreRegions.append(try ScreenshotIgnoreRegion.parse(arguments: arguments, from: index))
                index += 5
            case "--ignore-node-oid":
                guard index + 1 < arguments.count,
                      !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("valid --ignore-node-oid")
                }
                ignoreNodeOids.append(arguments[index + 1])
                index += 2
            case "--ignore-mask":
                guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("non-empty --ignore-mask")
                }
                ignoreMaskNames.append(arguments[index + 1])
                index += 2
            case "--ignore-node-query":
                let parsed = try ScreenshotIgnoreNodeQueryParser().parse(arguments: arguments, from: index + 1)
                ignoreNodeQueries.append(parsed.query)
                index = parsed.nextIndex
            default:
                guard try sourceParser.consume(
                    argument: argument,
                    arguments: arguments,
                    index: &index
                ) else {
                    throw CLIError.unsupportedCommand(argument)
                }
            }
        }

        guard let outputDirectory, !outputDirectory.isEmpty else {
            throw CLIError.missingArgument("--output-dir")
        }
        return BaselineRecordCommand(
            outputDirectory: outputDirectory,
            name: name,
            ignoreRegions: ignoreRegions,
            ignoreNodeOids: ignoreNodeOids,
            ignoreMaskNames: ignoreMaskNames,
            ignoreNodeQueries: ignoreNodeQueries,
            captureOptions: try captureOptionsResolver.resolve(
                appId: appId,
                arguments: sourceParser.arguments
            )
        )
    }
}

struct BaselineComparisonCommandParser {
    func parse(arguments: [String]) throws -> BaselineComparisonCommand {
        var baselinePath: String?
        var comparisonArguments: [String] = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--json":
                index += 1
            case "--baseline":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("--baseline path")
                }
                baselinePath = arguments[index + 1]
                index += 2
            default:
                comparisonArguments.append(argument)
                index += 1
            }
        }

        guard let baselinePath, !baselinePath.isEmpty else {
            throw CLIError.missingArgument("--baseline")
        }
        return BaselineComparisonCommand(baselinePath: baselinePath, comparisonArguments: comparisonArguments)
    }
}
