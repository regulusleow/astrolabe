//
//  PixelDifferenceAnalyzer.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct PixelDifferenceAnalysis {
    /// Global difference bounds.
    let bounds: [String: Int]?

    /// Connected difference regions.
    let regions: [[String: Any]]

    /// Total number of connected difference regions before truncation.
    let regionCount: Int

    /// Number of difference regions omitted because of the limit.
    let omittedRegionCount: Int
}

struct PixelDifferenceAnalyzer {
    func analyze(mask: [Bool], width: Int, height: Int, regionLimit: Int) -> PixelDifferenceAnalysis {
        guard width > 0, height > 0, mask.contains(true) else {
            return PixelDifferenceAnalysis(bounds: nil, regions: [], regionCount: 0, omittedRegionCount: 0)
        }

        let globalBounds = bounds(for: mask, width: width, height: height)
        let allRegions = connectedRegions(for: mask, width: width, height: height)
            .sorted { lhs, rhs in
                let lhsPixels = lhs["pixelCount"] as? Int ?? 0
                let rhsPixels = rhs["pixelCount"] as? Int ?? 0
                if lhsPixels != rhsPixels {
                    return lhsPixels > rhsPixels
                }
                let lhsY = lhs["y"] as? Int ?? 0
                let rhsY = rhs["y"] as? Int ?? 0
                if lhsY != rhsY {
                    return lhsY < rhsY
                }
                let lhsX = lhs["x"] as? Int ?? 0
                let rhsX = rhs["x"] as? Int ?? 0
                return lhsX < rhsX
            }
        let returnedRegions = Array(allRegions.prefix(regionLimit))

        return PixelDifferenceAnalysis(
            bounds: globalBounds,
            regions: returnedRegions,
            regionCount: allRegions.count,
            omittedRegionCount: max(0, allRegions.count - returnedRegions.count)
        )
    }

    private func bounds(for mask: [Bool], width: Int, height: Int) -> [String: Int] {
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0

        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] {
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            }
        }

        return [
            "x": minX,
            "y": minY,
            "width": maxX - minX + 1,
            "height": maxY - minY + 1
        ]
    }

    private func connectedRegions(for mask: [Bool], width: Int, height: Int) -> [[String: Any]] {
        var visited = [Bool](repeating: false, count: mask.count)
        var regions: [[String: Any]] = []

        for index in mask.indices where mask[index] && !visited[index] {
            regions.append(region(startIndex: index, mask: mask, visited: &visited, width: width, height: height))
        }

        return regions
    }

    private func region(startIndex: Int, mask: [Bool], visited: inout [Bool], width: Int, height: Int) -> [String: Any] {
        var queue = [startIndex]
        var cursor = 0
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var pixelCount = 0
        visited[startIndex] = true

        while cursor < queue.count {
            let index = queue[cursor]
            cursor += 1
            let x = index % width
            let y = index / width
            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
            pixelCount += 1

            for neighbor in neighbors(x: x, y: y, width: width, height: height) {
                if mask[neighbor], !visited[neighbor] {
                    visited[neighbor] = true
                    queue.append(neighbor)
                }
            }
        }

        return [
            "x": minX,
            "y": minY,
            "width": maxX - minX + 1,
            "height": maxY - minY + 1,
            "pixelCount": pixelCount
        ]
    }

    private func neighbors(x: Int, y: Int, width: Int, height: Int) -> [Int] {
        var result: [Int] = []
        if x > 0 {
            result.append(y * width + x - 1)
        }
        if x + 1 < width {
            result.append(y * width + x + 1)
        }
        if y > 0 {
            result.append((y - 1) * width + x)
        }
        if y + 1 < height {
            result.append((y + 1) * width + x)
        }
        return result
    }
}
