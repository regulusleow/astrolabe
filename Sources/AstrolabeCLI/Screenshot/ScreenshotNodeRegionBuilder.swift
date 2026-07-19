//
//  ScreenshotNodeRegionBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct ScreenshotNodeRegionBuilder {
    private let extractor: HierarchyNodeExtractor

    init(extractor: HierarchyNodeExtractor = HierarchyNodeExtractor()) {
        self.extractor = extractor
    }

    func ignoreRegion(from record: HierarchyNodeRecord, scale: Double) -> ScreenshotIgnoreRegion? {
        ignoreRegion(from: record.node, scale: scale)
    }

    func ignoredRegionMetadata(record: HierarchyNodeRecord, region: ScreenshotIgnoreRegion) -> [String: Any] {
        var snapshot = extractor.nodeSnapshot(from: record)
        snapshot["frameInPixels"] = region.dictionary
        snapshot["ignoreRegion"] = region.dictionary
        return snapshot
    }

    private func ignoreRegion(from node: [String: Any], scale: Double) -> ScreenshotIgnoreRegion? {
        guard let frame = node["frame"] as? [String: Any],
              let x = extractor.numericValue(from: frame["x"]),
              let y = extractor.numericValue(from: frame["y"]),
              let width = extractor.numericValue(from: frame["width"]),
              let height = extractor.numericValue(from: frame["height"]),
              width > 0,
              height > 0 else {
            return nil
        }

        let minX = Int(floor(x * scale))
        let minY = Int(floor(y * scale))
        let maxX = Int(ceil((x + width) * scale))
        let maxY = Int(ceil((y + height) * scale))
        let pixelWidth = max(1, maxX - minX)
        let pixelHeight = max(1, maxY - minY)
        return ScreenshotIgnoreRegion(x: minX, y: minY, width: pixelWidth, height: pixelHeight)
    }
}
