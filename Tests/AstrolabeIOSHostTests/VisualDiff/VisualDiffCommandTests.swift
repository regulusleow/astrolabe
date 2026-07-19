//
//  VisualDiffCommandTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeProtocol
import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import AstrolabeCLI

private typealias Fixtures = CLICommandTestFixtures

final class VisualDiffCommandTests: XCTestCase {
    func testCompareScreenshotPassesForMatchingPNG() throws {
        let pngData = try Fixtures.makePNGData(width: 2, height: 1, pixels: [
            [255, 0, 0, 255],
            [0, 0, 255, 255]
        ])
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": pngData.base64EncodedString(),
                "byteCount": pngData.count,
                "width": 2,
                "height": 1,
                "scale": 1
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let actualURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
            Fixtures.removeFileIfNeeded(actualURL)
        }
        try pngData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-screenshot",
            "app-1",
            "--expected",
            expectedURL.path,
            "--actual-output",
            actualURL.path,
            "--threshold",
            "0"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(object["success"] as? Bool, true)
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["mismatchPixels"] as? Int, 0)
        XCTAssertEqual(data["totalPixels"] as? Int, 2)
        XCTAssertEqual(data["mismatchRatio"] as? Double, 0)
        XCTAssertEqual(data["actualPath"] as? String, actualURL.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: actualURL.path))
        XCTAssertEqual(service.calls, [])
    }

    func testCompareScreenshotDataContractIncludesStableKeys() throws {
        let pngData = try Fixtures.makePNGData(width: 1, height: 1, pixels: [[0, 0, 0, 255]])
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": pngData.base64EncodedString(),
                "byteCount": pngData.count,
                "width": 1,
                "height": 1,
                "scale": 1
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
        }
        try pngData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-screenshot",
            "app-1",
            "--expected",
            expectedURL.path
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let keys = Set(data.keys)
        XCTAssertTrue(keys.isSuperset(of: [
            "passed",
            "reason",
            "expectedPath",
            "actualPath",
            "diffPath",
            "threshold",
            "pixelTolerance",
            "screenshotScale",
            "screenshotSource",
            "lowResolution",
            "dimensions",
            "totalPixels",
            "comparedPixels",
            "mismatchPixels",
            "mismatchRatio",
            "mismatchBounds",
            "mismatchRegions",
            "mismatchRegionCount",
            "omittedMismatchRegionCount",
            "ignoredRegionCount",
            "ignoredPixels"
        ]))
    }

    func testCompareScreenshotRejectsLowResolutionSourceByDefault() throws {
        let pngData = try Fixtures.makePNGData(width: 1, height: 1, pixels: [[0, 0, 0, 255]])
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": pngData.base64EncodedString(),
                "byteCount": pngData.count,
                "width": 1,
                "height": 1,
                "scale": 1,
                "source": "synthetic",
                "lowResolution": true
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
        }
        try pngData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-screenshot",
            "app-1",
            "--expected",
            expectedURL.path
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, false)
        XCTAssertEqual(data["reason"] as? String, "lowResolutionScreenshot")
        XCTAssertEqual(data["screenshotSource"] as? String, "synthetic")
        XCTAssertEqual(data["lowResolution"] as? Bool, true)
    }

    func testCompareScreenshotReportsMismatchBoundsAndRegions() throws {
        let expectedData = try Fixtures.makePNGData(width: 4, height: 3, pixels: Array(repeating: [0, 0, 0, 255], count: 12))
        var actualPixels: [[UInt8]] = Array(repeating: [0, 0, 0, 255], count: 12)
        actualPixels[5] = [255, 0, 0, 255]
        actualPixels[6] = [255, 0, 0, 255]
        let actualData = try Fixtures.makePNGData(width: 4, height: 3, pixels: actualPixels)
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": actualData.base64EncodedString(),
                "byteCount": actualData.count,
                "width": 4,
                "height": 3,
                "scale": 1
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
        }
        try expectedData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-screenshot",
            "app-1",
            "--expected",
            expectedURL.path,
            "--threshold",
            "0"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let bounds = try XCTUnwrap(data["mismatchBounds"] as? [String: Int])
        let regions = try XCTUnwrap(data["mismatchRegions"] as? [[String: Any]])
        XCTAssertEqual(data["passed"] as? Bool, false)
        XCTAssertEqual(data["reason"] as? String, "pixelMismatch")
        XCTAssertEqual(data["mismatchPixels"] as? Int, 2)
        XCTAssertEqual(bounds, ["x": 1, "y": 1, "width": 2, "height": 1])
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions.first?["x"] as? Int, 1)
        XCTAssertEqual(regions.first?["y"] as? Int, 1)
        XCTAssertEqual(regions.first?["width"] as? Int, 2)
        XCTAssertEqual(regions.first?["height"] as? Int, 1)
        XCTAssertEqual(regions.first?["pixelCount"] as? Int, 2)
        XCTAssertEqual(service.calls, [])
    }

    func testCompareScreenshotLimitsMismatchRegions() throws {
        let expectedData = try Fixtures.makePNGData(width: 5, height: 1, pixels: Array(repeating: [0, 0, 0, 255], count: 5))
        var actualPixels: [[UInt8]] = Array(repeating: [0, 0, 0, 255], count: 5)
        actualPixels[0] = [255, 0, 0, 255]
        actualPixels[2] = [255, 0, 0, 255]
        actualPixels[4] = [255, 0, 0, 255]
        let actualData = try Fixtures.makePNGData(width: 5, height: 1, pixels: actualPixels)
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": actualData.base64EncodedString(),
                "byteCount": actualData.count,
                "width": 5,
                "height": 1,
                "scale": 1
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
        }
        try expectedData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-screenshot",
            "app-1",
            "--expected",
            expectedURL.path,
            "--region-limit",
            "2"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let regions = try XCTUnwrap(data["mismatchRegions"] as? [[String: Any]])
        XCTAssertEqual(data["mismatchRegionCount"] as? Int, 3)
        XCTAssertEqual(data["omittedMismatchRegionCount"] as? Int, 1)
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions.compactMap { $0["x"] as? Int }, [0, 2])
        XCTAssertEqual(service.calls, [])
    }

    func testCompareScreenshotCanIncludeAffectedNodes() throws {
        let expectedData = try Fixtures.makePNGData(width: 4, height: 3, pixels: Array(repeating: [0, 0, 0, 255], count: 12))
        var actualPixels: [[UInt8]] = Array(repeating: [0, 0, 0, 255], count: 12)
        actualPixels[5] = [255, 0, 0, 255]
        actualPixels[6] = [255, 0, 0, 255]
        let actualData = try Fixtures.makePNGData(width: 4, height: 3, pixels: actualPixels)
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": actualData.base64EncodedString(),
                "byteCount": actualData.count,
                "width": 4,
                "height": 3,
                "scale": 1
            ]
        ]
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "1",
                    "detailOid": "11",
                    "className": "UIWindow",
                    "frame": ["x": 0, "y": 0, "width": 4, "height": 3],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1,
                    "subitems": [
                        [
                            "oid": "2",
                            "detailOid": "22",
                            "className": "UILabel",
                            "customDisplayTitle": "Title",
                            "frame": ["x": 1, "y": 1, "width": 2, "height": 1],
                            "hidden": false,
                            "visible": true,
                            "alpha": 1
                        ]
                    ]
                ]
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
        }
        try expectedData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-screenshot",
            "app-1",
            "--expected",
            expectedURL.path,
            "--include-nodes",
            "--node-limit",
            "1"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let affectedNodes = try XCTUnwrap(data["affectedNodes"] as? [[String: Any]])
        XCTAssertEqual(data["affectedNodeCount"] as? Int, 2)
        XCTAssertEqual(data["omittedAffectedNodeCount"] as? Int, 1)
        XCTAssertEqual(affectedNodes.count, 1)
        XCTAssertEqual(affectedNodes.first?["oid"] as? String, "2")
        XCTAssertEqual(affectedNodes.first?["className"] as? String, "UILabel")
        XCTAssertEqual(affectedNodes.first?["hierarchyPath"] as? String, "UIWindow[0]/UILabel[0]")
        XCTAssertEqual(affectedNodes.first?["regionIndex"] as? Int, 0)
        XCTAssertEqual(affectedNodes.first?["overlapArea"] as? Double, 2)
        XCTAssertEqual(affectedNodes.first?["nodeOverlapRatio"] as? Double, 1)
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testCompareScreenshotIgnoresConfiguredRegions() throws {
        let expectedData = try Fixtures.makePNGData(width: 3, height: 1, pixels: Array(repeating: [0, 0, 0, 255], count: 3))
        let actualData = try Fixtures.makePNGData(width: 3, height: 1, pixels: [
            [255, 0, 0, 255],
            [0, 0, 0, 255],
            [0, 0, 255, 255]
        ])
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": actualData.base64EncodedString(),
                "byteCount": actualData.count,
                "width": 3,
                "height": 1,
                "scale": 1
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
        }
        try expectedData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-screenshot",
            "app-1",
            "--expected",
            expectedURL.path,
            "--ignore-region",
            "0",
            "0",
            "1",
            "1",
            "--ignore-region",
            "2",
            "0",
            "1",
            "1",
            "--threshold",
            "0"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["mismatchPixels"] as? Int, 0)
        XCTAssertEqual(data["ignoredRegionCount"] as? Int, 2)
        XCTAssertEqual(data["ignoredPixels"] as? Int, 2)
        XCTAssertEqual(data["mismatchRegionCount"] as? Int, 0)
        XCTAssertEqual(service.calls, [])
    }

    func testCompareScreenshotExcludesIgnoredPixelsFromMismatchRatio() throws {
        let expectedData = try Fixtures.makePNGData(
            width: 10,
            height: 1,
            pixels: Array(repeating: [0, 0, 0, 255], count: 10)
        )
        var actualPixels = Array(repeating: [0, 0, 0, 255] as [UInt8], count: 10)
        actualPixels[9] = [255, 0, 0, 255]
        let service = Fixtures.FakeInspectorService()
        let actualData = try Fixtures.makePNGData(width: 10, height: 1, pixels: actualPixels)
        service.screenshot = [
            "appId": "app-1",
            "screenshot": [
                "format": "png",
                "base64": actualData.base64EncodedString(),
                "width": 10,
                "height": 1,
                "scale": 1
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer { Fixtures.removeFileIfNeeded(expectedURL) }
        try expectedData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-screenshot",
            "app-1",
            "--expected",
            expectedURL.path,
            "--ignore-region",
            "0",
            "0",
            "9",
            "1",
            "--threshold",
            "0.5"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, false)
        XCTAssertEqual(data["totalPixels"] as? Int, 10)
        XCTAssertEqual(data["comparedPixels"] as? Int, 1)
        XCTAssertEqual(data["mismatchPixels"] as? Int, 1)
        XCTAssertEqual(data["mismatchRatio"] as? Double, 1)
    }

    func testCompareScreenshotCanIgnoreNamedMasks() throws {
        let expectedData = try Fixtures.makePNGData(width: 100, height: 100, pixels: Array(repeating: [0, 0, 0, 255], count: 10_000))
        var actualPixels: [[UInt8]] = Array(repeating: [0, 0, 0, 255], count: 10_000)
        for y in 0..<44 {
            for x in 0..<100 {
                actualPixels[y * 100 + x] = [255, 0, 0, 255]
            }
        }
        let actualData = try Fixtures.makePNGData(width: 100, height: 100, pixels: actualPixels)
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": actualData.base64EncodedString(),
                "byteCount": actualData.count,
                "width": 100,
                "height": 100,
                "scale": 1
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
        }
        try expectedData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-screenshot",
            "app-1",
            "--expected",
            expectedURL.path,
            "--ignore-mask",
            "statusBar",
            "--threshold",
            "0"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let ignoredMaskRegions = try XCTUnwrap(data["ignoredMaskRegions"] as? [[String: Any]])
        let maskRegion = try XCTUnwrap(ignoredMaskRegions.first?["ignoreRegion"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["mismatchPixels"] as? Int, 0)
        XCTAssertEqual(data["ignoredRegionCount"] as? Int, 1)
        XCTAssertEqual(data["ignoredPixels"] as? Int, 4_400)
        XCTAssertEqual(data["ignoredMaskRegionCount"] as? Int, 1)
        XCTAssertEqual(data["unresolvedIgnoreMasks"] as? [String], [])
        XCTAssertEqual(ignoredMaskRegions.first?["name"] as? String, "statusBar")
        XCTAssertEqual(maskRegion["width"] as? Int, 100)
        XCTAssertEqual(maskRegion["height"] as? Int, 44)
        XCTAssertEqual(service.calls, [])
    }

    func testCompareScreenshotReportsUnknownNamedMasks() throws {
        let pngData = try Fixtures.makePNGData(width: 2, height: 2, pixels: Array(repeating: [0, 0, 0, 255], count: 4))
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": pngData.base64EncodedString(),
                "byteCount": pngData.count,
                "width": 2,
                "height": 2,
                "scale": 1
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
        }
        try pngData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-screenshot",
            "app-1",
            "--expected",
            expectedURL.path,
            "--ignore-mask",
            "clockLabel"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["ignoredMaskRegionCount"] as? Int, 0)
        XCTAssertEqual(data["unresolvedIgnoreMasks"] as? [String], ["clockLabel"])
        XCTAssertEqual(service.calls, [])
    }

    func testNamedMaskRegistryDelegatesOnlyToResolvedPlatform() {
        let resolver = FixedNamedMaskResolver()
        let registry = ScreenshotNamedMaskResolverRegistry(
            resolvers: [.android: resolver]
        )

        let androidResolution = registry.resolve(
            platform: .android,
            maskNames: ["systemBars"],
            imageWidth: 100,
            imageHeight: 200,
            screenshotScale: 1
        )
        let iosResolution = registry.resolve(
            platform: .ios,
            maskNames: ["systemBars"],
            imageWidth: 100,
            imageHeight: 200,
            screenshotScale: 1
        )

        XCTAssertEqual(androidResolution.ignoreRegions.first?.height, 24)
        XCTAssertEqual(androidResolution.unresolvedMaskNames, [])
        XCTAssertTrue(iosResolution.ignoreRegions.isEmpty)
        XCTAssertEqual(iosResolution.unresolvedMaskNames, ["systemBars"])
    }

    func testCompareScreenshotCanIgnoreNodeOids() throws {
        let expectedData = try Fixtures.makePNGData(width: 4, height: 4, pixels: Array(repeating: [0, 0, 0, 255], count: 16))
        var actualPixels: [[UInt8]] = Array(repeating: [0, 0, 0, 255], count: 16)
        actualPixels[10] = [255, 0, 0, 255]
        actualPixels[11] = [255, 0, 0, 255]
        actualPixels[14] = [255, 0, 0, 255]
        actualPixels[15] = [255, 0, 0, 255]
        let actualData = try Fixtures.makePNGData(width: 4, height: 4, pixels: actualPixels)
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": actualData.base64EncodedString(),
                "byteCount": actualData.count,
                "width": 4,
                "height": 4,
                "scale": 2
            ]
        ]
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UIImageView",
                    "frame": ["x": 1, "y": 1, "width": 1, "height": 1],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
        }
        try expectedData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-screenshot",
            "app-1",
            "--expected",
            expectedURL.path,
            "--ignore-node-oid",
            "2",
            "--threshold",
            "0"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let ignoredNodeRegions = try XCTUnwrap(data["ignoredNodeRegions"] as? [[String: Any]])
        let frameInPixels = try XCTUnwrap(ignoredNodeRegions.first?["frameInPixels"] as? [String: Int])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["mismatchPixels"] as? Int, 0)
        XCTAssertEqual(data["ignoredRegionCount"] as? Int, 1)
        XCTAssertEqual(data["ignoredPixels"] as? Int, 4)
        XCTAssertEqual(data["ignoredNodeRegionCount"] as? Int, 1)
        XCTAssertEqual(data["unresolvedIgnoreNodeOids"] as? [Int], [])
        XCTAssertEqual(ignoredNodeRegions.first?["oid"] as? String, "2")
        XCTAssertEqual(frameInPixels, ["x": 2, "y": 2, "width": 2, "height": 2])
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testCompareScreenshotCanIgnoreNodeQueries() throws {
        let expectedData = try Fixtures.makePNGData(width: 4, height: 4, pixels: Array(repeating: [0, 0, 0, 255], count: 16))
        var actualPixels: [[UInt8]] = Array(repeating: [0, 0, 0, 255], count: 16)
        actualPixels[10] = [255, 0, 0, 255]
        actualPixels[11] = [255, 0, 0, 255]
        actualPixels[14] = [255, 0, 0, 255]
        actualPixels[15] = [255, 0, 0, 255]
        let actualData = try Fixtures.makePNGData(width: 4, height: 4, pixels: actualPixels)
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": actualData.base64EncodedString(),
                "byteCount": actualData.count,
                "width": 4,
                "height": 4,
                "scale": 2
            ]
        ]
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UILabel",
                    "customDisplayTitle": "Timer",
                    "frame": ["x": 1, "y": 1, "width": 1, "height": 1],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
        }
        try expectedData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-screenshot",
            "app-1",
            "--expected",
            expectedURL.path,
            "--ignore-node-query",
            "--query-role",
            "timer",
            "--query-visible-only",
            "--query-limit",
            "1",
            "--threshold",
            "0"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let ignoredQueryRegions = try XCTUnwrap(data["ignoredQueryRegions"] as? [[String: Any]])
        let query = try XCTUnwrap(ignoredQueryRegions.first?["query"] as? [String: Any])
        let frameInPixels = try XCTUnwrap(ignoredQueryRegions.first?["frameInPixels"] as? [String: Int])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["mismatchPixels"] as? Int, 0)
        XCTAssertEqual(data["ignoredRegionCount"] as? Int, 1)
        XCTAssertEqual(data["ignoredPixels"] as? Int, 4)
        XCTAssertEqual(data["ignoredQueryRegionCount"] as? Int, 1)
        XCTAssertEqual((data["unresolvedIgnoreQueries"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(query["semanticRole"] as? String, "timer")
        XCTAssertEqual(ignoredQueryRegions.first?["oid"] as? String, "2")
        XCTAssertEqual(frameInPixels, ["x": 2, "y": 2, "width": 2, "height": 2])
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testCompareScreenshotMatchesAffectedNodesUsingScreenshotScale() throws {
        let expectedData = try Fixtures.makePNGData(width: 8, height: 6, pixels: Array(repeating: [0, 0, 0, 255], count: 48))
        var actualPixels: [[UInt8]] = Array(repeating: [0, 0, 0, 255], count: 48)
        for y in 2..<4 {
            for x in 2..<6 {
                actualPixels[y * 8 + x] = [255, 0, 0, 255]
            }
        }
        let actualData = try Fixtures.makePNGData(width: 8, height: 6, pixels: actualPixels)
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": actualData.base64EncodedString(),
                "byteCount": actualData.count,
                "width": 8,
                "height": 6,
                "scale": 2
            ]
        ]
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UILabel",
                    "customDisplayTitle": "Title",
                    "frame": ["x": 1, "y": 1, "width": 2, "height": 1],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
        }
        try expectedData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-screenshot",
            "app-1",
            "--expected",
            expectedURL.path,
            "--include-nodes"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let affectedNodes = try XCTUnwrap(data["affectedNodes"] as? [[String: Any]])
        let frameInPixels = try XCTUnwrap(affectedNodes.first?["frameInPixels"] as? [String: Double])
        XCTAssertEqual(data["screenshotScale"] as? Double, 2)
        XCTAssertEqual(affectedNodes.count, 1)
        XCTAssertEqual(affectedNodes.first?["overlapArea"] as? Double, 8)
        XCTAssertEqual(affectedNodes.first?["regionOverlapRatio"] as? Double, 1)
        XCTAssertEqual(frameInPixels, ["x": 2, "y": 2, "width": 4, "height": 2])
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testInspectDiffExplainsMismatchRegionsAndLikelyNodes() throws {
        let expectedData = try Fixtures.makePNGData(width: 4, height: 3, pixels: Array(repeating: [0, 0, 0, 255], count: 12))
        var actualPixels: [[UInt8]] = Array(repeating: [0, 0, 0, 255], count: 12)
        actualPixels[5] = [255, 0, 0, 255]
        actualPixels[6] = [255, 0, 0, 255]
        let actualData = try Fixtures.makePNGData(width: 4, height: 3, pixels: actualPixels)
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": actualData.base64EncodedString(),
                "byteCount": actualData.count,
                "width": 4,
                "height": 3,
                "scale": 1
            ]
        ]
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UILabel",
                    "customDisplayTitle": "Title",
                    "frame": ["x": 1, "y": 1, "width": 2, "height": 1],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
        }
        try expectedData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "inspect-diff",
            "app-1",
            "--expected",
            expectedURL.path,
            "--node-limit",
            "3"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("inspect-diff should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let likelyCauses = try XCTUnwrap(data["likelyCauses"] as? [[String: Any]])
        let regionSummaries = try XCTUnwrap(data["regionSummaries"] as? [[String: Any]])
        let followUpCommands = try XCTUnwrap(data["followUpCommands"] as? [[String: Any]])
        let suspectedIssues = try XCTUnwrap(likelyCauses.first?["suspectedIssues"] as? [String])
        XCTAssertEqual(data["passed"] as? Bool, false)
        XCTAssertEqual(data["reason"] as? String, "pixelMismatch")
        XCTAssertEqual(data["mismatchRegionCount"] as? Int, 1)
        XCTAssertEqual(data["affectedNodeCount"] as? Int, 1)
        XCTAssertEqual(likelyCauses.first?["oid"] as? String, "2")
        XCTAssertEqual(likelyCauses.first?["className"] as? String, "UILabel")
        XCTAssertEqual(likelyCauses.first?["summary"] as? String, "UILabel \"Title\" overlaps diff region 0")
        XCTAssertEqual(likelyCauses.first?["confidence"] as? String, "high")
        XCTAssertGreaterThan(likelyCauses.first?["confidenceScore"] as? Double ?? 0, 0.8)
        XCTAssertEqual(suspectedIssues.prefix(3).map { $0 }, ["textOrTypographyMismatch", "styleMismatchCandidate", "layoutMismatchCandidate"])
        XCTAssertEqual(likelyCauses.first?["dominantCategory"] as? String, "typography")
        XCTAssertEqual(likelyCauses.first?["issueCategories"] as? [String], ["typography", "visualStyle", "layout"])
        XCTAssertEqual(likelyCauses.first?["semanticChangeSummary"] as? String, "typography change candidate")
        XCTAssertEqual(likelyCauses.first?["reviewHint"] as? String, "Check typography values for UILabel \"Title\"")
        XCTAssertEqual(regionSummaries.first?["regionIndex"] as? Int, 0)
        XCTAssertEqual(regionSummaries.first?["likelyNodeCount"] as? Int, 1)
        XCTAssertEqual(regionSummaries.first?["dominantIssue"] as? String, "textOrTypographyMismatch")
        XCTAssertEqual(regionSummaries.first?["dominantCategory"] as? String, "typography")
        XCTAssertEqual((data["recommendedNextTools"] as? [String])?.prefix(2).map { $0 }, ["inspect_node", "check_style"])
        XCTAssertEqual(followUpCommands.first?["tool"] as? String, "inspect_node")
        XCTAssertEqual(followUpCommands.first?["cliArguments"] as? [String], ["inspect-node", "app-1", "--oid", "2", "--json"])
        XCTAssertEqual(followUpCommands.dropFirst().first?["tool"] as? String, "summarize_node_detail")
        XCTAssertEqual(followUpCommands.dropFirst().first?["cliArguments"] as? [String], ["summarize-node-detail", "app-1", "22", "--json"])
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testInspectDiffReportsNodeQueryIgnoreMetadata() throws {
        let expectedData = try Fixtures.makePNGData(width: 4, height: 4, pixels: Array(repeating: [0, 0, 0, 255], count: 16))
        var actualPixels: [[UInt8]] = Array(repeating: [0, 0, 0, 255], count: 16)
        actualPixels[10] = [255, 0, 0, 255]
        actualPixels[11] = [255, 0, 0, 255]
        actualPixels[14] = [255, 0, 0, 255]
        actualPixels[15] = [255, 0, 0, 255]
        let actualData = try Fixtures.makePNGData(width: 4, height: 4, pixels: actualPixels)
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": actualData.base64EncodedString(),
                "byteCount": actualData.count,
                "width": 4,
                "height": 4,
                "scale": 2
            ]
        ]
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UILabel",
                    "customDisplayTitle": "Timer",
                    "frame": ["x": 1, "y": 1, "width": 1, "height": 1],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]
        let expectedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            Fixtures.removeFileIfNeeded(expectedURL)
        }
        try expectedData.write(to: expectedURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "inspect-diff",
            "app-1",
            "--expected",
            expectedURL.path,
            "--ignore-node-query",
            "--query-class",
            "UILabel",
            "--query-text",
            "Timer",
            "--query-limit",
            "1",
            "--threshold",
            "0"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("inspect-diff should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["ignoredRegionCount"] as? Int, 1)
        XCTAssertEqual(data["ignoredPixels"] as? Int, 4)
        XCTAssertEqual(data["ignoredQueryRegionCount"] as? Int, 1)
        XCTAssertEqual((data["ignoredQueryRegions"] as? [[String: Any]])?.first?["text"] as? String, "Timer")
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testInspectDiffUsesBaselineSemanticDifferencesForLikelyCauses() throws {
        let expectedData = try Fixtures.makePNGData(width: 4, height: 3, pixels: Array(repeating: [0, 0, 0, 255], count: 12))
        var actualPixels: [[UInt8]] = Array(repeating: [0, 0, 0, 255], count: 12)
        actualPixels[5] = [255, 0, 0, 255]
        actualPixels[6] = [255, 0, 0, 255]
        let actualData = try Fixtures.makePNGData(width: 4, height: 3, pixels: actualPixels)
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": actualData.base64EncodedString(),
                "byteCount": actualData.count,
                "width": 4,
                "height": 3,
                "scale": 1
            ]
        ]
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UILabel",
                    "customDisplayTitle": "Title",
                    "frame": ["x": 1, "y": 1, "width": 2, "height": 1],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]
        service.detailsByOid["22"] = Fixtures.makeNodeDetail(
            oid: "22",
            attributes: [
                Fixtures.makeNodeAttribute(identifier: "fontSize", value: 12),
                Fixtures.makeNodeAttribute(identifier: "textColor", value: [0, 0, 1, 1], attrTypeName: "color")
            ]
        )
        let baselineDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: baselineDir, withIntermediateDirectories: true)
        let screenshotURL = baselineDir.appendingPathComponent("home.png")
        let nodeIndexURL = baselineDir.appendingPathComponent("home.nodes.json")
        let nodeDetailsURL = baselineDir.appendingPathComponent("home.node-details.json")
        let manifestURL = baselineDir.appendingPathComponent("home.baseline.json")
        defer {
            Fixtures.removeFileIfNeeded(baselineDir)
        }
        try expectedData.write(to: screenshotURL)
        try Fixtures.writeJSONObject([
            "schemaVersion": 2,
            "nodeCount": 1,
            "nodes": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UILabel",
                    "text": "Title",
                    "frame": ["x": 1, "y": 1, "width": 2, "height": 1],
                    "visible": true,
                    "alpha": 1,
                    "hierarchyPath": "UILabel[0]"
                ]
            ]
        ], to: nodeIndexURL)
        try Fixtures.writeJSONObject([
            "schemaVersion": 2,
            "detailCount": 1,
            "failedDetailCount": 0,
            "details": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UILabel",
                    "text": "Title",
                    "hierarchyPath": "UILabel[0]",
                    "attributeCount": 2,
                    "semanticAttributeCount": 2,
                    "semanticAttributes": [
                        "fontSize": [
                            "semanticName": "fontSize",
                            "semanticPath": "label.fontSize",
                            "value": 14,
                            "valuePreview": "14"
                        ],
                        "textColor": [
                            "semanticName": "textColor",
                            "semanticPath": "label.textColor",
                            "value": [1, 0, 0, 1],
                            "valuePreview": "1,0,0,1",
                            "colorHex": "#FF0000"
                        ]
                    ]
                ]
            ],
            "failures": []
        ], to: nodeDetailsURL)
        try Fixtures.writeJSONObject([
            "schemaVersion": 2,
            "kind": "astrolabe-baseline",
            "name": "home",
            "files": [
                "screenshot": "home.png",
                "nodeIndex": "home.nodes.json",
                "nodeDetails": "home.node-details.json"
            ]
        ], to: manifestURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "inspect-diff",
            "app-1",
            "--baseline",
            manifestURL.path,
            "--node-limit",
            "3",
            "--threshold",
            "0"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("inspect-diff should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let compactComparison = try XCTUnwrap(data["comparison"] as? [String: Any])
        let baselineNodeComparison = try XCTUnwrap(data["baselineNodeComparison"] as? [String: Any])
        let comparisons = try XCTUnwrap(baselineNodeComparison["comparisons"] as? [[String: Any]])
        let likelyCauses = try XCTUnwrap(data["likelyCauses"] as? [[String: Any]])
        let firstCause = try XCTUnwrap(likelyCauses.first)
        let suspectedIssues = try XCTUnwrap(firstCause["suspectedIssues"] as? [String])
        let detailChanges = try XCTUnwrap(firstCause["baselineDetailChanges"] as? [[String: Any]])
        let regionSummaries = try XCTUnwrap(data["regionSummaries"] as? [[String: Any]])
        XCTAssertEqual(compactComparison["baselinePath"] as? String, manifestURL.path)
        XCTAssertEqual(compactComparison["baselineName"] as? String, "home")
        XCTAssertEqual(compactComparison["baselineNodeIndexPath"] as? String, nodeIndexURL.path)
        XCTAssertEqual(compactComparison["baselineNodeDetailIndexPath"] as? String, nodeDetailsURL.path)
        XCTAssertEqual(baselineNodeComparison["changedNodeCount"] as? Int, 1)
        XCTAssertEqual(comparisons.first?["detailChangeCount"] as? Int, 2)
        XCTAssertEqual(firstCause["oid"] as? String, "2")
        XCTAssertEqual(firstCause["baselineMatchStrategy"] as? String, "hierarchyPath")
        XCTAssertEqual(firstCause["baselineChangeCount"] as? Int, 2)
        XCTAssertEqual(firstCause["baselineDetailChangeCount"] as? Int, 2)
        XCTAssertEqual(suspectedIssues.prefix(2).map { $0 }, ["fontSizeChanged", "textColorChanged"])
        XCTAssertEqual(firstCause["dominantCategory"] as? String, "typography")
        XCTAssertEqual(firstCause["issueCategories"] as? [String], ["typography"])
        XCTAssertEqual(firstCause["semanticChangeSummary"] as? String, "typography: semantic.fontSize, semantic.textColor")
        XCTAssertEqual(firstCause["reviewHint"] as? String, "Check typography values for UILabel \"Title\": semantic.fontSize, semantic.textColor")
        XCTAssertEqual(detailChanges.compactMap { $0["field"] as? String }, ["semantic.fontSize", "semantic.textColor"])
        XCTAssertEqual(detailChanges.compactMap { $0["issue"] as? String }, ["fontSizeChanged", "textColorChanged"])
        XCTAssertEqual(regionSummaries.first?["dominantIssue"] as? String, "fontSizeChanged")
        XCTAssertEqual(regionSummaries.first?["dominantCategory"] as? String, "typography")
        XCTAssertEqual((regionSummaries.first?["likelyNodes"] as? [[String: Any]])?.first?["dominantCategory"] as? String, "typography")
        XCTAssertTrue((firstCause["summary"] as? String ?? "").contains("semantic.fontSize"))
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1"), .fetchNodeDetail("app-1", "22")])
    }

}

private struct FixedNamedMaskResolver: ScreenshotNamedMaskResolving {
    func resolve(
        maskNames: [String],
        imageWidth: Int,
        imageHeight: Int,
        screenshotScale: Double
    ) -> ScreenshotNamedMaskResolution {
        ScreenshotNamedMaskResolution(
            ignoreRegions: [
                ScreenshotIgnoreRegion(x: 0, y: 0, width: imageWidth, height: 24)
            ],
            ignoredMaskRegions: [["name": "systemBars"]],
            unresolvedMaskNames: []
        )
    }
}
