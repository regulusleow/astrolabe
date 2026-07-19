//
//  ScreenshotProvider.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

package enum ScreenshotCaptureTarget {
    case automatic
    case virtualDevice
    case physicalDevice
}

package struct ScreenshotCaptureOptions {
    /// Preferred screenshot target type; the platform Provider resolves automatic from connection metadata.
    package let target: ScreenshotCaptureTarget

    /// Target device identifier whose format is interpreted by the selected platform Provider.
    package let targetIdentifier: String?

    package init(target: ScreenshotCaptureTarget, targetIdentifier: String?) {
        self.target = target
        self.targetIdentifier = targetIdentifier
    }

    static let automatic = ScreenshotCaptureOptions(
        target: .automatic,
        targetIdentifier: nil
    )
}

package protocol ScreenshotProviding {
    func capture(
        appId: String,
        options: ScreenshotCaptureOptions,
        screenMetadata: () throws -> [String: Any]
    ) throws -> [String: Any]
}

package protocol PlatformScreenshotProviding {
    func capture(
        appId: String,
        options: ScreenshotCaptureOptions,
        screenMetadata: () throws -> [String: Any]
    ) throws -> [String: Any]
}

package struct DefaultScreenshotProvider: ScreenshotProviding {
    private let platformResolver: any RuntimeUIPlatformResolving
    private let platformProviders: [RuntimeUIPlatform: any PlatformScreenshotProviding]

    package init(
        platformResolver: any RuntimeUIPlatformResolving,
        platformProviders: [RuntimeUIPlatform: any PlatformScreenshotProviding]
    ) {
        self.platformResolver = platformResolver
        self.platformProviders = platformProviders
    }

    package func capture(
        appId: String,
        options: ScreenshotCaptureOptions,
        screenMetadata: () throws -> [String: Any]
    ) throws -> [String: Any] {
        let platform = try platformResolver.platform(for: appId)
        guard let platformProvider = platformProviders[platform] else {
            throw CLIError.commandFailed("No screenshot Provider is configured for platform \(platform.rawValue)")
        }

        return try platformProvider.capture(
            appId: appId,
            options: options,
            screenMetadata: screenMetadata
        )
    }
}
