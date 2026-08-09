//
//  CLICommandRunner.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

package struct CLICommandRunner {
    private let commandHandlers: [String: any CLICommandHandling]
    private let closeHandler: () -> Void

    package init(
        platformModules: [HostPlatformModule]
    ) throws {
        try self.init(
            platformModules: platformModules,
            paginationSnapshotStore: nil,
            pageSnapshotStore: nil
        )
    }

    init(
        platformModules: [HostPlatformModule],
        paginationSnapshotStore: (any HierarchyPaginationSnapshotStoring)?,
        pageSnapshotStore: (any PageSnapshotStoring)?
    ) throws {
        let registry = try HostPlatformModuleRegistry(modules: platformModules)
        let modulesByPlatform = registry.modulesByPlatform()
        self.init(
            service: registry,
            screenshotProvider: DefaultScreenshotProvider(
                platformResolver: registry,
                platformProviders: modulesByPlatform.compactMapValues(\.screenshotProvider)
            ),
            paginationSnapshotStore: paginationSnapshotStore,
            pageSnapshotStore: pageSnapshotStore,
            screenshotCaptureOptionsBuilders: modulesByPlatform.compactMapValues(
                \.screenshotOptionsBuilder
            ),
            screenInspectionBuilders: modulesByPlatform.compactMapValues(
                \.screenInspectionBuilder
            ),
            semanticRoleClassifiers: modulesByPlatform.compactMapValues(
                \.semanticRoleClassifier
            ),
            namedMaskResolvers: modulesByPlatform.compactMapValues(\.namedMaskResolver),
            nodeDetailSemanticMapper: HostPlatformNodeDetailSemanticMapper(
                registry: registry
            ),
            nodeDetailIssueInterpreter: HostPlatformNodeDetailIssueInterpreter(
                registry: registry
            ),
            visualDiffIssueInterpreter: HostPlatformVisualDiffIssueInterpreter(
                registry: registry
            ),
            closeHandler: registry.close
        )
    }

    init(
        service: any RuntimeUIInspecting,
        screenshotProvider: ScreenshotProviding,
        screenshotCaptureOptionsBuilders: [
            RuntimeUIPlatform: any ScreenshotCaptureOptionsBuilding
        ],
        screenInspectionBuilders: [
            RuntimeUIPlatform: ScreenInspectionBuilder
        ],
        semanticRoleClassifiers: [
            RuntimeUIPlatform: any NodeSemanticRoleClassifying
        ],
        namedMaskResolvers: [
            RuntimeUIPlatform: any ScreenshotNamedMaskResolving
        ]
    ) {
        self.init(
            service: service,
            screenshotProvider: screenshotProvider,
            paginationSnapshotStore: nil,
            pageSnapshotStore: nil,
            screenshotCaptureOptionsBuilders: screenshotCaptureOptionsBuilders,
            screenInspectionBuilders: screenInspectionBuilders,
            semanticRoleClassifiers: semanticRoleClassifiers,
            namedMaskResolvers: namedMaskResolvers,
            nodeDetailSemanticMapper: PlatformNeutralNodeDetailAttributeSemanticMapper(),
            nodeDetailIssueInterpreter: PlatformNeutralNodeDetailSemanticIssueInterpreter(),
            visualDiffIssueInterpreter: PlatformNeutralVisualDiffIssueInterpreter(),
            closeHandler: {}
        )
    }

    init(
        service: any RuntimeUIInspecting,
        screenshotProvider: ScreenshotProviding,
        paginationSnapshotStore: (any HierarchyPaginationSnapshotStoring)? = nil,
        pageSnapshotStore: (any PageSnapshotStoring)? = nil,
        screenshotCaptureOptionsBuilders: [
            RuntimeUIPlatform: any ScreenshotCaptureOptionsBuilding
        ],
        screenInspectionBuilders: [
            RuntimeUIPlatform: ScreenInspectionBuilder
        ],
        semanticRoleClassifiers: [
            RuntimeUIPlatform: any NodeSemanticRoleClassifying
        ],
        namedMaskResolvers: [
            RuntimeUIPlatform: any ScreenshotNamedMaskResolving
        ],
        nodeDetailSemanticMapper: any NodeDetailAttributeSemanticMapping =
            PlatformNeutralNodeDetailAttributeSemanticMapper(),
        nodeDetailIssueInterpreter: any NodeDetailSemanticIssueInterpreting =
            PlatformNeutralNodeDetailSemanticIssueInterpreter(),
        visualDiffIssueInterpreter: any VisualDiffIssueInterpreting =
            PlatformNeutralVisualDiffIssueInterpreter(),
        closeHandler: @escaping () -> Void = {}
    ) {
        let resolvedService = SemanticRoleAnnotatingRuntimeUIInspector(
            base: service,
            classifiers: semanticRoleClassifiers
        )
        let resolvedPaginationSnapshotStore = paginationSnapshotStore
            ?? FileHierarchyPaginationSnapshotStore()
        let resolvedPageSnapshotStore = pageSnapshotStore
            ?? FilePageSnapshotStore()
        let hierarchyResolver = PageHierarchyResolver(
            service: resolvedService,
            snapshotStore: resolvedPageSnapshotStore
        )
        let nodeDetailResolver = PageNodeDetailResolver(
            service: resolvedService,
            snapshotStore: resolvedPageSnapshotStore
        )
        let captureWorkflow = ScreenshotCaptureWorkflow(
            service: resolvedService,
            screenshotProvider: screenshotProvider
        )
        let captureOptionsResolver = ScreenshotCaptureOptionsResolver(
            platformResolver: resolvedService,
            builders: screenshotCaptureOptionsBuilders
        )
        let namedMaskResolverRegistry = ScreenshotNamedMaskResolverRegistry(
            resolvers: namedMaskResolvers
        )
        let screenshotComparisonBuilder = ScreenshotComparisonBuilder(
            namedMaskResolverRegistry: namedMaskResolverRegistry
        )
        let nodeDetailSummaryBuilder = NodeDetailSummaryBuilder(
            semanticMapper: nodeDetailSemanticMapper
        )
        let baselineNodeDetailIndexBuilder = BaselineNodeDetailIndexBuilder(
            summaryBuilder: nodeDetailSummaryBuilder
        )
        let baselineNodeComparisonWorkflow = BaselineNodeComparisonWorkflow(
            detailIndexBuilder: baselineNodeDetailIndexBuilder,
            comparisonBuilder: BaselineNodeComparisonBuilder(
                detailComparisonBuilder: BaselineNodeDetailComparisonBuilder(
                    issueClassifier: nodeDetailIssueInterpreter
                )
            )
        )
        let handlers: [any CLICommandHandling] = [
            AppCommandGroup(
                service: resolvedService,
                hierarchyResolver: hierarchyResolver
            ),
            UIGraphCommandGroup(
                hierarchyResolver: hierarchyResolver
            ),
            ScreenshotCommandGroup(
                service: resolvedService,
                captureWorkflow: captureWorkflow,
                captureParser: ScreenshotCaptureCommandParser(
                    captureOptionsResolver: captureOptionsResolver
                ),
                comparisonParser: ScreenshotComparisonCommandParser(
                    captureOptionsResolver: captureOptionsResolver
                ),
                comparisonBuilder: screenshotComparisonBuilder,
                visualDiffInspectionBuilder: VisualDiffInspectionBuilder(
                    issueInterpreter: visualDiffIssueInterpreter
                ),
                baselineNodeComparisonWorkflow: baselineNodeComparisonWorkflow
            ),
            BaselineCommandGroup(
                service: resolvedService,
                captureWorkflow: captureWorkflow,
                recordParser: BaselineRecordCommandParser(
                    captureOptionsResolver: captureOptionsResolver
                ),
                screenshotComparisonParser: ScreenshotComparisonCommandParser(
                    captureOptionsResolver: captureOptionsResolver
                ),
                screenshotComparisonBuilder: screenshotComparisonBuilder,
                baselineNodeDetailIndexBuilder: baselineNodeDetailIndexBuilder,
                baselineNodeComparisonWorkflow: baselineNodeComparisonWorkflow,
                namedMaskResolverRegistry: namedMaskResolverRegistry
            ),
            AttributePatchCommandGroup(service: resolvedService),
            NodeInspectionCommandGroup(
                paginationSnapshotStore: resolvedPaginationSnapshotStore,
                hierarchyResolver: hierarchyResolver,
                nodeDetailResolver: nodeDetailResolver,
                screenInspectionBuilderRegistry: ScreenInspectionBuilderRegistry(
                    builders: screenInspectionBuilders
                ),
                nodeDetailSummaryBuilder: nodeDetailSummaryBuilder
            )
        ]
        var commandHandlers: [String: any CLICommandHandling] = [:]
        for handler in handlers {
            for command in handler.supportedCommands {
                precondition(commandHandlers[command] == nil, "Duplicate CLI command handler: \(command)")
                commandHandlers[command] = handler
            }
        }
        self.commandHandlers = commandHandlers
        self.closeHandler = closeHandler
    }

    package func close() {
        closeHandler()
    }

    func run(arguments: [String]) throws -> CLICommandOutput {
        guard let command = arguments.first else {
            throw CLIError.missingCommand
        }

        if command == "version" {
            guard arguments.count == 1 else {
                throw CLIError.invalidArgument("version does not accept arguments")
            }
            return .jsonObject([
                "schemaVersion": CLIOutputSchema.currentVersion,
                "command": "version",
                "success": true,
                "data": ["version": AstrolabeHostMetadata.version]
            ])
        }

        guard let handler = commandHandlers[command] else {
            throw CLIError.unsupportedCommand(command)
        }
        return try handler.run(command: command, arguments: arguments)
    }

    package func runJSON(arguments: [String]) throws -> [String: Any] {
        let output = try run(arguments: arguments)
        guard case .jsonObject(let object) = output else {
            throw CLIError.commandFailed("Command does not produce a JSON object")
        }
        return object
    }

    package func runAndPrint(arguments: [String]) -> Int32 {
        do {
            let output = try run(arguments: arguments)
            try output.print()
            return 0
        } catch {
            NSLog("Failed: \(error)")
            try? JSONOutput.printJSON(CommandResult<EmptyPayload>(
                success: false,
                error: String(describing: error),
                data: nil,
                command: arguments.first,
                errorCode: CLIError.code(for: error),
                recoverySuggestion: CLIError.recoverySuggestion(for: error)
            ))
            return 1
        }
    }
}
