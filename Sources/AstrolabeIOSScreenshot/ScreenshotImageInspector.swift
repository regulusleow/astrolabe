//
//  ScreenshotImageInspector.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeCLI
import Foundation
import ImageIO
import CoreGraphics

struct ScreenshotImageMetadata {
    /// PNG pixel width.
    let pixelWidth: Int

    /// PNG pixel height.
    let pixelHeight: Int
}

protocol ScreenshotImageMetadataReading {
    func metadata(from data: Data) throws -> ScreenshotImageMetadata
}

struct ScreenshotImageMetadataReader: ScreenshotImageMetadataReading {
    func metadata(from data: Data) throws -> ScreenshotImageMetadata {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            throw CLIError.invalidJSONObject
        }
        return ScreenshotImageMetadata(pixelWidth: width, pixelHeight: height)
    }
}

protocol ScreenshotImageContentInspecting {
    func isCompletelyBlack(_ data: Data) throws -> Bool
}

struct ScreenshotImageContentInspector: ScreenshotImageContentInspecting {
    func isCompletelyBlack(_ data: Data) throws -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CLIError.invalidScreenshot("Unable to decode PNG data")
        }
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        var pixels = [UInt8](
            repeating: 0,
            count: bytesPerRow * image.height
        )
        try pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                throw CLIError.invalidScreenshot("Unable to inspect PNG pixels")
            }
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: image.width,
                    height: image.height
                )
            )
        }
        return stride(from: 0, to: pixels.count, by: bytesPerPixel)
            .allSatisfy { offset in
                pixels[offset] == 0 &&
                    pixels[offset + 1] == 0 &&
                    pixels[offset + 2] == 0
            }
    }
}
