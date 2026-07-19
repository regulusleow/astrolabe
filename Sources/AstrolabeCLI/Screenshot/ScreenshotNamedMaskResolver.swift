//
//  ScreenshotNamedMaskResolver.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

package struct ScreenshotNamedMaskResolution {
    /// Pixel ignore regions resolved from named masks.
    package let ignoreRegions: [ScreenshotIgnoreRegion]

    /// Descriptions of successfully resolved named masks and pixel regions.
    package let ignoredMaskRegions: [[String: Any]]

    /// Unrecognized named masks.
    package let unresolvedMaskNames: [String]

    package init(
        ignoreRegions: [ScreenshotIgnoreRegion],
        ignoredMaskRegions: [[String: Any]],
        unresolvedMaskNames: [String]
    ) {
        self.ignoreRegions = ignoreRegions
        self.ignoredMaskRegions = ignoredMaskRegions
        self.unresolvedMaskNames = unresolvedMaskNames
    }

    package static var empty: ScreenshotNamedMaskResolution {
        ScreenshotNamedMaskResolution(ignoreRegions: [], ignoredMaskRegions: [], unresolvedMaskNames: [])
    }

    var metadata: [String: Any] {
        [
            "ignoredMaskRegionCount": ignoredMaskRegions.count,
            "ignoredMaskRegions": ignoredMaskRegions,
            "unresolvedIgnoreMasks": unresolvedMaskNames
        ]
    }
}

package protocol ScreenshotNamedMaskResolving {
    func resolve(
        maskNames: [String],
        imageWidth: Int,
        imageHeight: Int,
        screenshotScale: Double
    ) -> ScreenshotNamedMaskResolution
}

struct ScreenshotNamedMaskResolverRegistry {
    private let resolvers: [RuntimeUIPlatform: any ScreenshotNamedMaskResolving]

    init(resolvers: [RuntimeUIPlatform: any ScreenshotNamedMaskResolving]) {
        self.resolvers = resolvers
    }

    func resolve(
        platform: RuntimeUIPlatform,
        maskNames: [String],
        imageWidth: Int,
        imageHeight: Int,
        screenshotScale: Double
    ) -> ScreenshotNamedMaskResolution {
        guard !maskNames.isEmpty else {
            return .empty
        }
        guard let resolver = resolvers[platform] else {
            return ScreenshotNamedMaskResolution(
                ignoreRegions: [],
                ignoredMaskRegions: [],
                unresolvedMaskNames: maskNames
            )
        }
        return resolver.resolve(
            maskNames: maskNames,
            imageWidth: imageWidth,
            imageHeight: imageHeight,
            screenshotScale: screenshotScale
        )
    }
}
