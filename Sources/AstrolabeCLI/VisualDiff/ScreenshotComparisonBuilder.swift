//
//  ScreenshotComparisonBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScreenshotComparisonBuilder {
    private let decoder: ScreenshotPayloadDecoder
    private let differenceAnalyzer: PixelDifferenceAnalyzer
    private let namedMaskResolverRegistry: ScreenshotNamedMaskResolverRegistry

    init(
        decoder: ScreenshotPayloadDecoder = ScreenshotPayloadDecoder(),
        differenceAnalyzer: PixelDifferenceAnalyzer = PixelDifferenceAnalyzer(),
        namedMaskResolverRegistry: ScreenshotNamedMaskResolverRegistry
    ) {
        self.decoder = decoder
        self.differenceAnalyzer = differenceAnalyzer
        self.namedMaskResolverRegistry = namedMaskResolverRegistry
    }

    func buildComparison(
        platform: RuntimeUIPlatform,
        rawPayload: [String: Any],
        command: ScreenshotComparisonCommand
    ) throws -> [String: Any] {
        let decodedScreenshot = try decoder.decode(rawPayload: rawPayload)
        let expectedURL = URL(fileURLWithPath: command.expectedPath)
        let expectedData = try Data(contentsOf: expectedURL)
        let actualImage = try pixelImage(from: decodedScreenshot.data)
        let expectedImage = try pixelImage(from: expectedData)
        let screenshotScale = numericValue(from: decodedScreenshot.metadata["scale"]) ?? 1
        let isLowResolution = decodedScreenshot.metadata["lowResolution"] as? Bool ?? false
        let screenshotSource = decodedScreenshot.metadata["source"] as? String ?? "unknown"
        let maskResolution = namedMaskResolverRegistry.resolve(
            platform: platform,
            maskNames: command.ignoreMaskNames,
            imageWidth: actualImage.width,
            imageHeight: actualImage.height,
            screenshotScale: screenshotScale
        )
        let ignoreRegions = command.ignoreRegions + maskResolution.ignoreRegions

        if let actualOutputPath = command.actualOutputPath {
            try write(decodedScreenshot.data, to: actualOutputPath)
        }

        let dimensions = [
            "expected": ["width": expectedImage.width, "height": expectedImage.height],
            "actual": ["width": actualImage.width, "height": actualImage.height]
        ]

        if isLowResolution && !command.allowLowResolution {
            return [
                "passed": false,
                "reason": "lowResolutionScreenshot",
                "expectedPath": expectedURL.path,
                "actualPath": command.actualOutputPath ?? NSNull(),
                "diffPath": command.diffOutputPath ?? NSNull(),
                "threshold": command.threshold,
                "pixelTolerance": command.pixelTolerance,
                "screenshotScale": screenshotScale,
                "screenshotSource": screenshotSource,
                "lowResolution": true,
                "dimensions": dimensions,
                "totalPixels": actualImage.width * actualImage.height,
                "comparedPixels": 0,
                "mismatchPixels": actualImage.width * actualImage.height,
                "mismatchRatio": 1.0,
                "mismatchBounds": NSNull(),
                "mismatchRegions": [],
                "mismatchRegionCount": 0,
                "omittedMismatchRegionCount": 0,
                "ignoredRegionCount": ignoreRegions.count,
                "ignoredPixels": 0,
                "ignoredMaskRegionCount": maskResolution.ignoredMaskRegions.count,
                "ignoredMaskRegions": maskResolution.ignoredMaskRegions,
                "unresolvedIgnoreMasks": maskResolution.unresolvedMaskNames,
                "recoverySuggestion": "Use a high-fidelity screenshot source or pass --allow-low-resolution explicitly"
            ]
        }

        guard actualImage.width == expectedImage.width, actualImage.height == expectedImage.height else {
            return [
                "passed": false,
                "reason": "dimensionMismatch",
                "expectedPath": expectedURL.path,
                "actualPath": command.actualOutputPath ?? NSNull(),
                "diffPath": command.diffOutputPath ?? NSNull(),
                "threshold": command.threshold,
                "pixelTolerance": command.pixelTolerance,
                "screenshotScale": screenshotScale,
                "screenshotSource": screenshotSource,
                "lowResolution": isLowResolution,
                "dimensions": dimensions,
                "totalPixels": max(actualImage.width * actualImage.height, expectedImage.width * expectedImage.height),
                "comparedPixels": 0,
                "mismatchPixels": max(actualImage.width * actualImage.height, expectedImage.width * expectedImage.height),
                "mismatchRatio": 1.0,
                "mismatchBounds": NSNull(),
                "mismatchRegions": [],
                "mismatchRegionCount": 0,
                "omittedMismatchRegionCount": 0,
                "ignoredRegionCount": ignoreRegions.count,
                "ignoredPixels": 0,
                "ignoredMaskRegionCount": maskResolution.ignoredMaskRegions.count,
                "ignoredMaskRegions": maskResolution.ignoredMaskRegions,
                "unresolvedIgnoreMasks": maskResolution.unresolvedMaskNames
            ]
        }

        let result = compare(
            expected: expectedImage,
            actual: actualImage,
            pixelTolerance: command.pixelTolerance,
            regionLimit: command.regionLimit,
            ignoreRegions: ignoreRegions
        )
        if let diffOutputPath = command.diffOutputPath {
            let diffData = try pngData(width: actualImage.width, height: actualImage.height, pixels: result.diffPixels)
            try write(diffData, to: diffOutputPath)
        }

        return [
            "passed": result.mismatchRatio <= command.threshold,
            "reason": result.mismatchRatio <= command.threshold ? "matched" : "pixelMismatch",
            "expectedPath": expectedURL.path,
            "actualPath": command.actualOutputPath ?? NSNull(),
            "diffPath": command.diffOutputPath ?? NSNull(),
            "threshold": command.threshold,
            "pixelTolerance": command.pixelTolerance,
            "screenshotScale": screenshotScale,
            "screenshotSource": screenshotSource,
            "lowResolution": isLowResolution,
            "dimensions": dimensions,
            "totalPixels": result.totalPixels,
            "comparedPixels": result.comparedPixels,
            "mismatchPixels": result.mismatchPixels,
            "mismatchRatio": result.mismatchRatio,
            "mismatchBounds": result.differenceAnalysis.bounds ?? NSNull(),
            "mismatchRegions": result.differenceAnalysis.regions,
            "mismatchRegionCount": result.differenceAnalysis.regionCount,
            "omittedMismatchRegionCount": result.differenceAnalysis.omittedRegionCount,
            "ignoredRegionCount": ignoreRegions.count,
            "ignoredPixels": result.ignoredPixels,
            "ignoredMaskRegionCount": maskResolution.ignoredMaskRegions.count,
            "ignoredMaskRegions": maskResolution.ignoredMaskRegions,
            "unresolvedIgnoreMasks": maskResolution.unresolvedMaskNames
        ]
    }

    private func compare(
        expected: PixelImage,
        actual: PixelImage,
        pixelTolerance: Int,
        regionLimit: Int,
        ignoreRegions: [ScreenshotIgnoreRegion]
    ) -> PixelComparisonResult {
        let totalPixels = actual.width * actual.height
        var mismatchPixels = 0
        var diffPixels = actual.pixels
        var mismatchMask = [Bool](repeating: false, count: totalPixels)
        var ignoredPixels = 0

        for pixelIndex in 0..<totalPixels {
            if isIgnored(pixelIndex: pixelIndex, width: actual.width, regions: ignoreRegions) {
                ignoredPixels += 1
                continue
            }
            let byteIndex = pixelIndex * 4
            let isMatched = (0..<4).allSatisfy { channel in
                abs(Int(expected.pixels[byteIndex + channel]) - Int(actual.pixels[byteIndex + channel])) <= pixelTolerance
            }
            if !isMatched {
                mismatchPixels += 1
                mismatchMask[pixelIndex] = true
                diffPixels[byteIndex] = 255
                diffPixels[byteIndex + 1] = 0
                diffPixels[byteIndex + 2] = 0
                diffPixels[byteIndex + 3] = 255
            }
        }

        let comparedPixels = max(0, totalPixels - ignoredPixels)
        let mismatchRatio = comparedPixels == 0 ?
            0 : Double(mismatchPixels) / Double(comparedPixels)
        let differenceAnalysis = differenceAnalyzer.analyze(
            mask: mismatchMask,
            width: actual.width,
            height: actual.height,
            regionLimit: regionLimit
        )
        return PixelComparisonResult(
            totalPixels: totalPixels,
            comparedPixels: comparedPixels,
            mismatchPixels: mismatchPixels,
            mismatchRatio: mismatchRatio,
            diffPixels: diffPixels,
            ignoredPixels: ignoredPixels,
            differenceAnalysis: differenceAnalysis
        )
    }

    private func isIgnored(pixelIndex: Int, width: Int, regions: [ScreenshotIgnoreRegion]) -> Bool {
        let x = pixelIndex % width
        let y = pixelIndex / width
        return regions.contains { region in
            x >= region.x &&
                y >= region.y &&
                x < region.x + region.width &&
                y < region.y + region.height
        }
    }

    private func pixelImage(from data: Data) throws -> PixelImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CLIError.invalidJSONObject
        }

        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CLIError.invalidJSONObject
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return PixelImage(width: width, height: height, pixels: pixels)
    }

    private func pngData(width: Int, height: Int, pixels: [UInt8]) throws -> Data {
        var mutablePixels = pixels
        guard let context = CGContext(
            data: &mutablePixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
              let image = context.makeImage() else {
            throw CLIError.invalidJSONObject
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CLIError.invalidJSONObject
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CLIError.invalidJSONObject
        }
        return data as Data
    }

    private func write(_ data: Data, to path: String) throws {
        let outputURL = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: outputURL, options: .atomic)
    }

    private func numericValue(from value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        return nil
    }
}

private struct PixelImage {
    /// Image width, in pixels.
    let width: Int

    /// Image height, in pixels.
    let height: Int

    /// RGBA pixel data.
    let pixels: [UInt8]
}

private struct PixelComparisonResult {
    /// Total number of pixels considered for comparison.
    let totalPixels: Int

    /// Number of pixels compared after excluding ignore regions.
    let comparedPixels: Int

    /// Number of mismatched pixels.
    let mismatchPixels: Int

    /// Mismatched-pixel ratio.
    let mismatchRatio: Double

    /// RGBA pixel data used to generate the diff PNG.
    let diffPixels: [UInt8]

    /// Number of pixels covered by ignore regions.
    let ignoredPixels: Int

    /// Difference-region analysis result.
    let differenceAnalysis: PixelDifferenceAnalysis
}
