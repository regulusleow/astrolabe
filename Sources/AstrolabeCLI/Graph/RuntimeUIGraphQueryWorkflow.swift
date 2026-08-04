//
//  RuntimeUIGraphQueryWorkflow.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/4.
//

struct RuntimeUIGraphQueryWorkflow {
    private let hierarchyResolver: PageHierarchyResolver
    private let snapshotAdapter: RuntimeUIGraphSnapshotAdapter
    private let indexBuilder: RuntimeUIGraphIndexBuilder
    private let queryEngine: RuntimeUIGraphQueryEngine
    private let projector: RuntimeUIGraphJSONProjector

    init(
        hierarchyResolver: PageHierarchyResolver,
        snapshotAdapter: RuntimeUIGraphSnapshotAdapter =
            RuntimeUIGraphSnapshotAdapter(),
        indexBuilder: RuntimeUIGraphIndexBuilder = RuntimeUIGraphIndexBuilder(),
        queryEngine: RuntimeUIGraphQueryEngine = RuntimeUIGraphQueryEngine(),
        projector: RuntimeUIGraphJSONProjector = RuntimeUIGraphJSONProjector()
    ) {
        self.hierarchyResolver = hierarchyResolver
        self.snapshotAdapter = snapshotAdapter
        self.indexBuilder = indexBuilder
        self.queryEngine = queryEngine
        self.projector = projector
    }

    func execute(
        appID: String,
        snapshotID: String,
        command: RuntimeUIGraphCommand
    ) throws -> [String: Any] {
        let resolvedHierarchy = try hierarchyResolver.resolve(
            appId: appID,
            snapshotIdentifier: snapshotID
        )
        do {
            let input = try snapshotAdapter.adapt(resolvedHierarchy.snapshot)
            let index = try indexBuilder.build(from: input)
            let result = try queryEngine.execute(command.query, in: index)
            return try projector.project(
                query: command.query,
                result: result,
                appID: appID,
                snapshotID: resolvedHierarchy.snapshot.identifier,
                capturedAtUnixTime: resolvedHierarchy.snapshot.createdAt
                    .timeIntervalSince1970,
                hierarchySource: resolvedHierarchy.source,
                byteLimit: command.byteLimit
            )
        } catch let error as RuntimeUIGraphError {
            throw cliError(for: error)
        } catch let error as RuntimeUIGraphProjectionError {
            throw cliError(for: error)
        }
    }

    private func cliError(
        for error: RuntimeUIGraphError
    ) -> CLIError {
        switch error {
        case .capabilityUnavailable:
            return .uiGraphUnavailable
        case .invalidSnapshot, .duplicateNodeIdentifier, .danglingRelation,
             .duplicateRelation:
            return .invalidUIGraphSnapshot
        case .nodeNotFound:
            return .uiGraphNodeNotFound
        case .invalidQuery:
            return .invalidArgument("invalid UI Graph query")
        }
    }

    private func cliError(
        for error: RuntimeUIGraphProjectionError
    ) -> CLIError {
        switch error {
        case .invalidByteLimit:
            return .invalidArgument("invalid UI Graph byte limit")
        case .minimumPayloadExceedsByteLimit:
            return .uiGraphOutputLimitExceeded
        }
    }
}
