//
//  AndroidInspectionCommandIntegrationTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeAndroidInspection
import AstrolabeCLI
import AstrolabeProtocol
import XCTest

final class AndroidInspectionCommandIntegrationTests: XCTestCase {
    func testAndroidModuleSupportsThePlatformNeutralInspectionCommands() throws {
        let provider = FakeAndroidInspectionProvider()
        let module = try HostPlatformModuleBuilder(provider: provider)
            .hierarchyCapture(provider)
            .nodeDetail(provider)
            .patchCatalog(provider)
            .attributePatching(provider)
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

        let patchCatalog = try data(from: runner.runJSON(arguments: [
            "list-patchable-attributes",
            provider.appID
        ]))
        XCTAssertEqual(patchCatalog["attributeCount"] as? Int, 1)

        _ = try data(from: runner.runJSON(arguments: [
            "apply-attribute-patch",
            provider.appID,
            "2",
            "--attribute",
            "android.text.fontSize",
            "--value",
            "20"
        ]))
        XCTAssertEqual(
            provider.lastAppliedValue,
            .measurement(RuntimeMeasurement(value: 20, unit: .scaledLogical))
        )

        _ = try data(from: runner.runJSON(arguments: [
            "list-attribute-patches",
            provider.appID
        ]))
        _ = try data(from: runner.runJSON(arguments: [
            "revert-attribute-patch",
            provider.appID,
            "patch-android-1"
        ]))
        _ = try data(from: runner.runJSON(arguments: [
            "clear-attribute-patches",
            provider.appID
        ]))
        XCTAssertEqual(provider.revertedPatchID, "patch-android-1")
        XCTAssertTrue(provider.didClearPatches)
    }

    private func data(from object: [String: Any]) throws -> [String: Any] {
        return try XCTUnwrap(object["data"] as? [String: Any])
    }
}

private final class FakeAndroidInspectionProvider:
    RuntimeUIProviderTargeting,
    RuntimeUIHierarchyCapturing,
    RuntimeUINodeDetailProviding,
    RuntimeUIPatchCatalogProviding,
    RuntimeUIAttributePatching {
    /// Stable app identifier handled by this fake Provider.
    let appID = "android:demo"

    /// Android capability declaration consumed by Host module validation.
    let descriptor = RuntimeUIProviderDescriptor(
        identifier: "fake-android-provider",
        platform: .android,
        capabilities: [
            .hierarchy,
            .nodeDetail,
            .attributePatchDiscovery,
            .attributePatching
        ]
    )

    /// Most recent typed value received from the platform-neutral patch command.
    var lastAppliedValue: RuntimeAttributeValue?

    /// Most recent patch identifier requested for reversion.
    var revertedPatchID: String?

    /// Whether the clear lifecycle command reached this Provider.
    var didClearPatches = false

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

    func fetchPatchableAttributeCatalog(
        appId: String
    ) throws -> RuntimePatchableAttributesPayload {
        RuntimePatchableAttributesPayload(
            attributes: [
                try RuntimePatchableAttribute(
                    attributePattern: "android.text.fontSize",
                    valueType: RuntimePatchValueType(rawValue: "measurement"),
                    targetRoles: ["text"],
                    valueConstraints: RuntimePatchValueConstraints(
                        minimum: 0,
                        maximum: nil,
                        minimumExclusive: true,
                        maximumExclusive: false,
                        acceptedFormats: ["scaledLogical"],
                        allowedValues: []
                    ),
                    extensions: RuntimeExtensionMap()
                )
            ]
        )
    }

    func applyAttributePatch(
        appId: String,
        oid: String,
        attributeIdentifier: String,
        value: RuntimeAttributeValue
    ) throws -> [String: Any] {
        lastAppliedValue = value
        return ["patchID": "patch-android-1"]
    }

    func fetchAttributePatches(appId: String) throws -> [String: Any] {
        ["patches": []]
    }

    func revertAttributePatch(
        appId: String,
        patchID: String
    ) throws -> [String: Any] {
        revertedPatchID = patchID
        return ["revertedPatchID": patchID]
    }

    func clearAttributePatches(appId: String) throws -> [String: Any] {
        didClearPatches = true
        return ["remainingPatchCount": 0]
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
