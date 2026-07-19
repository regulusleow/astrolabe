//
//  ScreenshotPayloadDecoder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct DecodedScreenshot {
    /// Raw screenshot PNG data.
    let data: Data

    /// Screenshot metadata before removing the base64 payload.
    let metadata: [String: Any]
}

struct ScreenshotPayloadDecoder {
    func decode(rawPayload: [String: Any]) throws -> DecodedScreenshot {
        guard let screenshot = rawPayload["screenshot"] as? [String: Any],
              let base64 = screenshot["base64"] as? String,
              let data = Data(base64Encoded: base64) else {
            throw CLIError.invalidJSONObject
        }

        return DecodedScreenshot(data: data, metadata: screenshot)
    }
}
