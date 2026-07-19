//
//  ScreenshotPayloadMetadata.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

import Foundation

struct ScreenshotPayloadMetadata {
    /// Scale factor from logical coordinates to screenshot pixels.
    let scale: Double

    /// Screenshot pixel dimensions, or nil when the payload lacks valid dimensions.
    let dimensions: (width: Int, height: Int)?

    init(rawPayload: [String: Any]) {
        guard let screenshot = rawPayload["screenshot"] as? [String: Any] else {
            scale = 1
            dimensions = nil
            return
        }
        scale = Self.doubleValue(from: screenshot["scale"]) ?? 1
        if let width = Self.intValue(from: screenshot["width"]),
           let height = Self.intValue(from: screenshot["height"]),
           width > 0,
           height > 0 {
            dimensions = (width, height)
        } else {
            dimensions = nil
        }
    }

    private static func doubleValue(from value: Any?) -> Double? {
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

    private static func intValue(from value: Any?) -> Int? {
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let int = value as? Int {
            return int
        }
        if let double = value as? Double {
            return Int(double)
        }
        return nil
    }
}
