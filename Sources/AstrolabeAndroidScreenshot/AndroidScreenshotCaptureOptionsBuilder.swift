//
//  AndroidScreenshotCaptureOptionsBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeCLI

package struct AndroidScreenshotCaptureOptionsBuilder:
    ScreenshotCaptureOptionsBuilding {
    package init() {}

    package func build(
        from arguments: ScreenshotCaptureSourceArguments
    ) throws -> ScreenshotCaptureOptions {
        switch arguments.source {
        case .automatic:
            return ScreenshotCaptureOptions(
                target: .automatic,
                targetIdentifier: arguments.targetIdentifier
            )
        case .virtual:
            return ScreenshotCaptureOptions(
                target: .virtualDevice,
                targetIdentifier: arguments.targetIdentifier
            )
        case .physical:
            guard let targetIdentifier = arguments.targetIdentifier else {
                throw CLIError.invalidArgument(
                    "--source physical requires --target-id"
                )
            }
            return ScreenshotCaptureOptions(
                target: .physicalDevice,
                targetIdentifier: targetIdentifier
            )
        }
    }
}
