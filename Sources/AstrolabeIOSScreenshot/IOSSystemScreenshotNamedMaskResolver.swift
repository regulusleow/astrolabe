//
//  IOSSystemScreenshotNamedMaskResolver.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

import AstrolabeCLI
import Foundation

package struct IOSSystemScreenshotNamedMaskResolver: ScreenshotNamedMaskResolving {
    package init() {}

    package func resolve(
        maskNames: [String],
        imageWidth: Int,
        imageHeight: Int,
        screenshotScale: Double
    ) -> ScreenshotNamedMaskResolution {
        guard !maskNames.isEmpty else {
            return .empty
        }
        guard imageWidth > 0, imageHeight > 0 else {
            return ScreenshotNamedMaskResolution(
                ignoreRegions: [],
                ignoredMaskRegions: [],
                unresolvedMaskNames: maskNames
            )
        }

        let scale = max(screenshotScale, 0.0001)
        var ignoreRegions: [ScreenshotIgnoreRegion] = []
        var ignoredMaskRegions: [[String: Any]] = []
        var unresolvedMaskNames: [String] = []

        for maskName in maskNames {
            guard let resolved = resolvedMask(
                name: maskName,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                scale: scale
            ) else {
                unresolvedMaskNames.append(maskName)
                continue
            }
            ignoreRegions.append(resolved.region)
            ignoredMaskRegions.append([
                "name": resolved.name,
                "requestedName": maskName,
                "ignoreRegion": resolved.region.dictionary
            ])
        }

        return ScreenshotNamedMaskResolution(
            ignoreRegions: ignoreRegions,
            ignoredMaskRegions: ignoredMaskRegions,
            unresolvedMaskNames: unresolvedMaskNames
        )
    }

    private func resolvedMask(
        name: String,
        imageWidth: Int,
        imageHeight: Int,
        scale: Double
    ) -> (name: String, region: ScreenshotIgnoreRegion)? {
        switch normalizedName(from: name) {
        case "statusbar", "topsafearea":
            return ("statusBar", topRegion(width: imageWidth, height: imageHeight, points: 44, scale: scale))
        case "navigationbar", "navibar", "navbar":
            return ("navigationBar", topRegion(width: imageWidth, height: imageHeight, points: 88, scale: scale))
        case "homeindicator", "bottomsafearea":
            return ("homeIndicator", bottomRegion(width: imageWidth, height: imageHeight, points: 34, scale: scale))
        case "tabbar":
            return ("tabBar", bottomRegion(width: imageWidth, height: imageHeight, points: 83, scale: scale))
        default:
            return nil
        }
    }

    private func topRegion(width: Int, height: Int, points: Double, scale: Double) -> ScreenshotIgnoreRegion {
        ScreenshotIgnoreRegion(
            x: 0,
            y: 0,
            width: width,
            height: clampedPixelLength(points: points, scale: scale, limit: height)
        )
    }

    private func bottomRegion(width: Int, height: Int, points: Double, scale: Double) -> ScreenshotIgnoreRegion {
        let pixelHeight = clampedPixelLength(points: points, scale: scale, limit: height)
        return ScreenshotIgnoreRegion(
            x: 0,
            y: max(0, height - pixelHeight),
            width: width,
            height: pixelHeight
        )
    }

    private func clampedPixelLength(points: Double, scale: Double, limit: Int) -> Int {
        min(max(1, Int(ceil(points * scale))), limit)
    }

    private func normalizedName(from name: String) -> String {
        name
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
