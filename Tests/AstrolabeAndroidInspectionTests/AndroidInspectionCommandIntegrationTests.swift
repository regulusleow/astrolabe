//
//  AndroidInspectionCommandIntegrationTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeAndroidInspection
import AstrolabeCLI
import XCTest

final class AndroidInspectionCommandIntegrationTests: XCTestCase {
    func testAndroidModuleSupportsThePlatformNeutralInspectionCommands() throws {
        let provider = FakeAndroidInspectionProvider()
        let module = try HostPlatformModuleBuilder(provider: provider)
            .hierarchyCapture(provider)
            .nodeDetail(provider)
            .screenInspectionBuilder(
                ScreenInspectionBuilder(
                    qualityPolicy: AndroidScreenInspectionTargetQualityPolicy()
                )
            )
            .semanticRoleClassifier(AndroidNodeSemanticRoleClassifier())
            .nodeDetailSemanticMapper(AndroidNodeDetailAttributeSemanticMapper())
            .nodeDetailIssueInterpreter(AndroidNodeDetailSemanticIssueInterpreter())
            .build()
        let runner = try CLICommandRunner(platformModules: [module])

        let inspection = try data(
            from: runner.runJSON(arguments: ["inspect-screen", provider.appID])
        )
        let targets = try XCTUnwrap(inspection["checkTargets"] as? [[String: Any]])
        XCTAssertTrue(targets.contains { target in target["oid"] as? String == "2" })
        XCTAssertTrue(targets.contains { target in target["oid"] as? String == "3" })
        XCTAssertTrue(targets.contains { target in target["oid"] as? String == "4" })

        let found = try data(from: runner.runJSON(arguments: [
            "find-nodes",
            provider.appID,
            "--role",
            "list"
        ]))
        let nodes = try XCTUnwrap(found["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.map { node in node["oid"] as? String }, ["5"])

        let nodeInspection = try data(from: runner.runJSON(arguments: [
            "inspect-node",
            provider.appID,
            "--oid",
            "2"
        ]))
        let detail = try XCTUnwrap(nodeInspection["detail"] as? [String: Any])
        XCTAssertEqual(detail["requestedOid"] as? String, "2")

        let nodeCheck = try data(from: runner.runJSON(arguments: [
            "check-node",
            provider.appID,
            "--oid",
            "3",
            "--expect-frame",
            "16",
            "80",
            "140",
            "48"
        ]))
        XCTAssertEqual(nodeCheck["passed"] as? Bool, true)

        let styleCheck = try data(from: runner.runJSON(arguments: [
            "check-style",
            provider.appID,
            "--oid",
            "2",
            "--expect",
            "fontSize",
            "16",
            "--expect",
            "textColor",
            "#102030"
        ]))
        XCTAssertEqual(styleCheck["passed"] as? Bool, true)
    }

    private func data(from object: [String: Any]) throws -> [String: Any] {
        return try XCTUnwrap(object["data"] as? [String: Any])
    }
}

private final class FakeAndroidInspectionProvider:
    RuntimeUIProviderTargeting,
    RuntimeUIHierarchyCapturing,
    RuntimeUINodeDetailProviding {
    /// Stable app identifier handled by this fake Provider.
    let appID = "android:demo"

    /// Android capability declaration consumed by Host module validation.
    let descriptor = RuntimeUIProviderDescriptor(
        identifier: "fake-android-provider",
        platform: .android,
        capabilities: [.hierarchy, .nodeDetail]
    )

    func canHandle(appId: String) -> Bool {
        appId == appID
    }

    func fetchHierarchy(appId: String) throws -> [String: Any] {
        [
            "appId": appID,
            "displayItems": [[
                "oid": "1",
                "detailOid": "1",
                "role": "window",
                "className": "com.android.internal.policy.DecorView",
                "classChain": ["com.android.internal.policy.DecorView", "android.view.ViewGroup"],
                "frame": frame(x: 0, y: 0, width: 412, height: 915),
                "hidden": false,
                "visible": true,
                "alpha": 1,
                "subitems": [
                    node(
                        oid: "2",
                        role: "label",
                        className: "android.widget.TextView",
                        text: "Android title",
                        frame: frame(x: 16, y: 24, width: 180, height: 32)
                    ),
                    node(
                        oid: "3",
                        role: "button",
                        className: "android.widget.Button",
                        text: "Continue",
                        frame: frame(x: 16, y: 80, width: 140, height: 48)
                    ),
                    node(
                        oid: "4",
                        role: "image",
                        className: "android.widget.ImageView",
                        text: nil,
                        frame: frame(x: 16, y: 144, width: 54, height: 54)
                    ),
                    node(
                        oid: "5",
                        role: "container",
                        className: "androidx.recyclerview.widget.RecyclerView",
                        text: nil,
                        frame: frame(x: 0, y: 220, width: 412, height: 400),
                        subitems: [
                            node(
                                oid: "6",
                                role: "label",
                                className: "android.widget.TextView",
                                text: "List item",
                                frame: frame(x: 16, y: 236, width: 120, height: 32)
                            )
                        ]
                    )
                ]
            ]]
        ]
    }

    func fetchNodeDetail(appId: String, oid: String) throws -> [String: Any] {
        [
            "requestedOid": oid,
            "resolvedOid": oid,
            "attributeGroups": [[
                "identifier": "AndroidRuntime",
                "sections": [[
                    "identifier": "android.text",
                    "attributes": [
                        attribute(
                            identifier: "android.text.fontSize",
                            type: "measurement",
                            value: 16
                        ),
                        attribute(
                            identifier: "android.text.color",
                            type: "color",
                            value: [16.0 / 255.0, 32.0 / 255.0, 48.0 / 255.0, 1.0]
                        )
                    ]
                ]]
            ]]
        ]
    }

    private func node(
        oid: String,
        role: String,
        className: String,
        text: String?,
        frame: [String: Any],
        subitems: [[String: Any]] = []
    ) -> [String: Any] {
        var result: [String: Any] = [
            "oid": oid,
            "detailOid": oid,
            "role": role,
            "className": className,
            "classChain": [className, "android.view.View"],
            "frame": frame,
            "hidden": false,
            "visible": true,
            "alpha": 1,
            "subitems": subitems
        ]
        if let text {
            result["customDisplayTitle"] = text
        }
        return result
    }

    private func frame(
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> [String: Any] {
        ["x": x, "y": y, "width": width, "height": height]
    }

    private func attribute(
        identifier: String,
        type: String,
        value: Any
    ) -> [String: Any] {
        [
            "identifier": identifier,
            "attrTypeName": type,
            "value": value
        ]
    }
}
