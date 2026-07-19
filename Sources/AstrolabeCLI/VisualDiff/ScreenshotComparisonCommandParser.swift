//
//  ScreenshotComparisonCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct ScreenshotComparisonCommand {
    /// Expected PNG file path.
    let expectedPath: String

    /// Output path for the actual screenshot PNG.
    let actualOutputPath: String?

    /// Output path for the diff PNG.
    let diffOutputPath: String?

    /// Maximum allowed mismatched-pixel ratio, in the range 0...1.
    let threshold: Double

    /// Per-channel pixel tolerance, in the range 0...255.
    let pixelTolerance: Int

    /// Maximum number of difference regions to return.
    let regionLimit: Int

    /// Whether to return UI nodes that overlap difference regions.
    let includeNodes: Bool

    /// Maximum number of affected nodes to return.
    let nodeLimit: Int

    /// Pixel regions to ignore during comparison.
    let ignoreRegions: [ScreenshotIgnoreRegion]

    /// Node OIDs whose UI frames are ignored during comparison.
    let ignoreNodeOids: [String]

    /// Named screenshot regions to ignore during comparison.
    let ignoreMaskNames: [String]

    /// Node queries whose matched frames are ignored during comparison.
    let ignoreNodeQueries: [HierarchyNodeQuery]

    /// Screenshot source configuration.
    let captureOptions: ScreenshotCaptureOptions

    /// Whether low-resolution screenshots may be used for pixel comparison.
    let allowLowResolution: Bool

    func includingAffectedNodes() -> ScreenshotComparisonCommand {
        ScreenshotComparisonCommand(
            expectedPath: expectedPath,
            actualOutputPath: actualOutputPath,
            diffOutputPath: diffOutputPath,
            threshold: threshold,
            pixelTolerance: pixelTolerance,
            regionLimit: regionLimit,
            includeNodes: true,
            nodeLimit: nodeLimit,
            ignoreRegions: ignoreRegions,
            ignoreNodeOids: ignoreNodeOids,
            ignoreMaskNames: ignoreMaskNames,
            ignoreNodeQueries: ignoreNodeQueries,
            captureOptions: captureOptions,
            allowLowResolution: allowLowResolution
        )
    }

    func addingIgnoreRegions(_ additionalRegions: [ScreenshotIgnoreRegion]) -> ScreenshotComparisonCommand {
        ScreenshotComparisonCommand(
            expectedPath: expectedPath,
            actualOutputPath: actualOutputPath,
            diffOutputPath: diffOutputPath,
            threshold: threshold,
            pixelTolerance: pixelTolerance,
            regionLimit: regionLimit,
            includeNodes: includeNodes,
            nodeLimit: nodeLimit,
            ignoreRegions: ignoreRegions + additionalRegions,
            ignoreNodeOids: ignoreNodeOids,
            ignoreMaskNames: ignoreMaskNames,
            ignoreNodeQueries: ignoreNodeQueries,
            captureOptions: captureOptions,
            allowLowResolution: allowLowResolution
        )
    }
}

package struct ScreenshotIgnoreRegion {
    /// Top-left x coordinate of the ignore region, in pixels.
    package let x: Int

    /// Top-left y coordinate of the ignore region, in pixels.
    package let y: Int

    /// Width of the ignore region, in pixels.
    package let width: Int

    /// Height of the ignore region, in pixels.
    package let height: Int

    package var dictionary: [String: Int] {
        [
            "x": x,
            "y": y,
            "width": width,
            "height": height
        ]
    }

    package init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(dictionary: [String: Any]) throws {
        guard let x = dictionary["x"] as? Int,
              let y = dictionary["y"] as? Int,
              let width = dictionary["width"] as? Int,
              let height = dictionary["height"] as? Int,
              width > 0,
              height > 0 else {
            throw CLIError.invalidJSONObject
        }
        self.init(x: x, y: y, width: width, height: height)
    }

    static func parse(arguments: [String], from index: Int) throws -> ScreenshotIgnoreRegion {
        guard index + 4 < arguments.count,
              let x = Int(arguments[index + 1]),
              let y = Int(arguments[index + 2]),
              let width = Int(arguments[index + 3]),
              let height = Int(arguments[index + 4]),
              width > 0,
              height > 0 else {
            throw CLIError.missingArgument("--ignore-region in x y width height format")
        }
        return ScreenshotIgnoreRegion(x: x, y: y, width: width, height: height)
    }
}

