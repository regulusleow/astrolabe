//
//  ScreenshotIgnoreRegionResolver.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct ScreenshotIgnoreRegionResolution {
    /// Pixel ignore regions resolved from node frames.
    let ignoreRegions: [ScreenshotIgnoreRegion]

    /// Descriptions of successfully resolved nodes and pixel regions.
    let ignoredNodeRegions: [[String: Any]]

    /// Node OIDs whose frames could not be resolved from the current hierarchy.
    let unresolvedNodeOids: [String]

    static var empty: ScreenshotIgnoreRegionResolution {
        ScreenshotIgnoreRegionResolution(ignoreRegions: [], ignoredNodeRegions: [], unresolvedNodeOids: [])
    }

    var metadata: [String: Any] {
        [
            "ignoredNodeRegionCount": ignoredNodeRegions.count,
            "ignoredNodeRegions": ignoredNodeRegions,
            "unresolvedIgnoreNodeOids": unresolvedNodeOids
        ]
    }
}

struct ScreenshotIgnoreRegionResolver {
    private let extractor: HierarchyNodeExtractor
    private let regionBuilder: ScreenshotNodeRegionBuilder

    init(
        extractor: HierarchyNodeExtractor = HierarchyNodeExtractor(),
        regionBuilder: ScreenshotNodeRegionBuilder = ScreenshotNodeRegionBuilder()
    ) {
        self.extractor = extractor
        self.regionBuilder = regionBuilder
    }

    func resolve(
        hierarchy: [String: Any],
        nodeOids: [String],
        screenshotScale: Double
    ) -> ScreenshotIgnoreRegionResolution {
        guard !nodeOids.isEmpty else {
            return .empty
        }

        let scale = max(screenshotScale, 0.0001)
        let records = extractor.collectNodeRecords(in: hierarchy)
        var ignoreRegions: [ScreenshotIgnoreRegion] = []
        var ignoredNodeRegions: [[String: Any]] = []
        var unresolvedNodeOids: [String] = []

        for oid in nodeOids {
            guard let record = records.first(where: { self.oid(from: $0.node) == oid }),
                  let region = regionBuilder.ignoreRegion(from: record, scale: scale) else {
                unresolvedNodeOids.append(oid)
                continue
            }
            ignoreRegions.append(region)
            ignoredNodeRegions.append(regionBuilder.ignoredRegionMetadata(record: record, region: region))
        }

        return ScreenshotIgnoreRegionResolution(
            ignoreRegions: ignoreRegions,
            ignoredNodeRegions: ignoredNodeRegions,
            unresolvedNodeOids: unresolvedNodeOids
        )
    }

    private func oid(from node: [String: Any]) -> String? {
        extractor.nodeIdentifier(from: node["oid"])
    }
}
