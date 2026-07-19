//
//  AppCommandGroup.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct AppCommandGroup: CLICommandHandling {
    let supportedCommands = [
        "list-apps",
        "capture-hierarchy"
    ]

    private let service: any RuntimeApplicationDiscovering & RuntimeUIAppDiscoveryDiagnosing
    private let hierarchyResolver: PageHierarchyResolver
    private let snapshotArgumentParser: PageSnapshotArgumentParser
    private let captureHierarchyParser: CaptureHierarchyCommandParser
    private let hierarchyProjectionBuilder: HierarchyProjectionBuilder

    init(
        service: any RuntimeApplicationDiscovering & RuntimeUIAppDiscoveryDiagnosing,
        hierarchyResolver: PageHierarchyResolver,
        snapshotArgumentParser: PageSnapshotArgumentParser = PageSnapshotArgumentParser(),
        captureHierarchyParser: CaptureHierarchyCommandParser = CaptureHierarchyCommandParser(),
        hierarchyProjectionBuilder: HierarchyProjectionBuilder = HierarchyProjectionBuilder()
    ) {
        self.service = service
        self.hierarchyResolver = hierarchyResolver
        self.snapshotArgumentParser = snapshotArgumentParser
        self.captureHierarchyParser = captureHierarchyParser
        self.hierarchyProjectionBuilder = hierarchyProjectionBuilder
    }

    func run(command: String, arguments: [String]) throws -> CLICommandOutput {
        switch command {
        case "list-apps":
            return try runListApps()
        case "capture-hierarchy":
            return try runCaptureHierarchy(arguments: arguments)
        default:
            throw CLIError.unsupportedCommand(command)
        }
    }

    private func runListApps() throws -> CLICommandOutput {
        let apps = try service.fetchApps()
        return .appList(
            CommandResult(
                success: true,
                error: nil,
                data: AppListPayload(
                    apps: apps,
                    diagnostics: service.appDiscoveryDiagnostics()
                ),
                command: "list-apps"
            )
        )
    }

    private func runCaptureHierarchy(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let snapshotArguments = try snapshotArgumentParser.parse(
            arguments: Array(arguments.dropFirst(2))
        )
        let command = try captureHierarchyParser.parse(
            arguments: snapshotArguments.remainingArguments
        )
        let resolvedHierarchy = try hierarchyResolver.resolve(
            appId: arguments[1],
            snapshotIdentifier: snapshotArguments.snapshotIdentifier
        )
        let projection = hierarchyProjectionBuilder.buildProjection(
            from: resolvedHierarchy.snapshot.hierarchy,
            options: HierarchyProjectionOptions(
                nodeLimit: command.nodeLimit,
                maxDepth: command.maxDepth
            )
        )
        return CLICommandResponse.success(
            command: "capture-hierarchy",
            data: resolvedHierarchy.addingMetadata(to: projection)
        )
    }
}
