//
//  BaselineNodeComparisonWorkflow.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct BaselineNodeComparisonWorkflow {
    private let detailIndexBuilder: BaselineNodeDetailIndexBuilder
    private let comparisonBuilder: BaselineNodeComparisonBuilder

    init(
        detailIndexBuilder: BaselineNodeDetailIndexBuilder = BaselineNodeDetailIndexBuilder(),
        comparisonBuilder: BaselineNodeComparisonBuilder = BaselineNodeComparisonBuilder()
    ) {
        self.detailIndexBuilder = detailIndexBuilder
        self.comparisonBuilder = comparisonBuilder
    }

    func buildComparison(
        appId: String,
        baseline: LoadedBaseline,
        currentNodes: [[String: Any]],
        detailProvider: ([String]) throws -> RuntimeNodeDetailBatch
    ) throws -> [String: Any] {
        let currentNodeDetails: [[String: Any]]
        if baseline.baselineNodeDetails.isEmpty {
            currentNodeDetails = []
        } else {
            let currentNodeDetailIndex = try detailIndexBuilder.buildIndex(
                nodes: currentNodes,
                appId: appId,
                detailProvider: detailProvider
            )
            currentNodeDetails = currentNodeDetailIndex["details"] as? [[String: Any]] ?? []
        }
        return comparisonBuilder.buildComparison(
            appId: appId,
            baselineNodes: baseline.baselineNodes,
            currentNodes: currentNodes,
            baselineNodeDetails: baseline.baselineNodeDetails,
            currentNodeDetails: currentNodeDetails
        )
    }
}
