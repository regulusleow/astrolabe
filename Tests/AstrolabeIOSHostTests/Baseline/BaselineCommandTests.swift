//
//  BaselineCommandTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeProtocol
import AstrolabeIOSInspection
import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import AstrolabeCLI

private typealias Fixtures = CLICommandTestFixtures

final class BaselineCommandTests: XCTestCase {
    func testRecordBaselineWritesManifestScreenshotAndHierarchy() throws {
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
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "1",
                    "detailOid": "11",
                    "className": "UIWindow",
                    "frame": ["x": 0, "y": 0, "width": 1, "height": 1],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]
        service.detailsByOid["11"] = Fixtures.makeNodeDetail(
            oid: "11",
            attributes: [
                Fixtures.makeNodeAttribute(identifier: "backgroundColor", value: [1, 0, 0, 1], attrTypeName: "color")
            ]
        )
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            Fixtures.removeFileIfNeeded(outputDir)
        }

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "record-baseline",
            "app-1",
            "--output-dir",
            outputDir.path,
            "--name",
            "home",
            "--ignore-region",
            "0",
            "0",
            "1",
            "1"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("record-baseline should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let files = try XCTUnwrap(data["files"] as? [String: String])
        XCTAssertEqual(data["name"] as? String, "home")
        XCTAssertTrue(FileManager.default.fileExists(atPath: files["manifestPath"] ?? ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files["screenshotPath"] ?? ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files["hierarchyPath"] ?? ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files["nodeIndexPath"] ?? ""))
        XCTAssertTrue(FileManager.default.fileExists(atPath: files["nodeDetailsPath"] ?? ""))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: files["screenshotPath"] ?? "")), pngData)
        let nodeIndexData = try Data(contentsOf: URL(fileURLWithPath: files["nodeIndexPath"] ?? ""))
        let nodeIndex = try XCTUnwrap(JSONSerialization.jsonObject(with: nodeIndexData) as? [String: Any])
        let nodes = try XCTUnwrap(nodeIndex["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodeIndex["nodeCount"] as? Int, 1)
        XCTAssertEqual(nodes.first?["className"] as? String, "UIWindow")
        XCTAssertEqual(nodes.first?["hierarchyPath"] as? String, "UIWindow[0]")
        let nodeDetailsData = try Data(contentsOf: URL(fileURLWithPath: files["nodeDetailsPath"] ?? ""))
        let nodeDetails = try XCTUnwrap(JSONSerialization.jsonObject(with: nodeDetailsData) as? [String: Any])
        let details = try XCTUnwrap(nodeDetails["details"] as? [[String: Any]])
        let semanticAttributes = try XCTUnwrap(details.first?["semanticAttributes"] as? [String: [String: Any]])
        XCTAssertEqual(nodeDetails["detailCount"] as? Int, 1)
        XCTAssertEqual(semanticAttributes["backgroundColor"]?["colorHex"] as? String, "#FF0000")
        let masks = try XCTUnwrap(data["masks"] as? [String: Any])
        let ignoreRegions = try XCTUnwrap(masks["ignoreRegions"] as? [[String: Any]])
        XCTAssertEqual(ignoreRegions.first?["x"] as? Int, 0)
        XCTAssertEqual(ignoreRegions.first?["y"] as? Int, 0)
        XCTAssertEqual(ignoreRegions.first?["width"] as? Int, 1)
        XCTAssertEqual(ignoreRegions.first?["height"] as? Int, 1)
        let manifestData = try Data(contentsOf: URL(fileURLWithPath: files["manifestPath"] ?? ""))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let manifestFiles = try XCTUnwrap(manifest["files"] as? [String: String])
        XCTAssertEqual(manifestFiles["nodeIndex"], "home.nodes.json")
        XCTAssertEqual(manifestFiles["nodeDetails"], "home.node-details.json")
        let manifestNodeIndex = try XCTUnwrap(manifest["nodeIndex"] as? [String: Any])
        XCTAssertEqual(manifestNodeIndex["nodeCount"] as? Int, 1)
        let manifestNodeDetails = try XCTUnwrap(manifest["nodeDetails"] as? [String: Any])
        XCTAssertEqual(manifestNodeDetails["detailCount"] as? Int, 1)
        let manifestMasks = try XCTUnwrap(manifest["masks"] as? [String: Any])
        XCTAssertEqual((manifestMasks["ignoreRegions"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1"), .fetchNodeDetail("app-1", "11")])
    }

    func testRecordBaselineCanPersistNodeIgnoreRegions() throws {
        let pngData = try Fixtures.makePNGData(width: 4, height: 4, pixels: Array(repeating: [0, 0, 0, 255], count: 16))
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": pngData.base64EncodedString(),
                "byteCount": pngData.count,
                "width": 4,
                "height": 4,
                "scale": 2
            ]
        ]
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "7",
                    "detailOid": "77",
                    "className": "UILabel",
                    "frame": ["x": 1, "y": 1, "width": 1, "height": 1],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            Fixtures.removeFileIfNeeded(outputDir)
        }

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "record-baseline",
            "app-1",
            "--output-dir",
            outputDir.path,
            "--name",
            "home",
            "--ignore-node-oid",
            "7"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("record-baseline should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let files = try XCTUnwrap(data["files"] as? [String: String])
        let masks = try XCTUnwrap(data["masks"] as? [String: Any])
        let ignoreRegions = try XCTUnwrap(masks["ignoreRegions"] as? [[String: Any]])
        let ignoredNodeRegions = try XCTUnwrap(masks["ignoredNodeRegions"] as? [[String: Any]])
        XCTAssertEqual(ignoreRegions.first?["x"] as? Int, 2)
        XCTAssertEqual(ignoreRegions.first?["y"] as? Int, 2)
        XCTAssertEqual(ignoreRegions.first?["width"] as? Int, 2)
        XCTAssertEqual(ignoreRegions.first?["height"] as? Int, 2)
        XCTAssertEqual(ignoredNodeRegions.first?["oid"] as? String, "7")
        let manifestData = try Data(contentsOf: URL(fileURLWithPath: files["manifestPath"] ?? ""))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let manifestMasks = try XCTUnwrap(manifest["masks"] as? [String: Any])
        XCTAssertEqual((manifestMasks["ignoredNodeRegions"] as? [[String: Any]])?.first?["oid"] as? String, "7")
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1"), .fetchNodeDetail("app-1", "77")])
    }

    func testRecordBaselineCanPersistNamedMaskRegions() throws {
        let pngData = try Fixtures.makePNGData(width: 100, height: 100, pixels: Array(repeating: [0, 0, 0, 255], count: 10_000))
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": pngData.base64EncodedString(),
                "byteCount": pngData.count,
                "width": 100,
                "height": 100,
                "scale": 1
            ]
        ]
        service.hierarchy = ["appId": "app-1", "displayItems": []]
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            Fixtures.removeFileIfNeeded(outputDir)
        }

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "record-baseline",
            "app-1",
            "--output-dir",
            outputDir.path,
            "--name",
            "home",
            "--ignore-mask",
            "navigationBar"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("record-baseline should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let files = try XCTUnwrap(data["files"] as? [String: String])
        let masks = try XCTUnwrap(data["masks"] as? [String: Any])
        let ignoreRegions = try XCTUnwrap(masks["ignoreRegions"] as? [[String: Any]])
        let ignoredMaskRegions = try XCTUnwrap(masks["ignoredMaskRegions"] as? [[String: Any]])
        let maskRegion = try XCTUnwrap(ignoredMaskRegions.first?["ignoreRegion"] as? [String: Any])
        XCTAssertEqual(ignoreRegions.first?["x"] as? Int, 0)
        XCTAssertEqual(ignoreRegions.first?["y"] as? Int, 0)
        XCTAssertEqual(ignoreRegions.first?["width"] as? Int, 100)
        XCTAssertEqual(ignoreRegions.first?["height"] as? Int, 88)
        XCTAssertEqual(ignoredMaskRegions.first?["name"] as? String, "navigationBar")
        XCTAssertEqual(ignoredMaskRegions.first?["requestedName"] as? String, "navigationBar")
        XCTAssertEqual(maskRegion["height"] as? Int, 88)
        XCTAssertEqual(masks["unresolvedIgnoreMasks"] as? [String], [])
        let manifestData = try Data(contentsOf: URL(fileURLWithPath: files["manifestPath"] ?? ""))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let manifestMasks = try XCTUnwrap(manifest["masks"] as? [String: Any])
        XCTAssertEqual((manifestMasks["ignoredMaskRegions"] as? [[String: Any]])?.first?["name"] as? String, "navigationBar")
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testRecordBaselineCanPersistNodeQueryIgnoreRegions() throws {
        let pngData = try Fixtures.makePNGData(width: 4, height: 4, pixels: Array(repeating: [0, 0, 0, 255], count: 16))
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": pngData.base64EncodedString(),
                "byteCount": pngData.count,
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
                    "customDisplayTitle": "00:12",
                    "frame": ["x": 1, "y": 1, "width": 1, "height": 1],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]
        service.detailsByOid["22"] = Fixtures.makeNodeDetail(oid: "22", attributes: [])
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            Fixtures.removeFileIfNeeded(outputDir)
        }

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "record-baseline",
            "app-1",
            "--output-dir",
            outputDir.path,
            "--name",
            "home",
            "--ignore-node-query",
            "--query-class",
            "UILabel",
            "--query-text",
            "00:12",
            "--query-role",
            "timer",
            "--query-visible-only",
            "--query-limit",
            "1"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("record-baseline should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let files = try XCTUnwrap(data["files"] as? [String: String])
        let masks = try XCTUnwrap(data["masks"] as? [String: Any])
        let ignoreRegions = try XCTUnwrap(masks["ignoreRegions"] as? [[String: Any]])
        let ignoredQueryRegions = try XCTUnwrap(masks["ignoredQueryRegions"] as? [[String: Any]])
        let query = try XCTUnwrap(ignoredQueryRegions.first?["query"] as? [String: Any])
        XCTAssertEqual(ignoreRegions.first?["x"] as? Int, 2)
        XCTAssertEqual(ignoreRegions.first?["y"] as? Int, 2)
        XCTAssertEqual(ignoreRegions.first?["width"] as? Int, 2)
        XCTAssertEqual(ignoreRegions.first?["height"] as? Int, 2)
        XCTAssertEqual(ignoredQueryRegions.first?["oid"] as? String, "2")
        XCTAssertEqual(ignoredQueryRegions.first?["matchIndex"] as? Int, 0)
        XCTAssertEqual(ignoredQueryRegions.first?["totalMatchCount"] as? Int, 1)
        XCTAssertEqual(query["className"] as? String, "UILabel")
        XCTAssertEqual(query["text"] as? String, "00:12")
        XCTAssertEqual(query["semanticRole"] as? String, "timer")
        XCTAssertEqual(query["visibleOnly"] as? Bool, true)
        XCTAssertEqual(query["limit"] as? Int, 1)
        XCTAssertEqual((masks["unresolvedIgnoreQueries"] as? [[String: Any]])?.count, 0)
        let manifestData = try Data(contentsOf: URL(fileURLWithPath: files["manifestPath"] ?? ""))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: manifestData) as? [String: Any])
        let manifestMasks = try XCTUnwrap(manifest["masks"] as? [String: Any])
        XCTAssertEqual((manifestMasks["ignoredQueryRegions"] as? [[String: Any]])?.first?["oid"] as? String, "2")
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1"), .fetchNodeDetail("app-1", "22")])
    }

    func testCompareBaselineUsesManifestScreenshotAndMasks() throws {
        let pngData = try Fixtures.makePNGData(width: 1, height: 1, pixels: [[0, 0, 0, 255]])
        let actualData = try Fixtures.makePNGData(width: 1, height: 1, pixels: [[255, 0, 0, 255]])
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": actualData.base64EncodedString(),
                "byteCount": actualData.count,
                "width": 1,
                "height": 1,
                "scale": 1
            ]
        ]
        let baselineDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: baselineDir, withIntermediateDirectories: true)
        let screenshotURL = baselineDir.appendingPathComponent("home.png")
        let manifestURL = baselineDir.appendingPathComponent("home.baseline.json")
        defer {
            Fixtures.removeFileIfNeeded(baselineDir)
        }
        try pngData.write(to: screenshotURL)
        try Fixtures.writeJSONObject([
            "schemaVersion": 2,
            "kind": "astrolabe-baseline",
            "name": "home",
            "files": [
                "screenshot": "home.png"
            ],
            "masks": [
                "ignoreRegions": [
                    ["x": 0, "y": 0, "width": 1, "height": 1]
                ]
            ]
        ], to: manifestURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-baseline",
            "app-1",
            "--baseline",
            manifestURL.path,
            "--threshold",
            "0"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-baseline should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["ignoredRegionCount"] as? Int, 1)
        XCTAssertEqual(data["ignoredPixels"] as? Int, 1)
        XCTAssertEqual(data["baselinePath"] as? String, manifestURL.path)
        XCTAssertEqual(data["baselineName"] as? String, "home")
        XCTAssertEqual(data["expectedPath"] as? String, screenshotURL.path)
        XCTAssertEqual(service.calls, [])
    }

    func testCompareBaselineReportsManifestNodeQueryIgnoreMetadata() throws {
        let pngData = try Fixtures.makePNGData(width: 4, height: 4, pixels: Array(repeating: [0, 0, 0, 255], count: 16))
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
        let baselineDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: baselineDir, withIntermediateDirectories: true)
        let screenshotURL = baselineDir.appendingPathComponent("home.png")
        let manifestURL = baselineDir.appendingPathComponent("home.baseline.json")
        defer {
            Fixtures.removeFileIfNeeded(baselineDir)
        }
        try pngData.write(to: screenshotURL)
        try Fixtures.writeJSONObject([
            "schemaVersion": 2,
            "kind": "astrolabe-baseline",
            "name": "home",
            "files": [
                "screenshot": "home.png"
            ],
            "masks": [
                "ignoreRegions": [
                    ["x": 2, "y": 2, "width": 2, "height": 2]
                ],
                "ignoredQueryRegions": [
                    [
                        "oid": "2",
                        "className": "UILabel",
                        "text": "Timer",
                        "query": ["className": "UILabel", "text": "Timer", "visibleOnly": true, "limit": 1],
                        "queryIndex": 0,
                        "matchIndex": 0,
                        "totalMatchCount": 1,
                        "limit": 1,
                        "ignoreRegion": ["x": 2, "y": 2, "width": 2, "height": 2]
                    ]
                ],
                "unresolvedIgnoreQueries": []
            ]
        ], to: manifestURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-baseline",
            "app-1",
            "--baseline",
            manifestURL.path,
            "--threshold",
            "0"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-baseline should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let ignoredQueryRegions = try XCTUnwrap(data["ignoredQueryRegions"] as? [[String: Any]])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["ignoredRegionCount"] as? Int, 1)
        XCTAssertEqual(data["ignoredPixels"] as? Int, 4)
        XCTAssertEqual(data["ignoredQueryRegionCount"] as? Int, 1)
        XCTAssertEqual(ignoredQueryRegions.first?["text"] as? String, "Timer")
        XCTAssertEqual((data["unresolvedIgnoreQueries"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(service.calls, [])
    }

    func testCompareBaselineAcceptsManifestWithoutMasks() throws {
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
        let baselineDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: baselineDir, withIntermediateDirectories: true)
        let screenshotURL = baselineDir.appendingPathComponent("legacy.png")
        let manifestURL = baselineDir.appendingPathComponent("legacy.baseline.json")
        defer {
            Fixtures.removeFileIfNeeded(baselineDir)
        }
        try pngData.write(to: screenshotURL)
        try Fixtures.writeJSONObject([
            "schemaVersion": 2,
            "kind": "astrolabe-baseline",
            "name": "legacy",
            "files": [
                "screenshot": "legacy.png"
            ]
        ], to: manifestURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-baseline",
            "app-1",
            "--baseline",
            manifestURL.path
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-baseline should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["ignoredRegionCount"] as? Int, 0)
        XCTAssertEqual(data["baselineName"] as? String, "legacy")
        XCTAssertEqual(data["expectedPath"] as? String, screenshotURL.path)
    }

    func testCompareBaselineRequiresRegenerationForV1Manifest() throws {
        let baselineDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: baselineDir,
            withIntermediateDirectories: true
        )
        let manifestURL = baselineDir.appendingPathComponent("future.baseline.json")
        defer { Fixtures.removeFileIfNeeded(baselineDir) }
        try Fixtures.writeJSONObject([
            "schemaVersion": 1,
            "kind": "astrolabe-baseline",
            "files": ["screenshot": "future.png"]
        ], to: manifestURL)

        XCTAssertThrowsError(
            try Fixtures.makeRunner(service: Fixtures.FakeInspectorService()).run(arguments: [
                "compare-baseline",
                "app-1",
                "--baseline",
                manifestURL.path
            ])
        ) { error in
            XCTAssertEqual(CLIError.code(for: error), "invalid_baseline")
            XCTAssertEqual(
                CLIError.recoverySuggestion(for: error),
                "Use a manifest generated by the current record-baseline command"
            )
        }
    }

    func testBaselineComparisonRejectsPathMatchWithDifferentIdentity() throws {
        let comparison = BaselineNodeComparisonBuilder().buildComparison(
            appId: "app-1",
            baselineNodes: [
                [
                    "oid": "1",
                    "className": "UIButton",
                    "text": "Save",
                    "hierarchyPath": "UIWindow[0]/Content[0]",
                    "frame": ["x": 0, "y": 0, "width": 100, "height": 40]
                ],
                [
                    "oid": "2",
                    "className": "UILabel",
                    "text": "Title",
                    "hierarchyPath": "UIWindow[0]/Content[1]",
                    "frame": ["x": 0, "y": 50, "width": 100, "height": 20]
                ]
            ],
            currentNodes: [
                [
                    "oid": "3",
                    "className": "UILabel",
                    "text": "Title",
                    "hierarchyPath": "UIWindow[0]/Content[0]",
                    "frame": ["x": 0, "y": 50, "width": 100, "height": 20]
                ]
            ]
        )
        let comparisons = try XCTUnwrap(
            comparison["comparisons"] as? [[String: Any]]
        )

        XCTAssertEqual(comparisons.first?["matchStrategy"] as? String, "classAndText")
        let baselineNode = try XCTUnwrap(
            comparisons.first?["baselineNode"] as? [String: Any]
        )
        XCTAssertEqual(baselineNode["oid"] as? String, "2")
    }

    func testBaselineComparisonDoesNotReuseOneBaselineNode() throws {
        let baselineNode: [String: Any] = [
            "oid": "1",
            "className": "UILabel",
            "text": "Title",
            "hierarchyPath": "UIWindow[0]/UILabel[0]",
            "frame": ["x": 0, "y": 0, "width": 100, "height": 20]
        ]
        let currentNode: [String: Any] = [
            "oid": "2",
            "className": "UILabel",
            "text": "Title",
            "hierarchyPath": "",
            "frame": ["x": 0, "y": 0, "width": 100, "height": 20]
        ]

        let comparison = BaselineNodeComparisonBuilder().buildComparison(
            appId: "app-1",
            baselineNodes: [baselineNode],
            currentNodes: [currentNode, currentNode]
        )
        let comparisons = try XCTUnwrap(
            comparison["comparisons"] as? [[String: Any]]
        )

        XCTAssertEqual(comparisons.map { $0["matched"] as? Bool }, [true, false])
    }

    func testBaselineComparisonUsesNearestNodeForDuplicateClassAndText() throws {
        let comparison = BaselineNodeComparisonBuilder().buildComparison(
            appId: "app-1",
            baselineNodes: [
                [
                    "oid": "1",
                    "className": "UILabel",
                    "text": "Title",
                    "hierarchyPath": "",
                    "frame": ["x": 0, "y": 0, "width": 100, "height": 20]
                ],
                [
                    "oid": "2",
                    "className": "UILabel",
                    "text": "Title",
                    "hierarchyPath": "",
                    "frame": ["x": 0, "y": 100, "width": 100, "height": 20]
                ]
            ],
            currentNodes: [
                [
                    "oid": "3",
                    "className": "UILabel",
                    "text": "Title",
                    "hierarchyPath": "",
                    "frame": ["x": 0, "y": 100, "width": 100, "height": 20]
                ]
            ]
        )
        let comparisons = try XCTUnwrap(
            comparison["comparisons"] as? [[String: Any]]
        )
        let baselineNode = try XCTUnwrap(
            comparisons.first?["baselineNode"] as? [String: Any]
        )

        XCTAssertEqual(baselineNode["oid"] as? String, "2")
    }

    func testCompareBaselineReportsBaselineNodeDifferences() throws {
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
                    "customDisplayTitle": "New",
                    "frame": ["x": 1, "y": 1, "width": 3, "height": 1],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]
        let baselineDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: baselineDir, withIntermediateDirectories: true)
        let screenshotURL = baselineDir.appendingPathComponent("home.png")
        let nodeIndexURL = baselineDir.appendingPathComponent("home.nodes.json")
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
                    "text": "Old",
                    "frame": ["x": 1, "y": 1, "width": 2, "height": 1],
                    "visible": true,
                    "alpha": 1,
                    "hierarchyPath": "UILabel[0]"
                ]
            ]
        ], to: nodeIndexURL)
        try Fixtures.writeJSONObject([
            "schemaVersion": 2,
            "kind": "astrolabe-baseline",
            "name": "home",
            "files": [
                "screenshot": "home.png",
                "nodeIndex": "home.nodes.json"
            ]
        ], to: manifestURL)

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "compare-baseline",
            "app-1",
            "--baseline",
            manifestURL.path,
            "--include-nodes",
            "--node-limit",
            "3",
            "--threshold",
            "0"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-baseline should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let baselineNodeComparison = try XCTUnwrap(data["baselineNodeComparison"] as? [String: Any])
        let comparisons = try XCTUnwrap(baselineNodeComparison["comparisons"] as? [[String: Any]])
        let firstComparison = try XCTUnwrap(comparisons.first)
        let currentNode = try XCTUnwrap(firstComparison["currentNode"] as? [String: Any])
        let baselineNode = try XCTUnwrap(firstComparison["baselineNode"] as? [String: Any])
        let changes = try XCTUnwrap(firstComparison["changes"] as? [[String: Any]])
        XCTAssertEqual(baselineNodeComparison["baselineNodeCount"] as? Int, 1)
        XCTAssertEqual(baselineNodeComparison["affectedNodeCount"] as? Int, 1)
        XCTAssertEqual(baselineNodeComparison["matchedNodeCount"] as? Int, 1)
        XCTAssertEqual(baselineNodeComparison["changedNodeCount"] as? Int, 1)
        XCTAssertEqual(data["baselineNodeIndexPath"] as? String, nodeIndexURL.path)
        XCTAssertEqual(firstComparison["matched"] as? Bool, true)
        XCTAssertEqual(firstComparison["matchStrategy"] as? String, "hierarchyPath")
        XCTAssertEqual(firstComparison["changeCount"] as? Int, 2)
        XCTAssertEqual(currentNode["text"] as? String, "New")
        XCTAssertEqual(baselineNode["text"] as? String, "Old")
        XCTAssertEqual(changes.compactMap { $0["field"] as? String }, ["text", "frame.width"])
        XCTAssertEqual(changes.compactMap { $0["issue"] as? String }, ["textChanged", "frameChanged"])
        XCTAssertEqual(firstComparison["suspectedIssues"] as? [String], ["textChanged", "frameChanged"])
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testCompareBaselineReportsSemanticNodeDetailDifferences() throws {
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
            "compare-baseline",
            "app-1",
            "--baseline",
            manifestURL.path,
            "--include-nodes",
            "--node-limit",
            "3",
            "--threshold",
            "0"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("compare-baseline should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let baselineNodeComparison = try XCTUnwrap(data["baselineNodeComparison"] as? [String: Any])
        let comparisons = try XCTUnwrap(baselineNodeComparison["comparisons"] as? [[String: Any]])
        let firstComparison = try XCTUnwrap(comparisons.first)
        let detailChanges = try XCTUnwrap(firstComparison["detailChanges"] as? [[String: Any]])
        XCTAssertEqual(data["baselineNodeDetailIndexPath"] as? String, nodeDetailsURL.path)
        XCTAssertEqual(baselineNodeComparison["baselineNodeDetailCount"] as? Int, 1)
        XCTAssertEqual(baselineNodeComparison["currentNodeDetailCount"] as? Int, 1)
        XCTAssertEqual(firstComparison["detailChangeCount"] as? Int, 2)
        XCTAssertEqual(firstComparison["changeCount"] as? Int, 2)
        XCTAssertEqual(detailChanges.compactMap { $0["field"] as? String }, ["semantic.fontSize", "semantic.textColor"])
        XCTAssertEqual(detailChanges.compactMap { $0["issue"] as? String }, ["fontSizeChanged", "textColorChanged"])
        XCTAssertEqual(detailChanges.first?["expected"] as? Int, 14)
        XCTAssertEqual(detailChanges.first?["actual"] as? Int, 12)
        XCTAssertEqual(detailChanges.dropFirst().first?["expected"] as? String, "#FF0000")
        XCTAssertEqual(detailChanges.dropFirst().first?["actual"] as? String, "#0000FF")
        XCTAssertEqual(firstComparison["suspectedIssues"] as? [String], ["fontSizeChanged", "textColorChanged"])
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1"), .fetchNodeDetail("app-1", "22")])
    }

    func testBaselineNodeDetailComparisonClassifiesExpandedSemanticIssues() throws {
        let builder = BaselineNodeDetailComparisonBuilder(
            issueClassifier: UIKitNodeDetailSemanticIssueInterpreter()
        )
        let baselineDetail = Fixtures.makeBaselineDetailSemanticAttributes([
            "contentInsets": Fixtures.makeSemanticAttribute(name: "contentInsets", path: "button.contentInsets", value: "{8,12,8,12}"),
            "enabled": Fixtures.makeSemanticAttribute(name: "enabled", path: "control.enabled", value: true),
            "horizontalContentHuggingPriority": Fixtures.makeSemanticAttribute(name: "horizontalContentHuggingPriority", path: "autoLayout.horizontalContentHuggingPriority", value: 251),
            "imageName": Fixtures.makeSemanticAttribute(name: "imageName", path: "imageView.imageName", value: "avatar_hannah")
        ])
        let currentDetail = Fixtures.makeBaselineDetailSemanticAttributes([
            "contentInsets": Fixtures.makeSemanticAttribute(name: "contentInsets", path: "button.contentInsets", value: "{6,10,6,10}"),
            "enabled": Fixtures.makeSemanticAttribute(name: "enabled", path: "control.enabled", value: false),
            "horizontalContentHuggingPriority": Fixtures.makeSemanticAttribute(name: "horizontalContentHuggingPriority", path: "autoLayout.horizontalContentHuggingPriority", value: 250),
            "imageName": Fixtures.makeSemanticAttribute(name: "imageName", path: "imageView.imageName", value: "avatar_me")
        ])

        let changes = builder.compare(
            appId: "app-1",
            baselineDetail: baselineDetail,
            currentDetail: currentDetail
        )

        XCTAssertEqual(changes.compactMap { $0["semanticName"] as? String }, [
            "contentInsets",
            "enabled",
            "horizontalContentHuggingPriority",
            "imageName"
        ])
        XCTAssertEqual(changes.compactMap { $0["issue"] as? String }, [
            "layoutInsetChanged",
            "controlStateChanged",
            "autoLayoutChanged",
            "imageChanged"
        ])
    }

}
