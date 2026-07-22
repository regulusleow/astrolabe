//
//  SystemScreenshotPayloadBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeCLI
import Foundation

package protocol SystemScreenshotPayloadBuilding {
    func payload(
        appId: String,
        hierarchy: [String: Any],
        pngData: Data,
        source: String,
        sourceMetadata: [String: Any]
    ) throws -> [String: Any]
}

package struct SystemScreenshotPayloadBuilder:
    SystemScreenshotPayloadBuilding {
    private let imageMetadataReader: any ScreenshotImageMetadataReading

    package init(
        imageMetadataReader: any ScreenshotImageMetadataReading =
            ScreenshotImageMetadataReader()
    ) {
        self.imageMetadataReader = imageMetadataReader
    }

    package func payload(
        appId: String,
        hierarchy: [String: Any],
        pngData: Data,
        source: String,
        sourceMetadata: [String: Any]
    ) throws -> [String: Any] {
        let app = hierarchy["app"] as? [String: Any] ?? [:]
        let screen = app["screen"] as? [String: Any] ?? [:]
        let imageMetadata = try imageMetadataReader.metadata(from: pngData)
        let scale = numericValue(from: screen["scale"])
            ?? inferredScale(imageMetadata: imageMetadata, screen: screen)
        var screenshot: [String: Any] = [
            "format": "png",
            "base64": pngData.base64EncodedString(),
            "byteCount": pngData.count,
            "source": source,
            "lowResolution": false,
            "width": imageMetadata.pixelWidth,
            "height": imageMetadata.pixelHeight,
            "pixelWidth": imageMetadata.pixelWidth,
            "pixelHeight": imageMetadata.pixelHeight
        ]
        screenshot.merge(sourceMetadata) { _, new in new }
        screenshot["scale"] = scale
        screenshot["pointWidth"] = pointDimension(
            pixels: imageMetadata.pixelWidth,
            scale: scale,
            fallback: screen["width"]
        )
        screenshot["pointHeight"] = pointDimension(
            pixels: imageMetadata.pixelHeight,
            scale: scale,
            fallback: screen["height"]
        )
        return [
            "appId": appId,
            "serverVersion": hierarchy["serverVersion"] ?? NSNull(),
            "app": app,
            "screenshot": screenshot.compactMapValues { $0 }
        ]
    }

    private func inferredScale(
        imageMetadata: ScreenshotImageMetadata,
        screen: [String: Any]
    ) -> Double? {
        guard let pointWidth = numericValue(from: screen["width"]),
              let pointHeight = numericValue(from: screen["height"]),
              pointWidth > 0,
              pointHeight > 0 else {
            return nil
        }
        let xScale = Double(imageMetadata.pixelWidth) / pointWidth
        let yScale = Double(imageMetadata.pixelHeight) / pointHeight
        guard xScale > 0, yScale > 0 else {
            return nil
        }
        return (xScale + yScale) / 2
    }

    private func numericValue(from value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int {
            return Double(value)
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        return nil
    }

    private func pointDimension(
        pixels: Int,
        scale: Double?,
        fallback: Any?
    ) -> Double? {
        guard let scale, scale > 0 else {
            return numericValue(from: fallback)
        }
        return Double(pixels) / scale
    }
}
