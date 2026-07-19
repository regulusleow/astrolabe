//
//  NodeInspectionCommandGroup.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct NodeInspectionCommandGroup: CLICommandHandling {
    let supportedCommands = [
        "node-detail",
        "summarize-node-detail",
        "check-node-detail",
        "summarize-hierarchy",
        "inspect-screen",
        "find-nodes",
        "inspect-node",
        "check-node",
        "check-style",
        "check-layout"
    ]

    private let hierarchyResolver: PageHierarchyResolver
    private let nodeDetailResolver: PageNodeDetailResolver
    private let snapshotArgumentParser: PageSnapshotArgumentParser
    private let summaryBuilder: HierarchySummaryBuilder
    private let nodeFinder: HierarchyNodeFinder
    private let nodeSearchWorkflow: HierarchyNodeSearchWorkflow
    private let findNodesParser: FindNodesCommandParser
    private let checkNodeParser: CheckNodeCommandParser
    private let expectationChecker: NodeExpectationChecker
    private let screenInspectionParser: ScreenInspectionCommandParser
    private let screenInspectionBuilderRegistry: ScreenInspectionBuilderRegistry
    private let nodeDetailSummaryParser: NodeDetailSummaryCommandParser
    private let nodeDetailSummaryBuilder: NodeDetailSummaryBuilder
    private let checkNodeDetailParser: CheckNodeDetailCommandParser
    private let nodeDetailExpectationChecker: NodeDetailExpectationChecker
    private let checkStyleParser: CheckStyleCommandParser
    private let styleExpectationChecker: StyleExpectationChecker
    private let checkLayoutParser: CheckLayoutCommandParser
    private let layoutExpectationChecker: LayoutExpectationChecker

    init(
        summaryBuilder: HierarchySummaryBuilder = HierarchySummaryBuilder(),
        nodeFinder: HierarchyNodeFinder = HierarchyNodeFinder(),
        paginationSnapshotStore: any HierarchyPaginationSnapshotStoring = FileHierarchyPaginationSnapshotStore(),
        hierarchyResolver: PageHierarchyResolver,
        nodeDetailResolver: PageNodeDetailResolver,
        snapshotArgumentParser: PageSnapshotArgumentParser = PageSnapshotArgumentParser(),
        findNodesParser: FindNodesCommandParser = FindNodesCommandParser(),
        checkNodeParser: CheckNodeCommandParser = CheckNodeCommandParser(),
        expectationChecker: NodeExpectationChecker = NodeExpectationChecker(),
        screenInspectionParser: ScreenInspectionCommandParser = ScreenInspectionCommandParser(),
        screenInspectionBuilderRegistry: ScreenInspectionBuilderRegistry,
        nodeDetailSummaryParser: NodeDetailSummaryCommandParser = NodeDetailSummaryCommandParser(),
        nodeDetailSummaryBuilder: NodeDetailSummaryBuilder = NodeDetailSummaryBuilder(),
        checkNodeDetailParser: CheckNodeDetailCommandParser = CheckNodeDetailCommandParser(),
        nodeDetailExpectationChecker: NodeDetailExpectationChecker = NodeDetailExpectationChecker(),
        checkStyleParser: CheckStyleCommandParser = CheckStyleCommandParser(),
        styleExpectationChecker: StyleExpectationChecker = StyleExpectationChecker(),
        checkLayoutParser: CheckLayoutCommandParser = CheckLayoutCommandParser(),
        layoutExpectationChecker: LayoutExpectationChecker = LayoutExpectationChecker()
    ) {
        self.hierarchyResolver = hierarchyResolver
        self.nodeDetailResolver = nodeDetailResolver
        self.snapshotArgumentParser = snapshotArgumentParser
        self.summaryBuilder = summaryBuilder
        self.nodeFinder = nodeFinder
        self.nodeSearchWorkflow = HierarchyNodeSearchWorkflow(
            hierarchyResolver: hierarchyResolver,
            nodeFinder: nodeFinder,
            snapshotStore: paginationSnapshotStore
        )
        self.findNodesParser = findNodesParser
        self.checkNodeParser = checkNodeParser
        self.expectationChecker = expectationChecker
        self.screenInspectionParser = screenInspectionParser
        self.screenInspectionBuilderRegistry = screenInspectionBuilderRegistry
        self.nodeDetailSummaryParser = nodeDetailSummaryParser
        self.nodeDetailSummaryBuilder = nodeDetailSummaryBuilder
        self.checkNodeDetailParser = checkNodeDetailParser
        self.nodeDetailExpectationChecker = nodeDetailExpectationChecker
        self.checkStyleParser = checkStyleParser
        self.styleExpectationChecker = styleExpectationChecker
        self.checkLayoutParser = checkLayoutParser
        self.layoutExpectationChecker = layoutExpectationChecker
    }

    func run(command: String, arguments: [String]) throws -> CLICommandOutput {
        switch command {
        case "node-detail":
            return try runNodeDetail(arguments: arguments)
        case "summarize-node-detail":
            return try runSummarizeNodeDetail(arguments: arguments)
        case "check-node-detail":
            return try runCheckNodeDetail(arguments: arguments)
        case "summarize-hierarchy":
            return try runSummarizeHierarchy(arguments: arguments)
        case "inspect-screen":
            return try runInspectScreen(arguments: arguments)
        case "find-nodes":
            return try runFindNodes(arguments: arguments)
        case "inspect-node":
            return try runInspectNode(arguments: arguments)
        case "check-node":
            return try runCheckNode(arguments: arguments)
        case "check-style":
            return try runCheckStyle(arguments: arguments)
        case "check-layout":
            return try runCheckLayout(arguments: arguments)
        default:
            throw CLIError.unsupportedCommand(command)
        }
    }

    private func runNodeDetail(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 3 else {
            throw CLIError.missingArgument("appId oid")
        }
        let snapshotArguments = try snapshotArgumentParser.parse(
            arguments: Array(arguments.dropFirst(2))
        )
        guard let oid = snapshotArguments.remainingArguments.first,
              !oid.isEmpty else {
            throw CLIError.missingArgument("valid oid")
        }
        let unsupportedArguments = snapshotArguments.remainingArguments
            .dropFirst()
            .filter { $0 != "--json" }
        guard unsupportedArguments.isEmpty else {
            throw CLIError.unsupportedCommand(unsupportedArguments[0])
        }
        let resolvedDetail = try nodeDetailResolver.resolve(
            appId: arguments[1],
            oid: oid,
            snapshotIdentifier: snapshotArguments.snapshotIdentifier
        )
        return CLICommandResponse.success(
            command: "node-detail",
            data: resolvedDetail.addingMetadata(to: resolvedDetail.detail)
        )
    }

    private func runSummarizeNodeDetail(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 3 else {
            throw CLIError.missingArgument("appId oid")
        }
        let appId = arguments[1]
        let snapshotArguments = try snapshotArgumentParser.parse(
            arguments: Array(arguments.dropFirst(2))
        )
        let command = try nodeDetailSummaryParser.parse(
            arguments: snapshotArguments.remainingArguments
        )
        let resolvedDetail = try nodeDetailResolver.resolve(
            appId: appId,
            oid: command.oid,
            snapshotIdentifier: snapshotArguments.snapshotIdentifier
        )
        let result = resolvedDetail.addingMetadata(
                to: nodeDetailSummaryBuilder.buildSummary(
                    from: resolvedDetail.detail,
                    appId: appId,
                    filter: command.filter
                )
        )
        return CLICommandResponse.success(command: "summarize-node-detail", data: result)
    }

    private func runCheckNodeDetail(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 3 else {
            throw CLIError.missingArgument("appId oid")
        }
        let appId = arguments[1]
        let snapshotArguments = try snapshotArgumentParser.parse(
            arguments: Array(arguments.dropFirst(2))
        )
        let command = try checkNodeDetailParser.parse(
            arguments: snapshotArguments.remainingArguments
        )
        let resolvedDetail = try nodeDetailResolver.resolve(
            appId: appId,
            oid: command.oid,
            snapshotIdentifier: snapshotArguments.snapshotIdentifier
        )
        let summary = nodeDetailSummaryBuilder.buildSummary(
            from: resolvedDetail.detail,
            appId: appId
        )
        var result = nodeDetailExpectationChecker.check(summary: summary, expectation: command.expectation)
        result["appId"] = appId
        result["requestedOid"] = command.oid
        result = resolvedDetail.addingMetadata(to: result)
        return CLICommandResponse.success(command: "check-node-detail", data: result)
    }

    private func runSummarizeHierarchy(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let snapshotArguments = try snapshotArgumentParser.parse(
            arguments: Array(arguments.dropFirst(2))
        )
        let resolvedHierarchy = try hierarchyResolver.resolve(
            appId: arguments[1],
            snapshotIdentifier: snapshotArguments.snapshotIdentifier
        )
        return CLICommandResponse.success(
            command: "summarize-hierarchy",
            data: resolvedHierarchy.addingMetadata(
                to: summaryBuilder.buildSummary(from: resolvedHierarchy.snapshot.hierarchy)
            )
        )
    }

    private func runFindNodes(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let snapshotArguments = try snapshotArgumentParser.parse(
            arguments: Array(arguments.dropFirst(2))
        )
        let command = try findNodesParser.parse(arguments: snapshotArguments.remainingArguments)
        return CLICommandResponse.success(
            command: "find-nodes",
            data: try nodeSearchWorkflow.findNodes(
                appId: arguments[1],
                query: command.query,
                cursor: command.cursor,
                snapshotIdentifier: snapshotArguments.snapshotIdentifier
            )
        )
    }

    private func runInspectScreen(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let appId = arguments[1]
        let snapshotArguments = try snapshotArgumentParser.parse(
            arguments: Array(arguments.dropFirst(2))
        )
        let command = try screenInspectionParser.parse(
            arguments: snapshotArguments.remainingArguments
        )
        let resolvedHierarchy = try hierarchyResolver.resolve(
            appId: appId,
            snapshotIdentifier: snapshotArguments.snapshotIdentifier
        )
        let screenInspectionBuilder = try screenInspectionBuilderRegistry.builder(
            for: resolvedHierarchy.snapshot.platform
        )
        return CLICommandResponse.success(
            command: "inspect-screen",
            data: resolvedHierarchy.addingMetadata(
                to: screenInspectionBuilder.buildInspection(
                    from: resolvedHierarchy.snapshot.hierarchy,
                    targetLimit: command.targetLimit,
                    classLimit: command.classLimit
                )
            )
        )
    }

    private func runInspectNode(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let appId = arguments[1]
        let snapshotArguments = try snapshotArgumentParser.parse(
            arguments: Array(arguments.dropFirst(2))
        )
        let command = try findNodesParser.parse(arguments: snapshotArguments.remainingArguments)
        let resolvedHierarchy = try hierarchyResolver.resolve(
            appId: appId,
            snapshotIdentifier: snapshotArguments.snapshotIdentifier
        )
        guard let node = nodeFinder.firstNodeSnapshot(
            in: resolvedHierarchy.snapshot.hierarchy,
            query: command.query
        ) else {
            throw CLIError.nodeNotFound
        }
        guard let detailOid = nodeFinder.detailOid(from: node) else {
            throw CLIError.missingArgument("valid detailOid")
        }
        let resolvedDetail = try nodeDetailResolver.resolve(
            appId: appId,
            oid: detailOid,
            snapshot: resolvedHierarchy.snapshot
        )
        var result = resolvedDetail.addingMetadata(to: [
            "appId": appId,
            "node": node,
            "detail": resolvedDetail.detail
        ])
        result = resolvedHierarchy.addingMetadata(to: result)
        return CLICommandResponse.success(command: "inspect-node", data: result)
    }

    private func runCheckNode(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let appId = arguments[1]
        let snapshotArguments = try snapshotArgumentParser.parse(
            arguments: Array(arguments.dropFirst(2))
        )
        let command = try checkNodeParser.parse(arguments: snapshotArguments.remainingArguments)
        let resolvedHierarchy = try hierarchyResolver.resolve(
            appId: appId,
            snapshotIdentifier: snapshotArguments.snapshotIdentifier
        )
        guard let node = nodeFinder.firstNodeSnapshot(
            in: resolvedHierarchy.snapshot.hierarchy,
            query: command.query
        ) else {
            throw CLIError.nodeNotFound
        }
        var result = expectationChecker.check(node: node, expectation: command.expectation)
        result["appId"] = appId
        return CLICommandResponse.success(
            command: "check-node",
            data: resolvedHierarchy.addingMetadata(to: result)
        )
    }

    private func runCheckStyle(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let appId = arguments[1]
        let snapshotArguments = try snapshotArgumentParser.parse(
            arguments: Array(arguments.dropFirst(2))
        )
        let command = try checkStyleParser.parse(arguments: snapshotArguments.remainingArguments)
        let resolvedHierarchy = try hierarchyResolver.resolve(
            appId: appId,
            snapshotIdentifier: snapshotArguments.snapshotIdentifier
        )
        guard let node = nodeFinder.firstNodeSnapshot(
            in: resolvedHierarchy.snapshot.hierarchy,
            query: command.query
        ) else {
            throw CLIError.nodeNotFound
        }
        guard let detailOid = nodeFinder.detailOid(from: node) else {
            throw CLIError.missingArgument("valid detailOid")
        }
        let resolvedDetail = try nodeDetailResolver.resolve(
            appId: appId,
            oid: detailOid,
            snapshot: resolvedHierarchy.snapshot
        )
        let summary = nodeDetailSummaryBuilder.buildSummary(
            from: resolvedDetail.detail,
            appId: appId
        )
        var result = styleExpectationChecker.check(summary: summary, node: node, command: command)
        result["appId"] = appId
        result["detailOid"] = detailOid
        result = resolvedDetail.addingMetadata(to: result)
        result = resolvedHierarchy.addingMetadata(to: result)
        return CLICommandResponse.success(command: "check-style", data: result)
    }

    private func runCheckLayout(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let appId = arguments[1]
        let snapshotArguments = try snapshotArgumentParser.parse(
            arguments: Array(arguments.dropFirst(2))
        )
        let command = try checkLayoutParser.parse(arguments: snapshotArguments.remainingArguments)
        let resolvedHierarchy = try hierarchyResolver.resolve(
            appId: appId,
            snapshotIdentifier: snapshotArguments.snapshotIdentifier
        )
        var result = try layoutExpectationChecker.check(
            hierarchy: resolvedHierarchy.snapshot.hierarchy,
            command: command
        )
        result["appId"] = appId
        return CLICommandResponse.success(
            command: "check-layout",
            data: resolvedHierarchy.addingMetadata(to: result)
        )
    }
}
