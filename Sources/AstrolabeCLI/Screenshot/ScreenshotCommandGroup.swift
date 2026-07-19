//
//  ScreenshotCommandGroup.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct ScreenshotCommandGroup: CLICommandHandling {
    let supportedCommands = [
        "capture-screenshot",
        "compare-screenshot",
        "inspect-diff"
    ]

    private let service: any RuntimeUIHierarchyCapturing & RuntimeUINodeDetailProviding & RuntimeUIPlatformResolving
    private let captureWorkflow: ScreenshotCaptureWorkflow
    private let captureParser: ScreenshotCaptureCommandParser
    private let captureResultBuilder: ScreenshotCaptureResultBuilder
    private let comparisonParser: ScreenshotComparisonCommandParser
    private let inspectDiffParser: InspectDiffCommandParser
    private let comparisonBuilder: ScreenshotComparisonBuilder
    private let visualDifferenceNodeMatcher: VisualDifferenceNodeMatcher
    private let visualDiffInspectionBuilder: VisualDiffInspectionBuilder
    private let ignoreRegionResolver: ScreenshotIgnoreRegionResolver
    private let queryIgnoreResolver: ScreenshotNodeQueryIgnoreResolver
    private let baselineStore: UIBaselineStore
    private let baselineNodeComparisonWorkflow: BaselineNodeComparisonWorkflow

    init(
        service: any RuntimeUIHierarchyCapturing & RuntimeUINodeDetailProviding & RuntimeUIPlatformResolving,
        captureWorkflow: ScreenshotCaptureWorkflow,
        captureParser: ScreenshotCaptureCommandParser,
        captureResultBuilder: ScreenshotCaptureResultBuilder = ScreenshotCaptureResultBuilder(),
        comparisonParser: ScreenshotComparisonCommandParser,
        inspectDiffParser: InspectDiffCommandParser = InspectDiffCommandParser(),
        comparisonBuilder: ScreenshotComparisonBuilder,
        visualDifferenceNodeMatcher: VisualDifferenceNodeMatcher = VisualDifferenceNodeMatcher(),
        visualDiffInspectionBuilder: VisualDiffInspectionBuilder = VisualDiffInspectionBuilder(),
        ignoreRegionResolver: ScreenshotIgnoreRegionResolver = ScreenshotIgnoreRegionResolver(),
        queryIgnoreResolver: ScreenshotNodeQueryIgnoreResolver = ScreenshotNodeQueryIgnoreResolver(),
        baselineStore: UIBaselineStore = UIBaselineStore(),
        baselineNodeComparisonWorkflow: BaselineNodeComparisonWorkflow = BaselineNodeComparisonWorkflow()
    ) {
        self.service = service
        self.captureWorkflow = captureWorkflow
        self.captureParser = captureParser
        self.captureResultBuilder = captureResultBuilder
        self.comparisonParser = comparisonParser
        self.inspectDiffParser = inspectDiffParser
        self.comparisonBuilder = comparisonBuilder
        self.visualDifferenceNodeMatcher = visualDifferenceNodeMatcher
        self.visualDiffInspectionBuilder = visualDiffInspectionBuilder
        self.ignoreRegionResolver = ignoreRegionResolver
        self.queryIgnoreResolver = queryIgnoreResolver
        self.baselineStore = baselineStore
        self.baselineNodeComparisonWorkflow = baselineNodeComparisonWorkflow
    }

    func run(command: String, arguments: [String]) throws -> CLICommandOutput {
        switch command {
        case "capture-screenshot":
            return try runCaptureScreenshot(arguments: arguments)
        case "compare-screenshot":
            return try runCompareScreenshot(arguments: arguments)
        case "inspect-diff":
            return try runInspectDiff(arguments: arguments)
        default:
            throw CLIError.unsupportedCommand(command)
        }
    }

    private func runCaptureScreenshot(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let appId = arguments[1]
        let command = try captureParser.parse(
            appId: appId,
            arguments: Array(arguments.dropFirst(2))
        )
        let payload = try captureResultBuilder.buildPayload(
            rawPayload: captureWorkflow.capture(appId: appId, options: command.captureOptions),
            outputPath: command.outputPath
        )
        return CLICommandResponse.success(command: "capture-screenshot", data: payload)
    }

    private func runCompareScreenshot(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let appId = arguments[1]
        let command = try comparisonParser.parse(
            appId: appId,
            arguments: Array(arguments.dropFirst(2))
        )
        let comparison = try buildComparison(appId: appId, command: command)
        return CLICommandResponse.success(command: "compare-screenshot", data: comparison)
    }

    private func runInspectDiff(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let appId = arguments[1]
        let inspectCommand = try inspectDiffParser.parse(arguments: Array(arguments.dropFirst(2)))
        let baseline = try inspectCommand.baselinePath.map { try baselineStore.load(path: $0) }
        let command = try comparisonParser.parse(
            appId: appId,
            arguments: inspectDiffComparisonArguments(
                from: inspectCommand.comparisonArguments,
                baseline: baseline
            )
        ).includingAffectedNodes()
        var comparison = try buildComparison(appId: appId, command: command)
        if let baseline {
            let currentNodes = comparison["affectedNodes"] as? [[String: Any]] ?? []
            comparison["baselineNodeComparison"] = try baselineNodeComparisonWorkflow.buildComparison(
                appId: appId,
                baseline: baseline,
                currentNodes: currentNodes,
                detailProvider: { oids in
                    try service.fetchNodeDetails(appId: appId, oids: oids)
                }
            )
            comparison["baselinePath"] = baseline.manifestPath
            comparison["baselineName"] = baseline.name
            if let nodeIndexPath = baseline.nodeIndexPath {
                comparison["baselineNodeIndexPath"] = nodeIndexPath
            }
            if let nodeDetailIndexPath = baseline.nodeDetailIndexPath {
                comparison["baselineNodeDetailIndexPath"] = nodeDetailIndexPath
            }
            BaselineComparisonMetadataMerger.merge(from: baseline, into: &comparison)
        }
        return CLICommandResponse.success(
            command: "inspect-diff",
            data: visualDiffInspectionBuilder.buildInspection(comparison: comparison, appId: appId)
        )
    }

    private func inspectDiffComparisonArguments(from arguments: [String], baseline: LoadedBaseline?) -> [String] {
        guard let baseline else {
            return arguments
        }
        var result = ["--expected", baseline.screenshotPath]
        result.append(contentsOf: ignoreRegionArguments(from: baseline.ignoreRegions))
        result.append(contentsOf: arguments)
        return result
    }

    private func ignoreRegionArguments(from regions: [ScreenshotIgnoreRegion]) -> [String] {
        regions.flatMap { region in
            [
                "--ignore-region",
                "\(region.x)",
                "\(region.y)",
                "\(region.width)",
                "\(region.height)"
            ]
        }
    }

    private func buildComparison(appId: String, command: ScreenshotComparisonCommand) throws -> [String: Any] {
        let rawPayload = try captureWorkflow.capture(appId: appId, options: command.captureOptions)
        let needsHierarchy = command.includeNodes || !command.ignoreNodeOids.isEmpty || !command.ignoreNodeQueries.isEmpty
        let hierarchy = needsHierarchy ? try service.fetchHierarchy(appId: appId) : nil
        let ignoreResolution: ScreenshotIgnoreRegionResolution
        let queryResolution: ScreenshotNodeQueryIgnoreResolution
        if let hierarchy {
            ignoreResolution = ignoreRegionResolver.resolve(
                hierarchy: hierarchy,
                nodeOids: command.ignoreNodeOids,
                screenshotScale: ScreenshotPayloadMetadata(rawPayload: rawPayload).scale
            )
            queryResolution = queryIgnoreResolver.resolve(
                hierarchy: hierarchy,
                queries: command.ignoreNodeQueries,
                screenshotScale: ScreenshotPayloadMetadata(rawPayload: rawPayload).scale
            )
        } else {
            ignoreResolution = .empty
            queryResolution = .empty
        }
        let comparisonCommand = command.addingIgnoreRegions(ignoreResolution.ignoreRegions + queryResolution.ignoreRegions)
        var comparison = try comparisonBuilder.buildComparison(
            platform: try service.platform(for: appId),
            rawPayload: rawPayload,
            command: comparisonCommand
        )
        if !command.ignoreNodeOids.isEmpty {
            comparison.merge(ignoreResolution.metadata) { _, new in new }
        }
        if !command.ignoreNodeQueries.isEmpty {
            comparison.merge(queryResolution.metadata) { _, new in new }
        }
        if command.includeNodes {
            guard let hierarchy else {
                throw CLIError.invalidJSONObject
            }
            comparison.merge(
                visualDifferenceNodeMatcher.matchAffectedNodes(
                    hierarchy: hierarchy,
                    comparison: comparison,
                    nodeLimit: command.nodeLimit
                )
            ) { _, new in new }
        }
        return comparison
    }
}
