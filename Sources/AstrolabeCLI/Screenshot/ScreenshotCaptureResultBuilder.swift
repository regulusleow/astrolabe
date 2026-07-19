//
//  ScreenshotCaptureResultBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct ScreenshotCaptureResultBuilder {
    private let decoder: ScreenshotPayloadDecoder

    init(decoder: ScreenshotPayloadDecoder = ScreenshotPayloadDecoder()) {
        self.decoder = decoder
    }

    func buildPayload(rawPayload: [String: Any], outputPath: String) throws -> [String: Any] {
        var payload = rawPayload
        let decodedScreenshot = try decoder.decode(rawPayload: rawPayload)
        var screenshot = decodedScreenshot.metadata

        let outputURL = URL(fileURLWithPath: outputPath)
        let directoryURL = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try decodedScreenshot.data.write(to: outputURL, options: .atomic)

        screenshot["base64"] = nil
        screenshot["outputPath"] = outputURL.path
        screenshot["byteCount"] = decodedScreenshot.data.count
        payload["screenshot"] = screenshot
        return payload
    }
}
