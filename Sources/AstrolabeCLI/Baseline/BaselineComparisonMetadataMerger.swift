//
//  BaselineComparisonMetadataMerger.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

import Foundation

enum BaselineComparisonMetadataMerger {
    static func merge(from baseline: LoadedBaseline, into comparison: inout [String: Any]) {
        mergeMaskMetadata(from: baseline, into: &comparison)
        mergeQueryMetadata(from: baseline, into: &comparison)
    }

    private static func mergeMaskMetadata(
        from baseline: LoadedBaseline,
        into comparison: inout [String: Any]
    ) {
        let currentMaskRegions = comparison["ignoredMaskRegions"] as? [[String: Any]] ?? []
        let currentUnresolvedMasks = comparison["unresolvedIgnoreMasks"] as? [String] ?? []
        let ignoredMaskRegions = baseline.ignoredMaskRegions + currentMaskRegions
        let unresolvedIgnoreMasks = baseline.unresolvedIgnoreMasks + currentUnresolvedMasks
        guard !ignoredMaskRegions.isEmpty || !unresolvedIgnoreMasks.isEmpty else {
            return
        }
        comparison["ignoredMaskRegionCount"] = ignoredMaskRegions.count
        comparison["ignoredMaskRegions"] = ignoredMaskRegions
        comparison["unresolvedIgnoreMasks"] = unresolvedIgnoreMasks
    }

    private static func mergeQueryMetadata(
        from baseline: LoadedBaseline,
        into comparison: inout [String: Any]
    ) {
        let currentQueryRegions = comparison["ignoredQueryRegions"] as? [[String: Any]] ?? []
        let currentUnresolvedQueries = comparison["unresolvedIgnoreQueries"] as? [[String: Any]] ?? []
        let ignoredQueryRegions = baseline.ignoredQueryRegions + currentQueryRegions
        let unresolvedIgnoreQueries = baseline.unresolvedIgnoreQueries + currentUnresolvedQueries
        guard !ignoredQueryRegions.isEmpty || !unresolvedIgnoreQueries.isEmpty else {
            return
        }
        comparison["ignoredQueryRegionCount"] = ignoredQueryRegions.count
        comparison["ignoredQueryRegions"] = ignoredQueryRegions
        comparison["unresolvedIgnoreQueries"] = unresolvedIgnoreQueries
    }
}
