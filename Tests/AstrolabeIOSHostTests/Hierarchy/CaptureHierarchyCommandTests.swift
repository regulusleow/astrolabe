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
    func testSemanticWrapperUsesOnlyRuntimeRoleAcrossBothTreeBranches() throws {
        let service = Fixtures.FakeInspectorService()
        let button: [String: Any] = ["oid": "button-1", "className": "SwiftUI.AXNode", "kind": "semantic", "runtimeRole": "button", "customDisplayTitle": "01:30", "semanticRoles": ["button", "timer", "text"], "subitems": []]
        let unknown: [String: Any] = ["oid": "unknown-1", "className": "SwiftUI.AvatarNode", "kind": "semantic", "runtimeRole": "vendor.unknown", "customDisplayTitle": "avatar", "semanticRoles": ["avatar", "image"], "subitems": []]
        for branch in ["displayItems", "semanticItems"] {
            service.hierarchy = [branch: [button, unknown]]
            let capture = try Fixtures.makeRunner(service: service).runJSON(arguments: ["capture-hierarchy", "app-1"])
            let nodes = try XCTUnwrap((capture["data"] as? [String: Any])?[branch] as? [[String: Any]])
            XCTAssertEqual(nodes[0]["semanticRoles"] as? [String], ["button"], branch)
            XCTAssertEqual(nodes[1]["semanticRoles"] as? [String], [], branch)
            XCTAssertEqual(nodes[1]["runtimeRole"] as? String, "vendor.unknown", branch)
        }
    }

    func testNativeCommonTextRetainsExistingPlatformSemanticPath() throws {
        let service = Fixtures.FakeInspectorService()
        service.detail = ["attributeGroups": [["identifier": "common.text", "sections": [["identifier": "properties", "attributes": [["identifier": "fontSize", "semanticPath": "common.text.fontSize", "attrTypeName": "number", "value": 28]]]]]]]
        let output = try Fixtures.makeRunner(service: service).runJSON(arguments: ["summarize-node-detail", "app-1", "native-1"])
        let attributes = try XCTUnwrap((output["data"] as? [String: Any])?["attributes"] as? [[String: Any]])
        XCTAssertEqual(attributes.first?["semanticPath"] as? String, "label.fontSize")
    }

    func testSemanticInspectAndStyleUseSavedPageAndCanonicalCommonText() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = ["snapshotId": "runtime-A", "capturedAtUnixTime": 100.0, "semanticCapture": ["source": "ios.accessibility"], "displayItems": [], "semanticItems": [["oid": "semantic-A-1", "detailOid": "semantic-A-1", "className": "AXNode", "runtimeRole": "text", "kind": "semantic", "subitems": []]]]
        service.detail = ["requestedOid": "semantic-A-1", "resolvedOid": "semantic-A-1", "semanticContext": ["snapshotID": "runtime-A", "capturedAtUnixTime": 100.0, "source": "ios.accessibility", "availability": "partial", "issues": [], "wasTruncated": false, "textCandidates": []], "extensions": ["vendor.test": true], "attributeGroups": [["identifier": "common.text", "sections": [["identifier": "properties", "attributes": [["identifier": "fontSize", "semanticPath": "common.text.fontSize", "attrTypeName": "measurement", "value": ["value": 28, "unit": "scaledLogical"]]]]]]]]
        let runner = Fixtures.makeRunner(service: service)
        let capture = try runner.runJSON(arguments: ["capture-hierarchy", "app-1", "--include-semantics"])
        let id = try XCTUnwrap((capture["data"] as? [String: Any])?["snapshotId"] as? String)
        let inspection = try runner.runJSON(arguments: ["inspect-node", "app-1", "--snapshot-id", id, "--oid", "semantic-A-1"])
        let inspected = try XCTUnwrap(inspection["data"] as? [String: Any])
        XCTAssertEqual(inspected["detailSource"] as? String, "runtimeSnapshot")
        XCTAssertEqual(inspected["detailCapturedAtUnixTime"] as? Double, 100)
        XCTAssertEqual((inspected["semanticContext"] as? [String: Any])?["snapshotID"] as? String, "runtime-A")
        let style = try runner.runJSON(arguments: ["check-style", "app-1", "--snapshot-id", id, "--oid", "semantic-A-1", "--expect", "fontSize", "28"])
        let checked = try XCTUnwrap(style["data"] as? [String: Any])
        XCTAssertEqual(checked["passed"] as? Bool, true)
        let checks = try XCTUnwrap(checked["checks"] as? [[String: Any]])
        XCTAssertEqual(checks.first?["semanticPath"] as? String, "common.text.fontSize")
        XCTAssertEqual(service.calls.filter { $0 == .fetchHierarchy("app-1") }.count, 1)
        XCTAssertEqual(service.calls.filter { $0 == .fetchNodeDetail("app-1", "semantic-A-1") }.count, 1)
    }

    func testSemanticScopeReachesAllExistingCaptureBoundaries() throws {
        for command in ["capture-hierarchy", "find-nodes", "summarize-hierarchy", "inspect-screen"] {
            let service = Fixtures.FakeInspectorService()
            service.hierarchy = ["snapshotId": "runtime-A", "capturedAtUnixTime": 100.0, "semanticCapture": ["source": "ios.accessibility"], "displayItems": [], "semanticItems": [["oid": "semantic-A-1", "className": "AXNode", "runtimeRole": "text", "kind": "semantic", "subitems": []]]]
            let output = try Fixtures.makeRunner(service: service).runJSON(arguments: [command, "app-1", "--include-semantics", "--window-id", "window-2", "--json"])
            XCTAssertEqual(service.semanticCaptureOptions?.windowID?.rawValue, "window-2", command)
            let data = try XCTUnwrap(output["data"] as? [String: Any])
            XCTAssertNotEqual(data["snapshotId"] as? String, "runtime-A", command)
            if command != "find-nodes" { XCTAssertEqual(data["runtimeSnapshotId"] as? String, "runtime-A", command) }
        }
    }

    func testSemanticDetailWithoutSavedPageNeverCapturesCurrentUI() throws {
        for arguments in [["node-detail", "app-1", "opaque-A-1", "--include-semantics"], ["capture-hierarchy", "app-1", "--window-id", "window-2"]] {
            let service = Fixtures.FakeInspectorService()
            XCTAssertThrowsError(try Fixtures.makeRunner(service: service).run(arguments: arguments))
            XCTAssertTrue(service.calls.isEmpty)
        }
    }

    func testOpaqueIDRefusalStopsInspectAndStyleBeforeAnyCapture() throws {
        for code in [RuntimeErrorCode.invalidParameters, .nodeNotFound] {
            for arguments in [["inspect-node", "app-1", "--oid", "opaque-Q7"], ["check-style", "app-1", "--oid", "opaque-Q7", "--expect", "fontSize", "28"]] {
                let service = Fixtures.FakeInspectorService()
                service.nativePreflightError = RuntimeError(code: code, message: "Context unavailable", recoverySuggestion: nil)
                XCTAssertThrowsError(try Fixtures.makeRunner(service: service).run(arguments: arguments))
                XCTAssertEqual(service.nativePreflightCount, 1)
                XCTAssertTrue(service.calls.isEmpty)
            }
        }
    }

    func testNativeOpaqueIDSuccessPreservesOriginalHierarchyProjection() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = ["displayItems": [["oid": "opaque-N7", "detailOid": "opaque-N7", "className": "UILabel", "visible": true, "customDisplayTitle": "Native"]]]
        service.detail = ["resolvedOid": "opaque-N7", "attributeGroups": []]
        let output = try Fixtures.makeRunner(service: service).runJSON(arguments: ["inspect-node", "app-1", "--oid", "opaque-N7"])
        let data = try XCTUnwrap(output["data"] as? [String: Any])
        let node = try XCTUnwrap(data["node"] as? [String: Any])
        XCTAssertEqual(node["className"] as? String, "UILabel")
        XCTAssertEqual(node["text"] as? String, "Native")
        XCTAssertEqual(node["visible"] as? Bool, true)
        XCTAssertEqual(service.nativePreflightCount, 1)
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1"), .fetchNodeDetail("app-1", "opaque-N7")])
    }

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
