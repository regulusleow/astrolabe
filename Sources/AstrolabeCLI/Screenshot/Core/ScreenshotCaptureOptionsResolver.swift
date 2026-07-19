//
//  ScreenshotCaptureOptionsResolver.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

package enum ScreenshotCaptureSource: String {
    case automatic = "auto"
    case virtual = "virtual"
    case physical = "physical"

    static func parse(_ value: String) throws -> ScreenshotCaptureSource {
        guard let source = ScreenshotCaptureSource(rawValue: value) else {
            throw CLIError.invalidArgument(
                "--source supports only auto, virtual, or physical"
            )
        }
        return source
    }
}

package struct ScreenshotCaptureSourceArguments {
    /// Platform-neutral screenshot source specified by the user.
    package let source: ScreenshotCaptureSource

    /// Target device identifier specified by the user.
    package let targetIdentifier: String?
}

struct ScreenshotCaptureSourceArgumentParser {
    private(set) var source = ScreenshotCaptureSource.automatic
    private(set) var targetIdentifier: String?

    var arguments: ScreenshotCaptureSourceArguments {
        ScreenshotCaptureSourceArguments(
            source: source,
            targetIdentifier: targetIdentifier
        )
    }

    mutating func consume(
        argument: String,
        arguments: [String],
        index: inout Int
    ) throws -> Bool {
        switch argument {
        case "--source":
            guard index + 1 < arguments.count else {
                throw CLIError.missingArgument("--source")
            }
            source = try ScreenshotCaptureSource.parse(arguments[index + 1])
            index += 2
            return true
        case "--target-id":
            guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                throw CLIError.missingArgument("non-empty --target-id")
            }
            targetIdentifier = arguments[index + 1]
            index += 2
            return true
        default:
            return false
        }
    }
}

package protocol ScreenshotCaptureOptionsBuilding {
    func build(from arguments: ScreenshotCaptureSourceArguments) throws -> ScreenshotCaptureOptions
}

struct ScreenshotCaptureOptionsResolver {
    private let platformResolver: any RuntimeUIPlatformResolving
    private let builders: [RuntimeUIPlatform: any ScreenshotCaptureOptionsBuilding]

    init(
        platformResolver: any RuntimeUIPlatformResolving,
        builders: [RuntimeUIPlatform: any ScreenshotCaptureOptionsBuilding]
    ) {
        self.platformResolver = platformResolver
        self.builders = builders
    }

    func resolve(
        appId: String,
        arguments: ScreenshotCaptureSourceArguments
    ) throws -> ScreenshotCaptureOptions {
        let platform = try platformResolver.platform(for: appId)
        guard let builder = builders[platform] else {
            throw CLIError.commandFailed("No screenshot source strategy is configured for platform \(platform.rawValue)")
        }
        return try builder.build(from: arguments)
    }
}
