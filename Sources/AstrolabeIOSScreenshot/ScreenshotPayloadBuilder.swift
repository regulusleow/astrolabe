//
//  ScreenshotPayloadBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeCLI
import Foundation

protocol ScreenshotPayloadBuilding {
    func simulatorPayload(appId: String, hierarchy: [String: Any], pngData: Data, simulatorUDID: String) throws -> [String: Any]
    func devicePayload(appId: String, hierarchy: [String: Any], pngData: Data, deviceIdentifier: String) throws -> [String: Any]
}

struct ScreenshotPayloadBuilder: ScreenshotPayloadBuilding {
    private let imageMetadataReader: ScreenshotImageMetadataReading

    init(imageMetadataReader: ScreenshotImageMetadataReading = ScreenshotImageMetadataReader()) {
        self.imageMetadataReader = imageMetadataReader
    }

    func simulatorPayload(appId: String, hierarchy: [String: Any], pngData: Data, simulatorUDID: String) throws -> [String: Any] {
        try systemPayload(
            appId: appId,
            hierarchy: hierarchy,
            pngData: pngData,
            source: "simulator",
            sourceMetadata: ["simulatorUDID": simulatorUDID]
        )
    }

    func devicePayload(appId: String, hierarchy: [String: Any], pngData: Data, deviceIdentifier: String) throws -> [String: Any] {
        try systemPayload(
            appId: appId,
            hierarchy: hierarchy,
            pngData: pngData,
            source: "device",
            sourceMetadata: ["deviceIdentifier": deviceIdentifier]
        )
    }

    private func systemPayload(
        appId: String,
        hierarchy: [String: Any],
        pngData: Data,
        source: String,
        sourceMetadata: [String: Any]
    ) throws -> [String: Any] {
        let app = hierarchy["app"] as? [String: Any] ?? [:]
        let screen = app["screen"] as? [String: Any] ?? [:]
        let imageMetadata = try imageMetadataReader.metadata(from: pngData)
        let scale = numericValue(from: screen["scale"]) ?? inferredScale(imageMetadata: imageMetadata, screen: screen)
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
        if let scale {
            screenshot["scale"] = scale
        }
        if let pointWidth = numericValue(from: screen["width"]) {
            screenshot["pointWidth"] = pointWidth
        }
        if let pointHeight = numericValue(from: screen["height"]) {
            screenshot["pointHeight"] = pointHeight
        }

        return [
            "appId": appId,
            "serverVersion": hierarchy["serverVersion"] ?? NSNull(),
            "app": app,
            "screenshot": screenshot
        ]
    }

    private func inferredScale(imageMetadata: ScreenshotImageMetadata, screen: [String: Any]) -> Double? {
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
        return (xScale + yScale) / 2.0
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
}
