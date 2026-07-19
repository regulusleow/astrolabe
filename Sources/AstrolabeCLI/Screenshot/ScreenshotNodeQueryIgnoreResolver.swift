//
//  ScreenshotNodeQueryIgnoreResolver.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct ScreenshotNodeQueryIgnoreResolution {
    /// Pixel ignore regions resolved from node queries.
    let ignoreRegions: [ScreenshotIgnoreRegion]

    /// Descriptions of successfully resolved node queries and pixel regions.
    let ignoredQueryRegions: [[String: Any]]

    /// Descriptions of node queries that could not resolve to valid ignore regions.
    let unresolvedIgnoreQueries: [[String: Any]]

    static var empty: ScreenshotNodeQueryIgnoreResolution {
        ScreenshotNodeQueryIgnoreResolution(ignoreRegions: [], ignoredQueryRegions: [], unresolvedIgnoreQueries: [])
    }

    var metadata: [String: Any] {
        [
            "ignoredQueryRegionCount": ignoredQueryRegions.count,
            "ignoredQueryRegions": ignoredQueryRegions,
            "unresolvedIgnoreQueries": unresolvedIgnoreQueries
        ]
    }
}

struct ScreenshotNodeQueryIgnoreResolver {
    private let nodeFinder: HierarchyNodeFinder
    private let regionBuilder: ScreenshotNodeRegionBuilder

    init(
        nodeFinder: HierarchyNodeFinder = HierarchyNodeFinder(),
        regionBuilder: ScreenshotNodeRegionBuilder = ScreenshotNodeRegionBuilder()
    ) {
        self.nodeFinder = nodeFinder
        self.regionBuilder = regionBuilder
    }

    func resolve(
        hierarchy: [String: Any],
        queries: [HierarchyNodeQuery],
        screenshotScale: Double
    ) -> ScreenshotNodeQueryIgnoreResolution {
        guard !queries.isEmpty else {
            return .empty
        }

        let scale = max(screenshotScale, 0.0001)
        var ignoreRegions: [ScreenshotIgnoreRegion] = []
        var ignoredQueryRegions: [[String: Any]] = []
        var unresolvedIgnoreQueries: [[String: Any]] = []

        for (queryIndex, query) in queries.enumerated() {
            let records = nodeFinder.findRecords(in: hierarchy, query: query)
            let limit = max(1, query.limit ?? 50)
            let selectedRecords = Array(records.prefix(limit))
            guard !selectedRecords.isEmpty else {
                unresolvedIgnoreQueries.append(unresolvedQuery(query, queryIndex: queryIndex, reason: "noMatchedNode"))
                continue
            }

            let resolvedCountBeforeQuery = ignoreRegions.count
            for (matchIndex, record) in selectedRecords.enumerated() {
                guard let region = regionBuilder.ignoreRegion(from: record, scale: scale) else {
                    continue
                }
                ignoreRegions.append(region)
                ignoredQueryRegions.append(ignoredQueryRegion(
                    record: record,
                    region: region,
                    query: query,
                    queryIndex: queryIndex,
                    matchIndex: matchIndex,
                    totalMatchCount: records.count,
                    limit: limit
                ))
            }

            if ignoreRegions.count == resolvedCountBeforeQuery {
                unresolvedIgnoreQueries.append(unresolvedQuery(query, queryIndex: queryIndex, reason: "matchedNodesHaveNoFrame"))
            }
        }

        return ScreenshotNodeQueryIgnoreResolution(
            ignoreRegions: ignoreRegions,
            ignoredQueryRegions: ignoredQueryRegions,
            unresolvedIgnoreQueries: unresolvedIgnoreQueries
        )
    }

    private func ignoredQueryRegion(
        record: HierarchyNodeRecord,
        region: ScreenshotIgnoreRegion,
        query: HierarchyNodeQuery,
        queryIndex: Int,
        matchIndex: Int,
        totalMatchCount: Int,
        limit: Int
    ) -> [String: Any] {
        var metadata = regionBuilder.ignoredRegionMetadata(record: record, region: region)
        metadata["query"] = query.dictionary
        metadata["queryIndex"] = queryIndex
        metadata["matchIndex"] = matchIndex
        metadata["totalMatchCount"] = totalMatchCount
        metadata["limit"] = limit
        return metadata
    }

    private func unresolvedQuery(_ query: HierarchyNodeQuery, queryIndex: Int, reason: String) -> [String: Any] {
        [
            "query": query.dictionary,
            "queryIndex": queryIndex,
            "reason": reason
        ]
    }
}