struct ScreenshotComparisonCommandParser {
    private let captureOptionsResolver: ScreenshotCaptureOptionsResolver

    init(captureOptionsResolver: ScreenshotCaptureOptionsResolver) {
        self.captureOptionsResolver = captureOptionsResolver
    }

    func parse(appId: String, arguments: [String]) throws -> ScreenshotComparisonCommand {
        var expectedPath: String?
        var actualOutputPath: String?
        var diffOutputPath: String?
        var threshold = 0.0
        var pixelTolerance = 0
        var regionLimit = 10
        var includeNodes = false
        var nodeLimit = 5
        var ignoreRegions: [ScreenshotIgnoreRegion] = []
        var ignoreNodeOids: [String] = []
        var ignoreMaskNames: [String] = []
        var ignoreNodeQueries: [HierarchyNodeQuery] = []
        var sourceParser = ScreenshotCaptureSourceArgumentParser()
        var allowLowResolution = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--json":
                index += 1
            case "--expected":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("--expected path")
                }
                expectedPath = arguments[index + 1]
                index += 2
            case "--actual-output":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("--actual-output path")
                }
                actualOutputPath = arguments[index + 1]
                index += 2
            case "--diff-output":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("--diff-output path")
                }
                diffOutputPath = arguments[index + 1]
                index += 2
            case "--threshold":
                guard index + 1 < arguments.count,
                      let parsedThreshold = Double(arguments[index + 1]),
                      parsedThreshold >= 0,
                      parsedThreshold <= 1 else {
                    throw CLIError.missingArgument("--threshold in the 0...1 range")
                }
                threshold = parsedThreshold
                index += 2
            case "--pixel-tolerance":
                guard index + 1 < arguments.count,
                      let parsedTolerance = Int(arguments[index + 1]),
                      parsedTolerance >= 0,
                      parsedTolerance <= 255 else {
                    throw CLIError.missingArgument("--pixel-tolerance in the 0...255 range")
                }
                pixelTolerance = parsedTolerance
                index += 2
            case "--region-limit":
                guard index + 1 < arguments.count,
                      let parsedLimit = Int(arguments[index + 1]),
                      parsedLimit >= 0 else {
                    throw CLIError.missingArgument("non-negative integer --region-limit")
                }
                regionLimit = parsedLimit
                index += 2
            case "--include-nodes":
                includeNodes = true
                index += 1
            case "--node-limit":
                guard index + 1 < arguments.count,
                      let parsedLimit = Int(arguments[index + 1]),
                      parsedLimit >= 0 else {
                    throw CLIError.missingArgument("non-negative integer --node-limit")
                }
                nodeLimit = parsedLimit
                index += 2
            case "--ignore-region":
                ignoreRegions.append(try ScreenshotIgnoreRegion.parse(arguments: arguments, from: index))
                index += 5
            case "--ignore-node-oid":
                guard index + 1 < arguments.count,
                      !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("valid --ignore-node-oid")
                }
                ignoreNodeOids.append(arguments[index + 1])
                index += 2
            case "--ignore-mask":
                guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("non-empty --ignore-mask")
                }
                ignoreMaskNames.append(arguments[index + 1])
                index += 2
            case "--ignore-node-query":
                let parsed = try ScreenshotIgnoreNodeQueryParser().parse(arguments: arguments, from: index + 1)
                ignoreNodeQueries.append(parsed.query)
                index = parsed.nextIndex
            case "--allow-low-resolution":
                allowLowResolution = true
                index += 1
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

        guard let expectedPath, !expectedPath.isEmpty else {
            throw CLIError.missingArgument("--expected")
        }

        return ScreenshotComparisonCommand(
            expectedPath: expectedPath,
            actualOutputPath: actualOutputPath,
            diffOutputPath: diffOutputPath,
            threshold: threshold,
            pixelTolerance: pixelTolerance,
            regionLimit: regionLimit,
            includeNodes: includeNodes,
            nodeLimit: nodeLimit,
            ignoreRegions: ignoreRegions,
            ignoreNodeOids: ignoreNodeOids,
            ignoreMaskNames: ignoreMaskNames,
            ignoreNodeQueries: ignoreNodeQueries,
            captureOptions: try captureOptionsResolver.resolve(
                appId: appId,
                arguments: sourceParser.arguments
            ),
            allowLowResolution: allowLowResolution
        )
    }
}
