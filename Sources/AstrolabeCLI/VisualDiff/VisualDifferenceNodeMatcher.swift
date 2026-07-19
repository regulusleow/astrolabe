//
//  VisualDifferenceNodeMatcher.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct VisualDifferenceNodeMatcher {
    private let extractor: HierarchyNodeExtractor

    init(extractor: HierarchyNodeExtractor = HierarchyNodeExtractor()) {
        self.extractor = extractor
    }

    func matchAffectedNodes(hierarchy: [String: Any], comparison: [String: Any], nodeLimit: Int) -> [String: Any] {
        let regions = regions(from: comparison)
        let coordinateScale = max(extractor.numericValue(from: comparison["screenshotScale"]) ?? 1, 0.0001)
        if regions.isEmpty || nodeLimit == 0 {
            return [
                "affectedNodeCount": 0,
                "omittedAffectedNodeCount": 0,
                "affectedNodes": []
            ]
        }

        let matches = extractor.collectNodeRecords(in: hierarchy)
            .filter { extractor.isVisibleNode($0.node) }
            .compactMap { matchedNode(from: $0, regions: regions, coordinateScale: coordinateScale) }
            .sorted { lhs, rhs in
                let lhsRegion = lhs["regionIndex"] as? Int ?? 0
                let rhsRegion = rhs["regionIndex"] as? Int ?? 0
                if lhsRegion != rhsRegion {
                    return lhsRegion < rhsRegion
                }
                let lhsRegionRatio = lhs["regionOverlapRatio"] as? Double ?? 0
                let rhsRegionRatio = rhs["regionOverlapRatio"] as? Double ?? 0
                if lhsRegionRatio != rhsRegionRatio {
                    return lhsRegionRatio > rhsRegionRatio
                }
                let lhsNodeRatio = lhs["nodeOverlapRatio"] as? Double ?? 0
                let rhsNodeRatio = rhs["nodeOverlapRatio"] as? Double ?? 0
                if lhsNodeRatio != rhsNodeRatio {
                    return lhsNodeRatio > rhsNodeRatio
                }
                let lhsDepth = lhs["depth"] as? Int ?? 0
                let rhsDepth = rhs["depth"] as? Int ?? 0
                if lhsDepth != rhsDepth {
                    return lhsDepth > rhsDepth
                }
                let lhsArea = lhs["overlapArea"] as? Double ?? 0
                let rhsArea = rhs["overlapArea"] as? Double ?? 0
                if lhsArea != rhsArea {
                    return lhsArea > rhsArea
                }
                let lhsOid = extractor.nodeIdentifier(from: lhs["oid"]) ?? ""
                let rhsOid = extractor.nodeIdentifier(from: rhs["oid"]) ?? ""
                return lhsOid < rhsOid
            }

        let returnedMatches = Array(matches.prefix(nodeLimit))
        return [
            "affectedNodeCount": matches.count,
            "omittedAffectedNodeCount": max(0, matches.count - returnedMatches.count),
            "affectedNodes": returnedMatches
        ]
    }

    private func matchedNode(from record: HierarchyNodeRecord, regions: [IndexedRect], coordinateScale: Double) -> [String: Any]? {
        guard let nodeRect = rect(from: record.node["frame"], scale: coordinateScale) else {
            return nil
        }

        var bestRegion: IndexedRect?
        var bestOverlapArea = 0.0
        for region in regions {
            let overlapArea = nodeRect.intersectionArea(with: region.rect)
            if overlapArea > bestOverlapArea {
                bestOverlapArea = overlapArea
                bestRegion = region
            }
        }

        guard let bestRegion, bestOverlapArea > 0 else {
            return nil
        }

        var snapshot = extractor.nodeSnapshot(from: record)
        snapshot["regionIndex"] = bestRegion.index
        snapshot["overlapArea"] = bestOverlapArea
        snapshot["regionOverlapRatio"] = bestRegion.rect.area == 0 ? 0 : bestOverlapArea / bestRegion.rect.area
        snapshot["nodeOverlapRatio"] = nodeRect.area == 0 ? 0 : bestOverlapArea / nodeRect.area
        snapshot["frameInPixels"] = nodeRect.dictionary
        snapshot["matchedRegion"] = bestRegion.rect.dictionary
        return snapshot
    }

    private func regions(from comparison: [String: Any]) -> [IndexedRect] {
        guard let regionDictionaries = comparison["mismatchRegions"] as? [[String: Any]] else {
            return []
        }
        return regionDictionaries.enumerated().compactMap { index, region in
            guard let rect = rect(from: region, scale: 1) else {
                return nil
            }
            return IndexedRect(index: index, rect: rect)
        }
    }

    private func rect(from value: Any?, scale: Double) -> DifferenceRect? {
        guard let dictionary = value as? [String: Any],
              let x = extractor.numericValue(from: dictionary["x"]),
              let y = extractor.numericValue(from: dictionary["y"]),
              let width = extractor.numericValue(from: dictionary["width"]),
              let height = extractor.numericValue(from: dictionary["height"]),
              width > 0,
              height > 0 else {
            return nil
        }
        return DifferenceRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }
}

private struct IndexedRect {
    /// Index of the difference region in mismatchRegions.
    let index: Int

    /// Difference-region rectangle.
    let rect: DifferenceRect
}

private struct DifferenceRect {
    /// Top-left x coordinate.
    let x: Double

    /// Top-left y coordinate.
    let y: Double

    /// Width.
    let width: Double

    /// Height.
    let height: Double

    var maxX: Double {
        x + width
    }

    var maxY: Double {
        y + height
    }

    var area: Double {
        width * height
    }

    var dictionary: [String: Any] {
        [
            "x": x,
            "y": y,
            "width": width,
            "height": height
        ]
    }

    func intersectionArea(with other: DifferenceRect) -> Double {
        let intersectionWidth = max(0, min(maxX, other.maxX) - max(x, other.x))
        let intersectionHeight = max(0, min(maxY, other.maxY) - max(y, other.y))
        return intersectionWidth * intersectionHeight
    }
}
