//
//  UIGraphCommandGroup.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/4.
//

struct UIGraphCommandGroup: CLICommandHandling {
    let supportedCommands = ["query-ui-graph"]

    private let workflow: RuntimeUIGraphQueryWorkflow
    private let snapshotArgumentParser: PageSnapshotArgumentParser
    private let commandParser: RuntimeUIGraphCommandParser

    init(
        hierarchyResolver: PageHierarchyResolver,
        snapshotArgumentParser: PageSnapshotArgumentParser =
            PageSnapshotArgumentParser(),
        commandParser: RuntimeUIGraphCommandParser =
            RuntimeUIGraphCommandParser()
    ) {
        workflow = RuntimeUIGraphQueryWorkflow(
            hierarchyResolver: hierarchyResolver
        )
        self.snapshotArgumentParser = snapshotArgumentParser
        self.commandParser = commandParser
    }

    func run(
        command: String,
        arguments: [String]
    ) throws -> CLICommandOutput {
        guard command == "query-ui-graph" else {
            throw CLIError.unsupportedCommand(command)
        }
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let snapshotArguments = try snapshotArgumentParser.parse(
            arguments: Array(arguments.dropFirst(2))
        )
        guard let snapshotID = snapshotArguments.snapshotIdentifier else {
            throw CLIError.missingArgument("--snapshot-id")
        }
        let graphCommand = try commandParser.parse(
            arguments: snapshotArguments.remainingArguments
        )
        return CLICommandResponse.success(
            command: command,
            data: try workflow.execute(
                appID: arguments[1],
                snapshotID: snapshotID,
                command: graphCommand
            )
        )
    }
}
