//
//  BaselineCommandGroup.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct BaselineCommandGroup: CLICommandHandling {
    let supportedCommands = [
        "record-baseline",
        "compare-baseline"
    ]

    private let service: any RuntimeUIHierarchyCapturing & RuntimeUINodeDetailProviding & RuntimeUIPlatformResolving
    private let captureWorkflow: ScreenshotCaptureWorkflow
    private let recordParser: BaselineRecordCommandParser
    private let comparisonParser: BaselineComparisonCommandParser
    private let screenshotComparisonParser: ScreenshotComparisonCommandParser
    private let screenshotComparisonBuilder: ScreenshotComparisonBuilder
    private let visualDifferenceNodeMatcher: VisualDifferenceNodeMatcher
    private let ignoreRegionResolver: ScreenshotIgnoreRegionResolver
    private let baselineNodeIndexBuilder: BaselineNodeIndexBuilder
    private let baselineNodeDetailIndexBuilder: BaselineNodeDetailIndexBuilder
    private let baselineStore: UIBaselineStore
    private let baselineNodeComparisonWorkflow: BaselineNodeComparisonWorkflow
    private let namedMaskResolverRegistry: ScreenshotNamedMaskResolverRegistry
    private let queryIgnoreResolver: ScreenshotNodeQueryIgnoreResolver

    init(
        service: any RuntimeUIHierarchyCapturing & RuntimeUINodeDetailProviding & RuntimeUIPlatformResolving,
        captureWorkflow: ScreenshotCaptureWorkflow,
        recordParser: BaselineRecordCommandParser,
        comparisonParser: BaselineComparisonCommandParser = BaselineComparisonCommandParser(),
        screenshotComparisonParser: ScreenshotComparisonCommandParser,
        screenshotComparisonBuilder: ScreenshotComparisonBuilder,
        visualDifferenceNodeMatcher: VisualDifferenceNodeMatcher = VisualDifferenceNodeMatcher(),
        ignoreRegionResolver: ScreenshotIgnoreRegionResolver = ScreenshotIgnoreRegionResolver(),
        baselineNodeIndexBuilder: BaselineNodeIndexBuilder = BaselineNodeIndexBuilder(),
        baselineNodeDetailIndexBuilder: BaselineNodeDetailIndexBuilder = BaselineNodeDetailIndexBuilder(),
        baselineStore: UIBaselineStore = UIBaselineStore(),
        baselineNodeComparisonWorkflow: BaselineNodeComparisonWorkflow = BaselineNodeComparisonWorkflow(),
        namedMaskResolverRegistry: ScreenshotNamedMaskResolverRegistry,
        queryIgnoreResolver: ScreenshotNodeQueryIgnoreResolver = ScreenshotNodeQueryIgnoreResolver()
    ) {
        self.service = service
        self.captureWorkflow = captureWorkflow
        self.recordParser = recordParser
        self.comparisonParser = comparisonParser
        self.screenshotComparisonParser = screenshotComparisonParser
        self.screenshotComparisonBuilder = screenshotComparisonBuilder
        self.visualDifferenceNodeMatcher = visualDifferenceNodeMatcher
        self.ignoreRegionResolver = ignoreRegionResolver
        self.baselineNodeIndexBuilder = baselineNodeIndexBuilder
        self.baselineNodeDetailIndexBuilder = baselineNodeDetailIndexBuilder
        self.baselineStore = baselineStore
        self.baselineNodeComparisonWorkflow = baselineNodeComparisonWorkflow
        self.namedMaskResolverRegistry = namedMaskResolverRegistry
        self.queryIgnoreResolver = queryIgnoreResolver
    }

    func run(command: String, arguments: [String]) throws -> CLICommandOutput {
        switch command {
        case "record-baseline":
            return try runRecordBaseline(arguments: arguments)
        case "compare-baseline":
            return try runCompareBaseline(arguments: arguments)
        default:
            throw CLIError.unsupportedCommand(command)
        }
    }

    private func runRecordBaseline(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let appId = arguments[1]
        let command = try recordParser.parse(
            appId: appId,
            arguments: Array(arguments.dropFirst(2))
        )
        let screenshotPayload = try captureWorkflow.capture(appId: appId, options: command.captureOptions)
        let hierarchy = try service.fetchHierarchy(appId: appId)
        let ignoreResolution = ignoreRegionResolver.resolve(
            hierarchy: hierarchy,
            nodeOids: command.ignoreNodeOids,
            screenshotScale: ScreenshotPayloadMetadata(rawPayload: screenshotPayload).scale
        )
        let dimensions = ScreenshotPayloadMetadata(rawPayload: screenshotPayload).dimensions
            ?? (width: 0, height: 0)
        let maskResolution = namedMaskResolverRegistry.resolve(
            platform: try service.platform(for: appId),
            maskNames: command.ignoreMaskNames,
            imageWidth: dimensions.width,
            imageHeight: dimensions.height,
            screenshotScale: ScreenshotPayloadMetadata(rawPayload: screenshotPayload).scale
        )
        let queryResolution = queryIgnoreResolver.resolve(
            hierarchy: hierarchy,
            queries: command.ignoreNodeQueries,
            screenshotScale: ScreenshotPayloadMetadata(rawPayload: screenshotPayload).scale
        )
        let nodeIndex = baselineNodeIndexBuilder.buildIndex(from: hierarchy)
        let nodeDetailIndex = try baselineNodeDetailIndexBuilder.buildIndex(
            nodes: nodeIndex["nodes"] as? [[String: Any]] ?? [],
            appId: appId,
            detailProvider: { oids in
                try service.fetchNodeDetails(appId: appId, oids: oids)
            }
        )
        let payload = try baselineStore.record(
            appId: appId,
            screenshotPayload: screenshotPayload,
            hierarchy: hierarchy,
            nodeIndex: nodeIndex,
            nodeDetailIndex: nodeDetailIndex,
            command: command.addingIgnoreRegions(ignoreResolution.ignoreRegions + maskResolution.ignoreRegions + queryResolution.ignoreRegions),
            ignoredNodeRegions: ignoreResolution.ignoredNodeRegions,
            ignoredMaskRegions: maskResolution.ignoredMaskRegions,
            unresolvedIgnoreMasks: maskResolution.unresolvedMaskNames,
            ignoredQueryRegions: queryResolution.ignoredQueryRegions,
            unresolvedIgnoreQueries: queryResolution.unresolvedIgnoreQueries
        )
        return CLICommandResponse.success(command: "record-baseline", data: payload)
    }

    private func runCompareBaseline(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let appId = arguments[1]
        let baselineCommand = try comparisonParser.parse(arguments: Array(arguments.dropFirst(2)))
        let baseline = try baselineStore.load(path: baselineCommand.baselinePath)
        let comparisonCommand = try screenshotComparisonParser.parse(
            appId: appId,
            arguments: [
                "--expected",
                baseline.screenshotPath
            ] + ignoreRegionArguments(from: baseline.ignoreRegions) + baselineCommand.comparisonArguments
        )
        let rawPayload = try captureWorkflow.capture(appId: appId, options: comparisonCommand.captureOptions)
        let needsHierarchy = comparisonCommand.includeNodes || !comparisonCommand.ignoreNodeOids.isEmpty || !comparisonCommand.ignoreNodeQueries.isEmpty
        let hierarchy = needsHierarchy ? try service.fetchHierarchy(appId: appId) : nil
        let ignoreResolution: ScreenshotIgnoreRegionResolution
        let queryResolution: ScreenshotNodeQueryIgnoreResolution
        if let hierarchy {
            ignoreResolution = ignoreRegionResolver.resolve(
                hierarchy: hierarchy,
                nodeOids: comparisonCommand.ignoreNodeOids,
                screenshotScale: ScreenshotPayloadMetadata(rawPayload: rawPayload).scale
            )
            queryResolution = queryIgnoreResolver.resolve(
                hierarchy: hierarchy,
                queries: comparisonCommand.ignoreNodeQueries,
                screenshotScale: ScreenshotPayloadMetadata(rawPayload: rawPayload).scale
            )
        } else {
            ignoreResolution = .empty
            queryResolution = .empty
        }
        let resolvedComparisonCommand = comparisonCommand.addingIgnoreRegions(ignoreResolution.ignoreRegions + queryResolution.ignoreRegions)
        var comparison = try screenshotComparisonBuilder.buildComparison(
            platform: try service.platform(for: appId),
            rawPayload: rawPayload,
            command: resolvedComparisonCommand
        )
        let ignoredNodeRegions = baseline.ignoredNodeRegions + ignoreResolution.ignoredNodeRegions
        if !ignoredNodeRegions.isEmpty || !comparisonCommand.ignoreNodeOids.isEmpty {
            comparison["ignoredNodeRegionCount"] = ignoredNodeRegions.count
            comparison["ignoredNodeRegions"] = ignoredNodeRegions
            comparison["unresolvedIgnoreNodeOids"] = ignoreResolution.unresolvedNodeOids.map { Int($0) }
        }
        if !comparisonCommand.ignoreNodeQueries.isEmpty {
            comparison.merge(queryResolution.metadata) { _, new in new }
        }
        if comparisonCommand.includeNodes {
            guard let hierarchy else {
                throw CLIError.invalidJSONObject
            }
            comparison.merge(
                visualDifferenceNodeMatcher.matchAffectedNodes(
                    hierarchy: hierarchy,
                    comparison: comparison,
                    nodeLimit: comparisonCommand.nodeLimit
                )
            ) { _, new in new }
            let currentNodes = comparison["affectedNodes"] as? [[String: Any]] ?? []
            comparison["baselineNodeComparison"] = try baselineNodeComparisonWorkflow.buildComparison(
                appId: appId,
                baseline: baseline,
                currentNodes: currentNodes,
                detailProvider: { oids in
                    try service.fetchNodeDetails(appId: appId, oids: oids)
                }
            )
        }
        comparison["baselinePath"] = baseline.manifestPath
        comparison["baselineName"] = baseline.name
        if let nodeIndexPath = baseline.nodeIndexPath {
            comparison["baselineNodeIndexPath"] = nodeIndexPath
        }
        if let nodeDetailIndexPath = baseline.nodeDetailIndexPath {
            comparison["baselineNodeDetailIndexPath"] = nodeDetailIndexPath
        }
        BaselineComparisonMetadataMerger.merge(from: baseline, into: &comparison)
        return CLICommandResponse.success(command: "compare-baseline", data: comparison)
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
}
