//
//  ScreenshotCaptureCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct ScreenshotCaptureCommand {
    /// Output path for the PNG file.
    let outputPath: String

    /// Screenshot source configuration.
    let captureOptions: ScreenshotCaptureOptions
}

struct ScreenshotCaptureCommandParser {
    private let captureOptionsResolver: ScreenshotCaptureOptionsResolver

    init(captureOptionsResolver: ScreenshotCaptureOptionsResolver) {
        self.captureOptionsResolver = captureOptionsResolver
    }

    func parse(appId: String, arguments: [String]) throws -> ScreenshotCaptureCommand {
        var outputPath: String?
        var sourceParser = ScreenshotCaptureSourceArgumentParser()
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--json":
                index += 1
            case "--output":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("--output path")
                }
                outputPath = arguments[index + 1]
                index += 2
            default:
                guard try sourceParser.consume(
                    argument: argument,
                    arguments: arguments,
                    index: &index
                ) else {
                    throw CLIError.unsupportedCommand(argument)
                }
            }
        }

        guard let outputPath, !outputPath.isEmpty else {
            throw CLIError.missingArgument("--output")
        }
        return ScreenshotCaptureCommand(
            outputPath: outputPath,
            captureOptions: try captureOptionsResolver.resolve(
                appId: appId,
                arguments: sourceParser.arguments
            )
        )
    }
}
