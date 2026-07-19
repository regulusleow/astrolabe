//
//  CaptureHierarchyCommandTests.swift
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

final class CaptureHierarchyCommandTests: XCTestCase {
    func testCaptureHierarchyRequiresAppId() {
        XCTAssertThrowsError(try Fixtures.makeRunner(service: Fixtures.FakeInspectorService()).run(arguments: ["capture-hierarchy"])) { error in
            XCTAssertEqual(String(describing: error), "Missing argument: appId")
        }
    }

    func testCaptureHierarchyReturnsJSONObjectOutput() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = ["root": ["className": "UIView"]]

        let output = try Fixtures.makeRunner(service: service).run(arguments: ["capture-hierarchy", "app-1"])

        guard case .jsonObject(let object) = output else {
            return XCTFail("capture-hierarchy should return jsonObject output")
        }
        XCTAssertEqual(object["success"] as? Bool, true)
        XCTAssertEqual((object["data"] as? [String: Any])?["root"] as? [String: String], ["className": "UIView"])
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testCaptureHierarchyCanBoundLargeTreeOutput() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "1",
                    "className": "UIWindow",
                    "subitems": [
                        [
                            "oid": "2",
                            "className": "UIView",
                            "subitems": [
                                ["oid": "3", "className": "UILabel"]
                            ]
                        ],
                        ["oid": "4", "className": "UIButton"]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "capture-hierarchy",
            "app-1",
            "--node-limit",
            "2",
            "--max-depth",
            "1"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("capture-hierarchy should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let roots = try XCTUnwrap(data["displayItems"] as? [[String: Any]])
        let children = try XCTUnwrap(roots.first?["subitems"] as? [[String: Any]])
        XCTAssertEqual(data["nodeCount"] as? Int, 4)
        XCTAssertEqual(data["returnedNodeCount"] as? Int, 2)
        XCTAssertEqual(data["omittedNodeCount"] as? Int, 2)
        XCTAssertEqual(data["truncated"] as? Bool, true)
        XCTAssertEqual(data["nodeLimit"] as? Int, 2)
        XCTAssertEqual(data["maxDepth"] as? Int, 1)
        XCTAssertEqual(roots.first?["oid"] as? String, "1")
        XCTAssertEqual(children.first?["oid"] as? String, "2")
        XCTAssertNil(children.first?["subitems"])
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testCaptureHierarchyPersistsCommonAndPlatformSemanticRoles() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [[
                "oid": "1",
                "className": "UserAvatarImageView",
                "classChain": ["UserAvatarImageView", "UIImageView", "UIView"]
            ]]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "capture-hierarchy",
            "app-1"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("capture-hierarchy should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let roots = try XCTUnwrap(data["displayItems"] as? [[String: Any]])
        XCTAssertEqual(roots.first?["semanticRoles"] as? [String], [
            "avatar",
            "image"
        ])
    }

}
