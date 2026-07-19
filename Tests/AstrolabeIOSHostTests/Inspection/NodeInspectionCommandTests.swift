//
//  NodeInspectionCommandTests.swift
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
@testable import AstrolabeIOSHost
@testable import AstrolabeIOSInspection

private typealias Fixtures = CLICommandTestFixtures

final class NodeInspectionCommandTests: XCTestCase {
    func testNodeDetailRequiresValidOid() {
        XCTAssertThrowsError(try Fixtures.makeRunner(service: Fixtures.FakeInspectorService()).run(arguments: ["node-detail", "app-1"])) { error in
            XCTAssertEqual(String(describing: error), "Missing argument: appId oid")
        }
    }

    func testNodeDetailReturnsJSONObjectOutput() throws {
        let service = Fixtures.FakeInspectorService()
        service.detail = ["text": "Hello"]

        let output = try Fixtures.makeRunner(service: service).run(arguments: ["node-detail", "app-1", "42"])

        guard case .jsonObject(let object) = output else {
            return XCTFail("node-detail should return jsonObject output")
        }
        XCTAssertEqual(object["success"] as? Bool, true)
        XCTAssertEqual((object["data"] as? [String: Any])?["text"] as? String, "Hello")
        XCTAssertEqual(service.calls, [.fetchNodeDetail("app-1", "42")])
    }

    func testSummarizeNodeDetailFlattensAttributes() throws {
        let service = Fixtures.FakeInspectorService()
        service.detail = [
            "appId": "app-1",
            "requestedOid": "42",
            "resolvedOid": "43",
            "attributeGroups": [
                [
                    "identifier": "View",
                    "userCustomTitle": "",
                    "sections": [
                        [
                            "identifier": "Frame",
                            "attributes": [
                                [
                                    "identifier": "x",
                                    "displayTitle": "X",
                                    "attrTypeName": "number",
                                    "value": 16
                                ],
                                [
                                    "identifier": "backgroundColor",
                                    "displayTitle": "Background",
                                    "attrTypeName": "color",
                                    "value": [1, 0, 0, 1]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: ["summarize-node-detail", "app-1", "42"])

        guard case .jsonObject(let object) = output else {
            return XCTFail("summarize-node-detail should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [[String: Any]])
        XCTAssertEqual(data["appId"] as? String, "app-1")
        XCTAssertEqual(data["requestedOid"] as? String, "42")
        XCTAssertEqual(data["resolvedOid"] as? String, "43")
        XCTAssertEqual(data["attributeCount"] as? Int, 2)
        XCTAssertEqual(attributes.first?["path"] as? String, "View.Frame.x")
        XCTAssertEqual(attributes.first?["displayTitle"] as? String, "X")
        XCTAssertEqual(attributes.first?["value"] as? Int, 16)
        XCTAssertEqual(attributes[1]["colorHex"] as? String, "#FF0000")
        XCTAssertEqual(attributes[1]["semanticName"] as? String, "backgroundColor")
        XCTAssertEqual(attributes[1]["semanticPath"] as? String, "view.backgroundColor")
        let colorRGBA = try XCTUnwrap(attributes[1]["colorRGBA"] as? [String: Any])
        XCTAssertEqual(colorRGBA["red"] as? Int, 255)
        XCTAssertEqual(colorRGBA["green"] as? Int, 0)
        XCTAssertEqual(colorRGBA["blue"] as? Int, 0)
        XCTAssertEqual(colorRGBA["alpha"] as? Double, 1)
        XCTAssertEqual(service.calls, [.fetchNodeDetail("app-1", "42")])
    }

    func testSummarizeNodeDetailFiltersAttributes() throws {
        let service = Fixtures.FakeInspectorService()
        service.detail = [
            "attributeGroups": [
                [
                    "identifier": "View",
                    "sections": [
                        [
                            "identifier": "Style",
                            "attributes": [
                                [
                                    "identifier": "backgroundColor",
                                    "displayTitle": "Background",
                                    "attrTypeName": "color",
                                    "value": [1, 0, 0, 1]
                                ],
                                [
                                    "identifier": "alpha",
                                    "displayTitle": "Alpha",
                                    "attrTypeName": "number",
                                    "value": 1
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "summarize-node-detail",
            "app-1",
            "42",
            "--filter",
            "color"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("summarize-node-detail should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [[String: Any]])
        XCTAssertEqual(data["attributeCount"] as? Int, 1)
        XCTAssertEqual(attributes.first?["identifier"] as? String, "backgroundColor")
        XCTAssertEqual(service.calls, [.fetchNodeDetail("app-1", "42")])
    }

    func testSummarizeNodeDetailAddsSemanticAliases() throws {
        let service = Fixtures.FakeInspectorService()
        service.detail = [
            "attributeGroups": [
                [
                    "identifier": "UILabel",
                    "sections": [
                        [
                            "identifier": "Font",
                            "attributes": [
                                [
                                    "identifier": "lb_f_n",
                                    "displayTitle": "",
                                    "attrTypeName": "string",
                                    "value": ".SFUI-Bold"
                                ],
                                [
                                    "identifier": "lb_f_s",
                                    "displayTitle": "",
                                    "attrTypeName": "double",
                                    "value": 12
                                ],
                                [
                                    "identifier": "lb_t_c",
                                    "displayTitle": "",
                                    "attrTypeName": "color",
                                    "value": [0, 0.5, 1, 1]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: ["summarize-node-detail", "app-1", "42"])

        guard case .jsonObject(let object) = output else {
            return XCTFail("summarize-node-detail should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [[String: Any]])
        XCTAssertEqual(attributes[0]["semanticName"] as? String, "fontName")
        XCTAssertEqual(attributes[0]["semanticPath"] as? String, "label.fontName")
        XCTAssertEqual(attributes[1]["semanticName"] as? String, "fontSize")
        XCTAssertEqual(attributes[1]["semanticPath"] as? String, "label.fontSize")
        XCTAssertEqual(attributes[2]["semanticName"] as? String, "textColor")
        XCTAssertEqual(attributes[2]["semanticPath"] as? String, "label.textColor")
        let semanticAttributes = try XCTUnwrap(data["semanticAttributes"] as? [String: [String: Any]])
        XCTAssertEqual((semanticAttributes["fontSize"]?["value"] as? Int), 12)
        XCTAssertEqual((semanticAttributes["fontSize"]?["semanticPath"] as? String), "label.fontSize")
        XCTAssertEqual((semanticAttributes["textColor"]?["colorHex"] as? String), "#0080FF")
        XCTAssertEqual(service.calls, [.fetchNodeDetail("app-1", "42")])
    }

    func testSummarizeNodeDetailAddsExpandedRuntimeSemanticAliases() throws {
        let service = Fixtures.FakeInspectorService()
        service.detail = [
            "attributeGroups": [
                [
                    "identifier": "Runtime",
                    "sections": [
                        [
                            "identifier": "Attributes",
                            "attributes": [
                                Fixtures.makeNodeAttribute(identifier: "al_h_h", value: 251),
                                Fixtures.makeNodeAttribute(identifier: "al_r_v", value: 750),
                                Fixtures.makeNodeAttribute(identifier: "cl_i_s", value: "{80, 24}", attrTypeName: "string"),
                                Fixtures.makeNodeAttribute(identifier: "vl_c_m", value: "scaleAspectFill", attrTypeName: "enum"),
                                Fixtures.makeNodeAttribute(identifier: "vl_t_t", value: 9),
                                Fixtures.makeNodeAttribute(identifier: "iv_n_n", value: "avatar_hannah", attrTypeName: "string"),
                                Fixtures.makeNodeAttribute(identifier: "ct_e_e", value: true, attrTypeName: "bool"),
                                Fixtures.makeNodeAttribute(identifier: "ct_e_s", value: false, attrTypeName: "bool"),
                                Fixtures.makeNodeAttribute(identifier: "ct_h_a", value: "center", attrTypeName: "enum"),
                                Fixtures.makeNodeAttribute(identifier: "ct_v_a", value: "center", attrTypeName: "enum"),
                                Fixtures.makeNodeAttribute(identifier: "ct_o_e", value: "{0,0,0,0}", attrTypeName: "insets"),
                                Fixtures.makeNodeAttribute(identifier: "bt_c_i", value: "{8,12,8,12}", attrTypeName: "insets"),
                                Fixtures.makeNodeAttribute(identifier: "bt_t_i", value: "{0,4,0,0}", attrTypeName: "insets"),
                                Fixtures.makeNodeAttribute(identifier: "bt_i_i", value: "{0,0,0,4}", attrTypeName: "insets")
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: ["summarize-node-detail", "app-1", "42"])

        guard case .jsonObject(let object) = output else {
            return XCTFail("summarize-node-detail should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let semanticAttributes = try XCTUnwrap(data["semanticAttributes"] as? [String: [String: Any]])
        XCTAssertEqual(semanticAttributes["horizontalContentHuggingPriority"]?["semanticPath"] as? String, "autoLayout.horizontalContentHuggingPriority")
        XCTAssertEqual(semanticAttributes["verticalCompressionResistancePriority"]?["semanticPath"] as? String, "autoLayout.verticalCompressionResistancePriority")
        XCTAssertEqual(semanticAttributes["intrinsicContentSize"]?["semanticPath"] as? String, "layout.intrinsicContentSize")
        XCTAssertEqual(semanticAttributes["contentMode"]?["semanticPath"] as? String, "view.contentMode")
        XCTAssertEqual(semanticAttributes["tag"]?["semanticPath"] as? String, "view.tag")
        XCTAssertEqual(semanticAttributes["imageName"]?["semanticPath"] as? String, "imageView.imageName")
        XCTAssertEqual(semanticAttributes["enabled"]?["semanticPath"] as? String, "control.enabled")
        XCTAssertEqual(semanticAttributes["selected"]?["semanticPath"] as? String, "control.selected")
        XCTAssertEqual(semanticAttributes["horizontalAlignment"]?["semanticPath"] as? String, "control.horizontalAlignment")
        XCTAssertEqual(semanticAttributes["verticalAlignment"]?["semanticPath"] as? String, "control.verticalAlignment")
        XCTAssertEqual(semanticAttributes["outsideEdge"]?["semanticPath"] as? String, "control.outsideEdge")
        XCTAssertEqual(semanticAttributes["contentInsets"]?["semanticPath"] as? String, "button.contentInsets")
        XCTAssertEqual(semanticAttributes["titleInsets"]?["semanticPath"] as? String, "button.titleInsets")
        XCTAssertEqual(semanticAttributes["imageInsets"]?["semanticPath"] as? String, "button.imageInsets")
        XCTAssertEqual(semanticAttributes["imageName"]?["valuePreview"] as? String, "avatar_hannah")
        XCTAssertEqual(service.calls, [.fetchNodeDetail("app-1", "42")])
    }

    func testSummarizeNodeDetailFiltersBySemanticAlias() throws {
        let service = Fixtures.FakeInspectorService()
        service.detail = [
            "attributeGroups": [
                [
                    "identifier": "UILabel",
                    "sections": [
                        [
                            "identifier": "Font",
                            "attributes": [
                                [
                                    "identifier": "lb_f_n",
                                    "attrTypeName": "string",
                                    "value": ".SFUI-Bold"
                                ],
                                [
                                    "identifier": "lb_f_s",
                                    "attrTypeName": "double",
                                    "value": 12
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "summarize-node-detail",
            "app-1",
            "42",
            "--filter",
            "fontSize"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("summarize-node-detail should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let attributes = try XCTUnwrap(data["attributes"] as? [[String: Any]])
        XCTAssertEqual(data["attributeCount"] as? Int, 1)
        XCTAssertEqual(attributes.first?["semanticName"] as? String, "fontSize")
        XCTAssertEqual(service.calls, [.fetchNodeDetail("app-1", "42")])
    }

    func testCheckNodeDetailPassesMatchingAttributeValue() throws {
        let service = Fixtures.FakeInspectorService()
        service.detail = [
            "appId": "app-1",
            "requestedOid": "42",
            "resolvedOid": "43",
            "attributeGroups": [
                [
                    "identifier": "View",
                    "sections": [
                        [
                            "identifier": "Style",
                            "attributes": [
                                [
                                    "identifier": "backgroundColor",
                                    "displayTitle": "Background",
                                    "attrTypeName": "color",
                                    "value": [1, 0, 0, 1]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "check-node-detail",
            "app-1",
            "42",
            "--attribute",
            "backgroundColor",
            "--expect-value",
            "1,0,0,1"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("check-node-detail should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["checkedCount"] as? Int, 1)
        XCTAssertEqual((data["failures"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((data["attribute"] as? [String: Any])?["path"] as? String, "View.Style.backgroundColor")
        XCTAssertEqual(service.calls, [.fetchNodeDetail("app-1", "42")])
    }

    func testCheckNodeDetailPassesMatchingColorHexValue() throws {
        let service = Fixtures.FakeInspectorService()
        service.detail = [
            "attributeGroups": [
                [
                    "identifier": "View",
                    "sections": [
                        [
                            "identifier": "Style",
                            "attributes": [
                                [
                                    "identifier": "backgroundColor",
                                    "displayTitle": "Background",
                                    "attrTypeName": "color",
                                    "value": [1, 0, 0, 1]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "check-node-detail",
            "app-1",
            "42",
            "--attribute",
            "backgroundColor",
            "--expect-value",
            "#FF0000"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("check-node-detail should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(service.calls, [.fetchNodeDetail("app-1", "42")])
    }

    func testCheckNodeDetailPassesMatchingSemanticAlias() throws {
        let service = Fixtures.FakeInspectorService()
        service.detail = [
            "attributeGroups": [
                [
                    "identifier": "UILabel",
                    "sections": [
                        [
                            "identifier": "Font",
                            "attributes": [
                                [
                                    "identifier": "adjustsFontSizeToFitWidth",
                                    "attrTypeName": "bool",
                                    "value": false
                                ],
                                [
                                    "identifier": "lb_f_s",
                                    "attrTypeName": "double",
                                    "value": 12
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "check-node-detail",
            "app-1",
            "42",
            "--attribute",
            "fontSize",
            "--expect-value",
            "12"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("check-node-detail should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual((data["attribute"] as? [String: Any])?["semanticName"] as? String, "fontSize")
        XCTAssertEqual(service.calls, [.fetchNodeDetail("app-1", "42")])
    }

    func testCheckNodeDetailReportsValueMismatch() throws {
        let service = Fixtures.FakeInspectorService()
        service.detail = [
            "attributeGroups": [
                [
                    "identifier": "Layer",
                    "sections": [
                        [
                            "identifier": "Corner",
                            "attributes": [
                                [
                                    "identifier": "cornerRadius",
                                    "displayTitle": "Corner Radius",
                                    "attrTypeName": "number",
                                    "value": 8
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "check-node-detail",
            "app-1",
            "42",
            "--attribute",
            "cornerRadius",
            "--expect-value",
            "10",
            "--tolerance",
            "0.5"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("check-node-detail should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let failures = try XCTUnwrap(data["failures"] as? [[String: Any]])
        XCTAssertEqual(data["passed"] as? Bool, false)
        XCTAssertEqual(failures.first?["field"] as? String, "value")
        XCTAssertEqual(failures.first?["expected"] as? String, "10")
        XCTAssertEqual(failures.first?["actual"] as? String, "8")
        XCTAssertEqual(service.calls, [.fetchNodeDetail("app-1", "42")])
    }

    func testSummarizeHierarchyRequiresAppId() {
        XCTAssertThrowsError(try Fixtures.makeRunner(service: Fixtures.FakeInspectorService()).run(arguments: ["summarize-hierarchy"])) { error in
            XCTAssertEqual(String(describing: error), "Missing argument: appId")
        }
    }

    func testSummarizeHierarchyReturnsAIReadableSummary() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "nodeCount": 3,
            "app": [
                "displayName": "Demo",
                "bundleIdentifier": "com.example.demo",
                "deviceName": "iPhone",
                "screen": [
                    "width": 390,
                    "height": 844,
                    "scale": 3
                ]
            ],
            "displayItems": [
                [
                    "oid": "1",
                    "detailOid": "11",
                    "className": "UIWindow",
                    "frame": ["x": 0, "y": 0, "width": 390, "height": 844],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1,
                    "subitems": [
                        [
                            "oid": "2",
                            "detailOid": "22",
                            "className": "UILabel",
                            "classChain": ["UILabel", "UIView"],
                            "memoryAddress": "0x1234",
                            "customDisplayTitle": "Hello",
                            "frame": ["x": 16, "y": 20, "width": 80, "height": 20],
                            "bounds": ["x": 0, "y": 0, "width": 80, "height": 20],
                            "backgroundColor": [1, 0, 0, 1],
                            "hidden": false,
                            "visible": true,
                            "alpha": 1
                        ],
                        [
                            "oid": "3",
                            "detailOid": "33",
                            "className": "UILabel",
                            "customDisplayTitle": "World",
                            "frame": ["x": 16, "y": 60, "width": 120, "height": 44],
                            "hidden": false,
                            "visible": true,
                            "alpha": 1
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: ["summarize-hierarchy", "app-1"])

        guard case .jsonObject(let object) = output else {
            return XCTFail("summarize-hierarchy should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["appId"] as? String, "app-1")
        XCTAssertEqual(data["nodeCount"] as? Int, 3)
        XCTAssertEqual(data["visibleNodeCount"] as? Int, 3)
        XCTAssertEqual((data["textNodes"] as? [[String: Any]])?.compactMap { $0["text"] as? String }, ["Hello", "World"])
        XCTAssertEqual((data["visibleNodes"] as? [[String: Any]])?.count, 3)
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testSummarizeHierarchyAddsStableRuntimeNodeSchemaFields() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "1",
                    "detailOid": "11",
                    "className": "UIWindow",
                    "classChain": ["UIWindow", "UIView", "UIResponder", "NSObject"],
                    "memoryAddress": "0x1",
                    "frame": ["x": 0, "y": 0, "width": 390, "height": 844],
                    "bounds": ["x": 0, "y": 0, "width": 390, "height": 844],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1,
                    "subitems": [
                        [
                            "oid": "2",
                            "detailOid": "22",
                            "className": "UILabel",
                            "classChain": ["UILabel", "UIView", "UIResponder", "NSObject"],
                            "customDisplayTitle": "Title",
                            "frame": ["x": 16, "y": 20, "width": 80, "height": 20],
                            "bounds": ["x": 0, "y": 0, "width": 80, "height": 20],
                            "backgroundColor": [1, 0.5, 0, 1],
                            "hidden": false,
                            "visible": true,
                            "alpha": 1
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: ["summarize-hierarchy", "app-1"])

        guard case .jsonObject(let object) = output else {
            return XCTFail("summarize-hierarchy should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let nodes = try XCTUnwrap(data["visibleNodes"] as? [[String: Any]])
        let label = try XCTUnwrap(nodes.first { ($0["className"] as? String) == "UILabel" })
        XCTAssertEqual(label["hierarchyPath"] as? String, "UIWindow[0]/UILabel[0]")
        XCTAssertEqual(label["depth"] as? Int, 1)
        XCTAssertEqual(label["siblingIndex"] as? Int, 0)
        XCTAssertEqual(label["bounds"] as? [String: Int], ["x": 0, "y": 0, "width": 80, "height": 20])
        XCTAssertEqual(label["classChain"] as? [String], ["UILabel", "UIView", "UIResponder", "NSObject"])
        XCTAssertEqual(label["backgroundColorHex"] as? String, "#FF8000")
        let color = try XCTUnwrap(label["backgroundColorRGBA"] as? [String: Any])
        XCTAssertEqual(color["red"] as? Int, 255)
        XCTAssertEqual(color["green"] as? Int, 128)
        XCTAssertEqual(color["blue"] as? Int, 0)
        XCTAssertEqual(color["alpha"] as? Double, 1)
    }

    func testHierarchySummaryReportsCompactedNodeCounts() throws {
        let hierarchy: [String: Any] = [
            "appId": "app-1",
            "displayItems": (1...3).map { index in
                [
                    "oid": String(index),
                    "detailOid": String(index),
                    "className": "UILabel",
                    "customDisplayTitle": "Label \(index)",
                    "frame": ["x": 0, "y": index * 20, "width": 80, "height": 20],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ] as [String: Any]
            }
        ]
        let summary = HierarchySummaryBuilder(
            visibleNodeLimit: 2,
            textNodeLimit: 1
        ).buildSummary(from: hierarchy)

        XCTAssertEqual(summary["visibleNodeCount"] as? Int, 3)
        XCTAssertEqual(summary["returnedVisibleNodeCount"] as? Int, 2)
        XCTAssertEqual(summary["omittedVisibleNodeCount"] as? Int, 1)
        XCTAssertEqual((summary["visibleNodes"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(summary["textNodeCount"] as? Int, 3)
        XCTAssertEqual(summary["returnedTextNodeCount"] as? Int, 1)
        XCTAssertEqual(summary["omittedTextNodeCount"] as? Int, 2)
        XCTAssertEqual((summary["textNodes"] as? [[String: Any]])?.count, 1)
    }

    func testHierarchySummaryUsesRuntimeOnscreenVisibility() throws {
        let hierarchy: [String: Any] = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "1",
                    "detailOid": "1",
                    "className": "UILabel",
                    "customDisplayTitle": "Offscreen",
                    "frame": ["x": 0, "y": 900, "width": 80, "height": 20],
                    "hidden": false,
                    "inHiddenHierarchy": false,
                    "alpha": 1,
                    "effectiveAlpha": 1,
                    "visible": false
                ] as [String: Any]
            ]
        ]

        let summary = HierarchySummaryBuilder().buildSummary(from: hierarchy)
        let query = HierarchyNodeQuery(
            oid: nil,
            className: "UILabel",
            text: nil,
            visibleOnly: false,
            limit: 1
        )
        let result = try HierarchyNodeFinder().findNodes(in: hierarchy, query: query)
        let node = try XCTUnwrap((result["nodes"] as? [[String: Any]])?.first)

        XCTAssertEqual(summary["visibleNodeCount"] as? Int, 0)
        XCTAssertEqual(node["visible"] as? Bool, false)
        XCTAssertNil(node["hierarchyVisible"])
        XCTAssertNil(node["onscreen"])
    }

    func testInspectScreenReturnsAIReadableInspection() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "nodeCount": 5,
            "displayItems": [
                [
                    "oid": "1",
                    "detailOid": "11",
                    "className": "UIWindow",
                    "frame": ["x": 0, "y": 0, "width": 390, "height": 844],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1,
                    "subitems": [
                        [
                            "oid": "2",
                            "detailOid": "22",
                            "className": "UILabel",
                            "customDisplayTitle": "Title",
                            "frame": ["x": 16, "y": 20, "width": 80, "height": 20],
                            "hidden": false,
                            "visible": true,
                            "alpha": 1
                        ],
                        [
                            "oid": "3",
                            "detailOid": "33",
                            "className": "UILabel",
                            "customDisplayTitle": "Subtitle",
                            "frame": ["x": 16, "y": 60, "width": 120, "height": 20],
                            "hidden": false,
                            "visible": true,
                            "alpha": 1
                        ],
                        [
                            "oid": "4",
                            "detailOid": "44",
                            "className": "UIButton",
                            "customDisplayTitle": "Continue",
                            "frame": ["x": 16, "y": 100, "width": 120, "height": 44],
                            "hidden": false,
                            "visible": true,
                            "alpha": 1
                        ],
                        [
                            "oid": "5",
                            "detailOid": "55",
                            "className": "UIImageView",
                            "frame": ["x": 16, "y": 160, "width": 80, "height": 80],
                            "hidden": true,
                            "visible": false,
                            "alpha": 1
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "inspect-screen",
            "app-1",
            "--target-limit",
            "2"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("inspect-screen should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let classHistogram = try XCTUnwrap(data["classHistogram"] as? [[String: Any]])
        let checkTargets = try XCTUnwrap(data["checkTargets"] as? [[String: Any]])
        XCTAssertEqual(data["appId"] as? String, "app-1")
        XCTAssertEqual(data["nodeCount"] as? Int, 5)
        XCTAssertEqual(data["visibleNodeCount"] as? Int, 4)
        XCTAssertEqual(data["targetLimit"] as? Int, 2)
        XCTAssertEqual(classHistogram.first?["className"] as? String, "UILabel")
        XCTAssertEqual(classHistogram.first?["visibleCount"] as? Int, 2)
        XCTAssertEqual(checkTargets.count, 2)
        XCTAssertEqual(checkTargets.first?["text"] as? String, "Title")
        XCTAssertEqual(checkTargets.first?["reason"] as? String, "text")
        XCTAssertEqual(Set(checkTargets.first?.keys.map { $0 } ?? []), [
            "className",
            "detailOid",
            "frame",
            "oid",
            "reason",
            "semanticRoles",
            "text"
        ])
        XCTAssertNil(data["visibleNodes"])
        XCTAssertNil(data["textNodes"])
        XCTAssertEqual(data["checkTargetCount"] as? Int, 3)
        XCTAssertEqual(data["returnedCheckTargetCount"] as? Int, 2)
        XCTAssertEqual(data["omittedCheckTargetCount"] as? Int, 1)
        XCTAssertEqual((data["recommendedNextTools"] as? [String])?.prefix(2).map { $0 }, ["inspect_node", "summarize_node_detail"])
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testInspectScreenBoundsClassHistogram() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": (1...4).map { index in
                [
                    "oid": String(index),
                    "detailOid": String(index),
                    "className": "Class\(index)",
                    "frame": ["x": 0, "y": index * 20, "width": 80, "height": 20],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ] as [String: Any]
            }
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "inspect-screen",
            "app-1",
            "--class-limit",
            "2"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("inspect-screen should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual((data["classHistogram"] as? [[String: Any]])?.count, 2)
        XCTAssertEqual(data["classCount"] as? Int, 4)
        XCTAssertEqual(data["returnedClassCount"] as? Int, 2)
        XCTAssertEqual(data["omittedClassCount"] as? Int, 2)
        XCTAssertEqual(data["classLimit"] as? Int, 2)
    }

    func testInspectScreenUsesCompactDefaultLimits() throws {
        let command = try ScreenInspectionCommandParser().parse(arguments: [])

        XCTAssertEqual(command.targetLimit, 12)
        XCTAssertEqual(command.classLimit, 12)
    }

    func testInspectScreenDiversifiesTargetsAndRemovesNestedDuplicateText() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "1",
                    "detailOid": "1",
                    "className": "UIWindow",
                    "frame": ["x": 0, "y": 0, "width": 390, "height": 844],
                    "visible": true,
                    "subitems": [
                        [
                            "oid": "2",
                            "detailOid": "2",
                            "className": "UILabel",
                            "customDisplayTitle": "Title",
                            "frame": ["x": 16, "y": 20, "width": 80, "height": 20],
                            "visible": true
                        ],
                        [
                            "oid": "3",
                            "detailOid": "3",
                            "className": "UILabel",
                            "customDisplayTitle": "Subtitle",
                            "frame": ["x": 16, "y": 50, "width": 120, "height": 20],
                            "visible": true
                        ],
                        [
                            "oid": "4",
                            "detailOid": "4",
                            "className": "UIImageView",
                            "frame": ["x": 16, "y": 300, "width": 80, "height": 80],
                            "visible": true
                        ],
                        [
                            "oid": "5",
                            "detailOid": "5",
                            "className": "UIButton",
                            "customDisplayTitle": "Continue",
                            "frame": ["x": 16, "y": 700, "width": 160, "height": 44],
                            "visible": true,
                            "subitems": [
                                [
                                    "oid": "6",
                                    "detailOid": "6",
                                    "className": "UILabel",
                                    "customDisplayTitle": "Continue",
                                    "frame": ["x": 60, "y": 712, "width": 72, "height": 20],
                                    "visible": true
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "inspect-screen",
            "app-1",
            "--target-limit",
            "3"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("inspect-screen should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let targets = try XCTUnwrap(data["checkTargets"] as? [[String: Any]])
        XCTAssertEqual(targets.compactMap { $0["reason"] as? String }, ["text", "control", "image"])
        XCTAssertEqual(targets.compactMap { $0["oid"] as? String }, ["2", "5", "4"])
        XCTAssertEqual(targets.filter { $0["text"] as? String == "Continue" }.count, 1)
    }

    func testInspectScreenDistributesSameCategoryTargetsAcrossVerticalRegions() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "1",
                    "detailOid": "1",
                    "className": "UIWindow",
                    "frame": ["x": 0, "y": 0, "width": 390, "height": 900],
                    "visible": true,
                    "subitems": [
                        Fixtures.makeVisibleTextNode(oid: 2, text: "Top A", y: 20),
                        Fixtures.makeVisibleTextNode(oid: 3, text: "Top B", y: 60),
                        Fixtures.makeVisibleTextNode(oid: 4, text: "Middle", y: 400),
                        Fixtures.makeVisibleTextNode(oid: 5, text: "Bottom", y: 760)
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "inspect-screen",
            "app-1",
            "--target-limit",
            "3"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("inspect-screen should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let targets = try XCTUnwrap(data["checkTargets"] as? [[String: Any]])
        XCTAssertEqual(targets.compactMap { $0["text"] as? String }, ["Top A", "Middle", "Bottom"])
    }

    func testInspectScreenUsesSemanticWindowFrameForNonUIKitHierarchy() throws {
        let hierarchy: [String: Any] = [
            "appId": "android:app-1",
            "displayItems": [[
                "oid": "1",
                "detailOid": "1",
                "className": "android.view.DecorView",
                "classChain": ["android.view.Window", "android.view.DecorView"],
                "semanticRoles": ["window"],
                "frame": ["x": 0, "y": 0, "width": 412, "height": 900],
                "visible": true,
                "subitems": [
                    Fixtures.makeVisibleTextNode(oid: 2, text: "Top A", y: 20),
                    Fixtures.makeVisibleTextNode(oid: 3, text: "Top B", y: 60),
                    Fixtures.makeVisibleTextNode(oid: 4, text: "Middle", y: 400),
                    Fixtures.makeVisibleTextNode(oid: 5, text: "Bottom", y: 760)
                ]
            ]]
        ]

        let inspection = ScreenInspectionBuilder(
            qualityPolicy: PermissiveScreenInspectionTargetQualityPolicy()
        ).buildInspection(
            from: hierarchy,
            targetLimit: 3
        )
        let targets = try XCTUnwrap(inspection["checkTargets"] as? [[String: Any]])

        XCTAssertEqual(targets.compactMap { $0["text"] as? String }, ["Top A", "Middle", "Bottom"])
    }

    func testInspectScreenUsesBuilderRegisteredForProviderPlatform() throws {
        let service = Fixtures.FakeInspectorService()
        service.descriptor = RuntimeUIProviderDescriptor(
            identifier: "android-provider",
            platform: .android,
            capabilities: [.hierarchy]
        )
        service.hierarchy = [
            "appId": "android:app-1",
            "displayItems": [[
                "oid": "1",
                "detailOid": "1",
                "className": "android.view.Window",
                "semanticRoles": ["window"],
                "frame": ["x": 0, "y": 0, "width": 412, "height": 900],
                "visible": true,
                "subitems": [Fixtures.makeVisibleNode(
                    oid: 2,
                    className: "UITransitionView",
                    y: 100
                )]
            ]]
        ]
        let runner = CLICommandRunner(
            service: service,
            screenshotProvider: Fixtures.FakeScreenshotProvider(),
            paginationSnapshotStore: InMemoryHierarchyPaginationSnapshotStore(),
            pageSnapshotStore: InMemoryPageSnapshotStore(),
            screenshotCaptureOptionsBuilders: [:],
            screenInspectionBuilders: [
                .android: ScreenInspectionBuilder(
                    qualityPolicy: PermissiveScreenInspectionTargetQualityPolicy()
                )
            ],
            semanticRoleClassifiers: [:],
            namedMaskResolvers: [:]
        )

        let output = try runner.run(arguments: ["inspect-screen", "android:app-1"])

        guard case .jsonObject(let object) = output else {
            return XCTFail("inspect-screen should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let targets = try XCTUnwrap(data["checkTargets"] as? [[String: Any]])
        XCTAssertEqual(targets.compactMap { $0["oid"] as? String }, ["2"])
    }

    func testInspectScreenOmitsInfrastructureContainersAndBackingLayers() throws {
        let hierarchy: [String: Any] = [
            "appId": "app-1",
            "displayItems": [[
                "oid": "1",
                "detailOid": "1",
                "className": "UIWindow",
                "semanticRoles": ["window"],
                "frame": ["x": 0, "y": 0, "width": 390, "height": 844],
                "visible": true,
                "subitems": [
                    Fixtures.makeVisibleNode(oid: 2, className: "UITransitionView", y: 0),
                    Fixtures.makeVisibleNode(oid: 3, className: "UIDropShadowView", y: 0),
                    Fixtures.makeVisibleNode(oid: 4, className: "UILayoutContainerView", y: 0),
                    Fixtures.makeVisibleNode(oid: 5, className: "UINavigationTransitionView", y: 0),
                    Fixtures.makeVisibleNode(oid: 6, className: "UIViewControllerWrapperView", y: 0),
                    Fixtures.makeVisibleNode(oid: 7, className: "UITableViewCellContentView", y: 100),
                    Fixtures.makeVisibleNode(oid: 8, className: "CALayer", y: 200),
                    Fixtures.makeVisibleNode(oid: 9, className: "_UILabelLayer", y: 300),
                    Fixtures.makeVisibleNode(oid: 10, className: "UIWindowLayer", y: 350),
                    Fixtures.makeVisibleNode(
                        oid: 11,
                        className: "DoraemonEntryWindow",
                        y: 375,
                        semanticRoles: ["window"]
                    ),
                    Fixtures.makeVisibleNode(oid: 12, className: "CAGradientLayer", y: 400),
                    Fixtures.makeVisibleNode(oid: 13, className: "FeedContentCell", y: 500)
                ]
            ]]
        ]

        let inspection = ScreenInspectionBuilder(
            qualityPolicy: UIKitScreenInspectionTargetQualityPolicy()
        ).buildInspection(
            from: hierarchy,
            targetLimit: 20
        )
        let targets = try XCTUnwrap(inspection["checkTargets"] as? [[String: Any]])

        XCTAssertEqual(Set(targets.compactMap { $0["className"] as? String }), [
            "CAGradientLayer",
            "FeedContentCell"
        ])
    }

    func testInspectScreenPrioritizesSemanticAndApplicationContainersWithinRegion() throws {
        let hierarchy: [String: Any] = [
            "appId": "app-1",
            "displayItems": [[
                "oid": "1",
                "detailOid": "1",
                "className": "UIWindow",
                "semanticRoles": ["window"],
                "frame": ["x": 0, "y": 0, "width": 390, "height": 844],
                "visible": true,
                "subitems": [
                    Fixtures.makeVisibleNode(oid: 2, className: "UIView", y: 20),
                    Fixtures.makeVisibleNode(oid: 3, className: "BusinessCardView", y: 40),
                    Fixtures.makeVisibleNode(
                        oid: 4,
                        className: "UICollectionView",
                        y: 60,
                        semanticRoles: ["list"]
                    )
                ]
            ]]
        ]

        let inspection = ScreenInspectionBuilder(
            qualityPolicy: UIKitScreenInspectionTargetQualityPolicy()
        ).buildInspection(
            from: hierarchy,
            targetLimit: 3
        )
        let targets = try XCTUnwrap(inspection["checkTargets"] as? [[String: Any]])

        XCTAssertEqual(targets.compactMap { $0["oid"] as? String }, ["4", "3", "2"])
    }

    func testInspectScreenOmitsFullScreenGenericControlOnly() throws {
        let hierarchy: [String: Any] = [
            "appId": "app-1",
            "displayItems": [[
                "oid": "1",
                "detailOid": "1",
                "className": "UIWindow",
                "semanticRoles": ["window"],
                "frame": ["x": 0, "y": 0, "width": 390, "height": 844],
                "visible": true,
                "subitems": [
                    Fixtures.makeVisibleNode(
                        oid: 2,
                        className: "UIControl",
                        y: 0,
                        width: 390,
                        height: 844,
                        semanticRoles: ["control"]
                    ),
                    Fixtures.makeVisibleNode(
                        oid: 3,
                        className: "UIControl",
                        y: 100,
                        semanticRoles: ["control"]
                    ),
                    Fixtures.makeVisibleNode(
                        oid: 4,
                        className: "CanvasControl",
                        y: 0,
                        width: 390,
                        height: 844
                    )
                ]
            ]]
        ]

        let inspection = ScreenInspectionBuilder(
            qualityPolicy: UIKitScreenInspectionTargetQualityPolicy()
        ).buildInspection(
            from: hierarchy,
            targetLimit: 10
        )
        let targets = try XCTUnwrap(inspection["checkTargets"] as? [[String: Any]])

        XCTAssertEqual(Set(targets.compactMap { $0["oid"] as? String }), ["3", "4"])
    }

    func testInspectScreenOmitsTinyTargetsAndNestedControlImages() throws {
        let hierarchy: [String: Any] = [
            "appId": "app-1",
            "displayItems": [[
                "oid": "1",
                "detailOid": "1",
                "className": "UIWindow",
                "semanticRoles": ["window"],
                "frame": ["x": 0, "y": 0, "width": 390, "height": 844],
                "visible": true,
                "subitems": [
                    [
                        "oid": "2",
                        "detailOid": "2",
                        "className": "UIImageView",
                        "semanticRoles": ["image"],
                        "frame": ["x": 20, "y": 100, "width": 1, "height": 1],
                        "visible": true
                    ],
                    [
                        "oid": "3",
                        "detailOid": "3",
                        "className": "ScaledImageButton",
                        "semanticRoles": ["button", "control"],
                        "frame": ["x": 100, "y": 700, "width": 26, "height": 26],
                        "visible": true,
                        "subitems": [[
                            "oid": "4",
                            "detailOid": "4",
                            "className": "UIImageView",
                            "semanticRoles": ["image"],
                            "frame": ["x": 100, "y": 700, "width": 26, "height": 26],
                            "visible": true
                        ]]
                    ]
                ]
            ]]
        ]

        let inspection = ScreenInspectionBuilder(
            qualityPolicy: UIKitScreenInspectionTargetQualityPolicy()
        ).buildInspection(
            from: hierarchy,
            targetLimit: 10
        )
        let targets = try XCTUnwrap(inspection["checkTargets"] as? [[String: Any]])

        XCTAssertEqual(targets.compactMap { $0["oid"] as? String }, ["3"])
        XCTAssertEqual(targets.first?["reason"] as? String, "control")
    }

    func testFindNodesRequiresAppId() {
        XCTAssertThrowsError(try Fixtures.makeRunner(service: Fixtures.FakeInspectorService()).run(arguments: ["find-nodes"])) { error in
            XCTAssertEqual(String(describing: error), "Missing argument: appId")
        }
    }

    func testSnapshotIdKeepsHierarchyChecksOnTheCapturedPage() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = Fixtures.hierarchyWithLabelOids([1, 2, 3])
        let snapshotDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            Fixtures.removeFileIfNeeded(snapshotDirectory)
        }
        let runner = Fixtures.makeRunner(
            service: service,
            pageSnapshotDirectory: snapshotDirectory
        )
        let inspection = try runner.run(arguments: ["inspect-screen", "app-1"])
        guard case .jsonObject(let inspectionObject) = inspection else {
            return XCTFail("inspect-screen should return jsonObject output")
        }
        let inspectionData = try XCTUnwrap(inspectionObject["data"] as? [String: Any])
        let snapshotID = try XCTUnwrap(inspectionData["snapshotId"] as? String)
        service.hierarchy = Fixtures.hierarchyWithLabelOids([9])

        let output = try runner.run(arguments: [
            "check-node",
            "app-1",
            "--snapshot-id",
            snapshotID,
            "--oid",
            "2",
            "--expect-class",
            "UILabel"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("check-node should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["snapshotId"] as? String, snapshotID)
        XCTAssertEqual(data["hierarchySource"] as? String, "snapshot")
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testSnapshotInspectScreenUsesCapturedPlatformAfterRuntimeDisconnects() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = Fixtures.hierarchyWithLabelOids([1, 2, 3])
        let runner = Fixtures.makeRunner(service: service)
        let initialOutput = try runner.run(arguments: ["inspect-screen", "app-1"])
        guard case .jsonObject(let initialObject) = initialOutput else {
            return XCTFail("inspect-screen should return jsonObject output")
        }
        let initialData = try XCTUnwrap(initialObject["data"] as? [String: Any])
        let snapshotID = try XCTUnwrap(initialData["snapshotId"] as? String)
        service.platformResolutionError = CLIError.targetProviderNotFound("app-1")

        let snapshotOutput = try runner.run(arguments: [
            "inspect-screen",
            "app-1",
            "--snapshot-id",
            snapshotID
        ])

        guard case .jsonObject(let snapshotObject) = snapshotOutput else {
            return XCTFail("inspect-screen should return jsonObject output")
        }
        let snapshotData = try XCTUnwrap(snapshotObject["data"] as? [String: Any])
        XCTAssertEqual(snapshotData["hierarchySource"] as? String, "snapshot")
    }

    func testOmittingSnapshotIdRecapturesTheCurrentHierarchy() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = Fixtures.hierarchyWithLabelOids([1])
        let snapshotDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            Fixtures.removeFileIfNeeded(snapshotDirectory)
        }
        let runner = Fixtures.makeRunner(
            service: service,
            pageSnapshotDirectory: snapshotDirectory
        )
        let firstOutput = try runner.run(arguments: ["inspect-screen", "app-1"])
        guard case .jsonObject(let firstObject) = firstOutput else {
            return XCTFail("inspect-screen should return jsonObject output")
        }
        let firstData = try XCTUnwrap(firstObject["data"] as? [String: Any])
        let firstSnapshotID = try XCTUnwrap(firstData["snapshotId"] as? String)
        service.hierarchy = Fixtures.hierarchyWithLabelOids([2])

        let secondOutput = try runner.run(arguments: ["inspect-screen", "app-1"])

        guard case .jsonObject(let secondObject) = secondOutput else {
            return XCTFail("inspect-screen should return jsonObject output")
        }
        let secondData = try XCTUnwrap(secondObject["data"] as? [String: Any])
        let secondSnapshotID = try XCTUnwrap(secondData["snapshotId"] as? String)
        XCTAssertNotEqual(firstSnapshotID, secondSnapshotID)
        XCTAssertEqual(secondData["hierarchySource"] as? String, "liveRuntime")
        XCTAssertEqual(service.calls, [
            .fetchHierarchy("app-1"),
            .fetchHierarchy("app-1")
        ])
    }

    func testSnapshotNodeDetailIsLoadedFromRuntimeOnceAndThenCached() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = Fixtures.hierarchyWithLabelOids([1, 2])
        service.detail = [
            "requestedOid": "2",
            "attributeGroups": [["identifier": "first"]]
        ]
        let snapshotDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            Fixtures.removeFileIfNeeded(snapshotDirectory)
        }
        let runner = Fixtures.makeRunner(
            service: service,
            pageSnapshotDirectory: snapshotDirectory
        )
        let firstOutput = try runner.run(arguments: [
            "inspect-node",
            "app-1",
            "--oid",
            "2"
        ])
        guard case .jsonObject(let firstObject) = firstOutput else {
            return XCTFail("inspect-node should return jsonObject output")
        }
        let firstData = try XCTUnwrap(firstObject["data"] as? [String: Any])
        let snapshotID = try XCTUnwrap(firstData["snapshotId"] as? String)
        XCTAssertEqual(firstData["detailSource"] as? String, "liveRuntime")
        service.detail = [
            "requestedOid": "2",
            "attributeGroups": [["identifier": "second"]]
        ]

        let secondOutput = try runner.run(arguments: [
            "inspect-node",
            "app-1",
            "--snapshot-id",
            snapshotID,
            "--oid",
            "2"
        ])

        guard case .jsonObject(let secondObject) = secondOutput else {
            return XCTFail("inspect-node should return jsonObject output")
        }
        let secondData = try XCTUnwrap(secondObject["data"] as? [String: Any])
        let secondDetail = try XCTUnwrap(secondData["detail"] as? [String: Any])
        let groups = try XCTUnwrap(secondDetail["attributeGroups"] as? [[String: Any]])
        XCTAssertEqual(groups.first?["identifier"] as? String, "first")
        XCTAssertEqual(secondData["detailSource"] as? String, "snapshotCache")
        XCTAssertEqual(service.calls, [
            .fetchHierarchy("app-1"),
            .fetchNodeDetail("app-1", "2")
        ])
    }

    func testSnapshotNodeDetailRejectsOidOutsideCapturedHierarchy() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = Fixtures.hierarchyWithLabelOids([1, 2])
        let snapshotDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            Fixtures.removeFileIfNeeded(snapshotDirectory)
        }
        let runner = Fixtures.makeRunner(
            service: service,
            pageSnapshotDirectory: snapshotDirectory
        )
        let inspection = try runner.run(arguments: ["inspect-screen", "app-1"])
        guard case .jsonObject(let inspectionObject) = inspection else {
            return XCTFail("inspect-screen should return jsonObject output")
        }
        let inspectionData = try XCTUnwrap(inspectionObject["data"] as? [String: Any])
        let snapshotID = try XCTUnwrap(inspectionData["snapshotId"] as? String)

        XCTAssertThrowsError(try runner.run(arguments: [
            "node-detail",
            "app-1",
            "99",
            "--snapshot-id",
            snapshotID
        ])) { error in
            XCTAssertEqual(CLIError.code(for: error), "snapshot_node_not_found")
        }
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testSnapshotNodeOidMapsToDetailOidAndUsesTheSameCacheEntry() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [[
                "oid": "2",
                "detailOid": "22",
                "className": "UILabel",
                "frame": ["x": 0, "y": 0, "width": 80, "height": 20],
                "visible": true
            ]]
        ]
        service.detail = ["requestedOid": "22", "attributeGroups": []]
        let snapshotDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            Fixtures.removeFileIfNeeded(snapshotDirectory)
        }
        let runner = Fixtures.makeRunner(
            service: service,
            pageSnapshotDirectory: snapshotDirectory
        )
        let inspection = try runner.run(arguments: ["inspect-screen", "app-1"])
        guard case .jsonObject(let inspectionObject) = inspection else {
            return XCTFail("inspect-screen should return jsonObject output")
        }
        let inspectionData = try XCTUnwrap(inspectionObject["data"] as? [String: Any])
        let snapshotID = try XCTUnwrap(inspectionData["snapshotId"] as? String)

        _ = try runner.run(arguments: [
            "node-detail",
            "app-1",
            "2",
            "--snapshot-id",
            snapshotID
        ])
        let cachedOutput = try runner.run(arguments: [
            "node-detail",
            "app-1",
            "22",
            "--snapshot-id",
            snapshotID
        ])

        guard case .jsonObject(let cachedObject) = cachedOutput else {
            return XCTFail("node-detail should return jsonObject output")
        }
        let cachedData = try XCTUnwrap(cachedObject["data"] as? [String: Any])
        XCTAssertEqual(cachedData["detailSource"] as? String, "snapshotCache")
        XCTAssertEqual(cachedData["hierarchySource"] as? String, "snapshot")
        XCTAssertNotNil(cachedData["capturedAtUnixTime"])
        XCTAssertNotNil(cachedData["detailCapturedAtUnixTime"])
        XCTAssertEqual(service.calls, [
            .fetchHierarchy("app-1"),
            .fetchNodeDetail("app-1", "22")
        ])
    }

    func testFindNodesFiltersClassTextVisibilityAndLimit() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "1",
                    "detailOid": "11",
                    "className": "UIWindow",
                    "frame": ["x": 0, "y": 0, "width": 390, "height": 844],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1,
                    "subitems": [
                        [
                            "oid": "2",
                            "detailOid": "22",
                            "className": "UILabel",
                            "customDisplayTitle": "Hello",
                            "frame": ["x": 16, "y": 20, "width": 80, "height": 20],
                            "hidden": false,
                            "visible": true,
                            "alpha": 1
                        ],
                        [
                            "oid": "3",
                            "detailOid": "33",
                            "className": "UILabel",
                            "customDisplayTitle": "Hello Hidden",
                            "frame": ["x": 16, "y": 60, "width": 120, "height": 44],
                            "hidden": true,
                            "visible": false,
                            "alpha": 1
                        ],
                        [
                            "oid": "4",
                            "detailOid": "44",
                            "className": "UIButton",
                            "customDisplayTitle": "Hello Button",
                            "frame": ["x": 16, "y": 120, "width": 120, "height": 44],
                            "hidden": false,
                            "visible": true,
                            "alpha": 1
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "find-nodes",
            "app-1",
            "--class",
            "UILabel",
            "--text",
            "Hello",
            "--visible-only",
            "--limit",
            "1"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("find-nodes should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let nodes = try XCTUnwrap(data["nodes"] as? [[String: Any]])
        XCTAssertEqual(data["appId"] as? String, "app-1")
        XCTAssertEqual(data["totalCount"] as? Int, 1)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes.first?["oid"] as? String, "2")
        XCTAssertEqual(nodes.first?["text"] as? String, "Hello")
        XCTAssertEqual(Set(nodes.first?.keys.map { $0 } ?? []), [
            "className",
            "detailOid",
            "frame",
            "hierarchyPath",
            "oid",
            "semanticRoles",
            "text",
            "visible"
        ])
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testFindNodesUsesCursorToReturnTheNextPage() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": (1...5).map { index in
                [
                    "oid": String(index),
                    "detailOid": String(index),
                    "className": "UILabel",
                    "frame": ["x": 0, "y": index * 20, "width": 80, "height": 20],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ] as [String: Any]
            }
        ]

        let runner = Fixtures.makeRunner(service: service)
        let firstOutput = try runner.run(arguments: [
            "find-nodes",
            "app-1",
            "--class",
            "UILabel",
            "--limit",
            "2"
        ])

        guard case .jsonObject(let firstObject) = firstOutput else {
            return XCTFail("find-nodes should return jsonObject output")
        }
        let firstData = try XCTUnwrap(firstObject["data"] as? [String: Any])
        let cursor = try XCTUnwrap(firstData["nextCursor"] as? String)
        let secondOutput = try runner.run(arguments: [
            "find-nodes",
            "app-1",
            "--class",
            "UILabel",
            "--limit",
            "2",
            "--cursor",
            cursor
        ])

        guard case .jsonObject(let secondObject) = secondOutput else {
            return XCTFail("find-nodes should return jsonObject output")
        }
        let data = try XCTUnwrap(secondObject["data"] as? [String: Any])
        let nodes = try XCTUnwrap(data["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.compactMap { $0["oid"] as? String }, ["3", "4"])
        XCTAssertEqual(data["totalCount"] as? Int, 5)
        XCTAssertEqual(data["returnedCount"] as? Int, 2)
        XCTAssertEqual(data["hasMore"] as? Bool, true)
        XCTAssertNotNil(data["nextCursor"] as? String)
        XCTAssertNotNil(data["paginationSnapshotId"] as? String)
        XCTAssertNil(data["nextOffset"])
    }

    func testFindNodesUsesFrozenSnapshotWhenRuntimeHierarchyChanges() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = Fixtures.hierarchyWithLabelOids([1, 2, 3])
        let snapshotDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            Fixtures.removeFileIfNeeded(snapshotDirectory)
        }
        let firstRunner = Fixtures.makeRunner(
            service: service,
            paginationSnapshotDirectory: snapshotDirectory
        )
        let firstOutput = try firstRunner.run(arguments: [
            "find-nodes",
            "app-1",
            "--class",
            "UILabel",
            "--limit",
            "2"
        ])

        guard case .jsonObject(let firstObject) = firstOutput else {
            return XCTFail("find-nodes should return jsonObject output")
        }
        let firstData = try XCTUnwrap(firstObject["data"] as? [String: Any])
        let cursor = try XCTUnwrap(firstData["nextCursor"] as? String)
        service.hierarchy = Fixtures.hierarchyWithLabelOids([0, 1, 2, 3])
        let secondRunner = Fixtures.makeRunner(
            service: service,
            paginationSnapshotDirectory: snapshotDirectory
        )
        let secondOutput = try secondRunner.run(arguments: [
            "find-nodes",
            "app-1",
            "--class",
            "UILabel",
            "--limit",
            "2",
            "--cursor",
            cursor
        ])

        guard case .jsonObject(let secondObject) = secondOutput else {
            return XCTFail("find-nodes should return jsonObject output")
        }
        let secondData = try XCTUnwrap(secondObject["data"] as? [String: Any])
        let nodes = try XCTUnwrap(secondData["nodes"] as? [[String: Any]])
        XCTAssertEqual(nodes.compactMap { $0["oid"] as? String }, ["3"])
        XCTAssertEqual(secondData["totalCount"] as? Int, 3)
        XCTAssertEqual(secondData["hasMore"] as? Bool, false)
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testFindNodesRejectsCursorForDifferentQuery() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = Fixtures.hierarchyWithLabelOids([1, 2, 3])
        let runner = Fixtures.makeRunner(service: service)
        let firstOutput = try runner.run(arguments: [
            "find-nodes",
            "app-1",
            "--class",
            "UILabel",
            "--limit",
            "2"
        ])

        guard case .jsonObject(let firstObject) = firstOutput else {
            return XCTFail("find-nodes should return jsonObject output")
        }
        let firstData = try XCTUnwrap(firstObject["data"] as? [String: Any])
        let cursor = try XCTUnwrap(firstData["nextCursor"] as? String)

        XCTAssertThrowsError(try runner.run(arguments: [
            "find-nodes",
            "app-1",
            "--class",
            "UI",
            "--limit",
            "2",
            "--cursor",
            cursor
        ])) { error in
            XCTAssertEqual(String(describing: error), "Pagination cursor does not match the current app or query")
        }
    }

    func testFindNodesRejectsCursorForDifferentApp() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = Fixtures.hierarchyWithLabelOids([1, 2, 3])
        let runner = Fixtures.makeRunner(service: service)
        let firstOutput = try runner.run(arguments: [
            "find-nodes",
            "app-1",
            "--class",
            "UILabel",
            "--limit",
            "2"
        ])

        guard case .jsonObject(let firstObject) = firstOutput else {
            return XCTFail("find-nodes should return jsonObject output")
        }
        let firstData = try XCTUnwrap(firstObject["data"] as? [String: Any])
        let cursor = try XCTUnwrap(firstData["nextCursor"] as? String)

        XCTAssertThrowsError(try runner.run(arguments: [
            "find-nodes",
            "app-2",
            "--class",
            "UILabel",
            "--limit",
            "2",
            "--cursor",
            cursor
        ])) { error in
            XCTAssertEqual(CLIError.code(for: error), "pagination_cursor_mismatch")
        }
    }

    func testFindNodesRejectsCursorForDifferentPageSnapshot() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = Fixtures.hierarchyWithLabelOids([1, 2, 3])
        let paginationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let pageSnapshotDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            Fixtures.removeFileIfNeeded(paginationDirectory)
            Fixtures.removeFileIfNeeded(pageSnapshotDirectory)
        }
        let runner = Fixtures.makeRunner(
            service: service,
            paginationSnapshotDirectory: paginationDirectory,
            pageSnapshotDirectory: pageSnapshotDirectory
        )
        let firstOutput = try runner.run(arguments: [
            "find-nodes",
            "app-1",
            "--class",
            "UILabel",
            "--limit",
            "2"
        ])
        guard case .jsonObject(let firstObject) = firstOutput else {
            return XCTFail("find-nodes should return jsonObject output")
        }
        let firstData = try XCTUnwrap(firstObject["data"] as? [String: Any])
        let cursor = try XCTUnwrap(firstData["nextCursor"] as? String)

        let secondInspection = try runner.run(arguments: ["inspect-screen", "app-1"])
        guard case .jsonObject(let secondObject) = secondInspection else {
            return XCTFail("inspect-screen should return jsonObject output")
        }
        let secondData = try XCTUnwrap(secondObject["data"] as? [String: Any])
        let secondSnapshotID = try XCTUnwrap(secondData["snapshotId"] as? String)

        XCTAssertThrowsError(try runner.run(arguments: [
            "find-nodes",
            "app-1",
            "--snapshot-id",
            secondSnapshotID,
            "--class",
            "UILabel",
            "--limit",
            "2",
            "--cursor",
            cursor
        ])) { error in
            XCTAssertEqual(CLIError.code(for: error), "pagination_cursor_mismatch")
        }
    }

    func testFindNodesRejectsMalformedCursor() {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = Fixtures.hierarchyWithLabelOids([1, 2, 3])

        XCTAssertThrowsError(try Fixtures.makeRunner(service: service).run(arguments: [
            "find-nodes",
            "app-1",
            "--class",
            "UILabel",
            "--limit",
            "2",
            "--cursor",
            "not-a-cursor"
        ])) { error in
            XCTAssertEqual(String(describing: error), "Invalid pagination cursor")
        }
    }

    func testFindNodesCanTargetExactOid() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UILabel",
                    "customDisplayTitle": "Title",
                    "frame": ["x": 16, "y": 20, "width": 80, "height": 20],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ],
                [
                    "oid": "3",
                    "detailOid": "33",
                    "className": "UILabel",
                    "customDisplayTitle": "Title",
                    "frame": ["x": 24, "y": 60, "width": 120, "height": 20],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "find-nodes",
            "app-1",
            "--oid",
            "3"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("find-nodes should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let nodes = try XCTUnwrap(data["nodes"] as? [[String: Any]])
        XCTAssertEqual(data["totalCount"] as? Int, 1)
        XCTAssertEqual(nodes.first?["oid"] as? String, "3")
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testFindNodesCanTargetSemanticRole() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UserAvatarImageView",
                    "classChain": ["UserAvatarImageView", "UIImageView", "UIView"],
                    "customInfo": ["title": "Profile Avatar"],
                    "frame": ["x": 16, "y": 20, "width": 44, "height": 44],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ],
                [
                    "oid": "3",
                    "detailOid": "33",
                    "className": "UIImageView",
                    "classChain": ["UIImageView", "UIView"],
                    "frame": ["x": 80, "y": 20, "width": 44, "height": 44],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "find-nodes",
            "app-1",
            "--role",
            "avatar"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("find-nodes should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let nodes = try XCTUnwrap(data["nodes"] as? [[String: Any]])
        XCTAssertEqual(data["totalCount"] as? Int, 1)
        XCTAssertEqual(nodes.first?["oid"] as? String, "2")
        XCTAssertEqual(nodes.first?["semanticRoles"] as? [String], ["avatar", "image"])
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testFindNodesRejectsUnknownSemanticRole() {
        XCTAssertThrowsError(try Fixtures.makeRunner(service: Fixtures.FakeInspectorService()).run(arguments: [
            "find-nodes",
            "app-1",
            "--role",
            "dynamic"
        ])) { error in
            XCTAssertEqual(CLIError.code(for: error), "invalid_argument")
            XCTAssertTrue(String(describing: error).contains("Unknown semantic role: dynamic"))
        }
    }

    func testFindNodesDoesNotApplyUIKitRolesToAndroidHierarchy() throws {
        let service = Fixtures.FakeInspectorService()
        service.descriptor = RuntimeUIProviderDescriptor(
            identifier: "android-provider",
            platform: .android,
            capabilities: [.hierarchy]
        )
        service.hierarchy = [
            "appId": "android:app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "className": "UIButton",
                    "classChain": ["UIButton", "UIView"],
                    "frame": ["x": 0, "y": 0, "width": 100, "height": 44]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "find-nodes",
            "android:app-1",
            "--role",
            "button"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("find-nodes should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["totalCount"] as? Int, 0)
    }

    func testFindNodesDoesNotClassifyButtonLabelAsButton() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "className": "UIButton",
                    "classChain": ["UIButton", "UIControl", "UIView"],
                    "frame": ["x": 0, "y": 0, "width": 100, "height": 44]
                ],
                [
                    "oid": "3",
                    "className": "UIButtonLabel",
                    "classChain": ["UIButtonLabel", "UILabel", "UIView"],
                    "customDisplayTitle": "Save",
                    "frame": ["x": 20, "y": 10, "width": 40, "height": 20]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "find-nodes",
            "app-1",
            "--role",
            "button"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("find-nodes should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let nodes = try XCTUnwrap(data["nodes"] as? [[String: Any]])
        XCTAssertEqual(data["totalCount"] as? Int, 1)
        XCTAssertEqual(nodes.first?["oid"] as? String, "2")
        XCTAssertEqual(nodes.first?["semanticRoles"] as? [String], ["button", "control"])
    }

    func testInspectNodeRequiresAppId() {
        XCTAssertThrowsError(try Fixtures.makeRunner(service: Fixtures.FakeInspectorService()).run(arguments: ["inspect-node"])) { error in
            XCTAssertEqual(String(describing: error), "Missing argument: appId")
        }
    }

    func testInspectNodeUsesOidWhenDetailOidIsAbsent() throws {
        let service = Fixtures.FakeInspectorService()
        service.detail = ["requestedOid": "2", "attributeGroups": []]
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "className": "UILabel",
                    "customDisplayTitle": "Hello",
                    "frame": ["x": 16, "y": 20, "width": 80, "height": 20],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "inspect-node",
            "app-1",
            "--class",
            "UILabel"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("inspect-node should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["detailOid"] as? String, nil)
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1"), .fetchNodeDetail("app-1", "2")])
    }

    func testInspectNodeFetchesFirstMatchingNodeDetail() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "1",
                    "detailOid": "11",
                    "className": "UIWindow",
                    "frame": ["x": 0, "y": 0, "width": 390, "height": 844],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1,
                    "subitems": [
                        [
                            "oid": "2",
                            "detailOid": "22",
                            "className": "UILabel",
                            "customDisplayTitle": "Hello",
                            "frame": ["x": 16, "y": 20, "width": 80, "height": 20],
                            "hidden": false,
                            "visible": true,
                            "alpha": 1
                        ]
                    ]
                ]
            ]
        ]
        service.detail = [
            "attributeGroupCount": 2,
            "attributeGroups": [
                ["identifier": "Font"]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "inspect-node",
            "app-1",
            "--class",
            "UILabel",
            "--text",
            "Hello",
            "--visible-only"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("inspect-node should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["appId"] as? String, "app-1")
        XCTAssertEqual((data["node"] as? [String: Any])?["detailOid"] as? String, "22")
        XCTAssertEqual((data["detail"] as? [String: Any])?["attributeGroupCount"] as? Int, 2)
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1"), .fetchNodeDetail("app-1", "22")])
    }

    func testCheckNodeComparesTextClassVisibilityAndFrame() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UILabel",
                    "customDisplayTitle": "Hello",
                    "frame": ["x": 16, "y": 20, "width": 80, "height": 20],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "check-node",
            "app-1",
            "--class",
            "UILabel",
            "--text",
            "Hello",
            "--visible-only",
            "--expect-class",
            "UILabel",
            "--expect-text",
            "Hello",
            "--expect-visible",
            "true",
            "--expect-frame",
            "16",
            "20",
            "80",
            "20",
            "--tolerance",
            "0.5"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("check-node should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["checkedCount"] as? Int, 7)
        XCTAssertEqual((data["failures"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual((data["node"] as? [String: Any])?["oid"] as? String, "2")
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testCheckNodeReportsExpectationFailures() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UILabel",
                    "customDisplayTitle": "Hello",
                    "frame": ["x": 16, "y": 20, "width": 80, "height": 20],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "check-node",
            "app-1",
            "--class",
            "UILabel",
            "--expect-text",
            "World",
            "--expect-frame",
            "10",
            "20",
            "80",
            "20"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("check-node should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let failures = try XCTUnwrap(data["failures"] as? [[String: Any]])
        XCTAssertEqual(data["passed"] as? Bool, false)
        XCTAssertEqual(failures.compactMap { $0["field"] as? String }, ["text", "frame.x"])
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testCheckNodeCanTargetExactOid() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UILabel",
                    "customDisplayTitle": "Title",
                    "frame": ["x": 16, "y": 20, "width": 80, "height": 20],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ],
                [
                    "oid": "3",
                    "detailOid": "33",
                    "className": "UILabel",
                    "customDisplayTitle": "Title",
                    "frame": ["x": 24, "y": 60, "width": 120, "height": 20],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "check-node",
            "app-1",
            "--oid",
            "3",
            "--expect-frame",
            "24",
            "60",
            "120",
            "20"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("check-node should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual((data["node"] as? [String: Any])?["oid"] as? String, "3")
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

    func testCheckStyleComparesMultipleSemanticAttributes() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UILabel",
                    "customDisplayTitle": "Title",
                    "frame": ["x": 16, "y": 20, "width": 80, "height": 20],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]
        service.detail = [
            "attributeGroups": [
                [
                    "identifier": "UILabel",
                    "sections": [
                        [
                            "identifier": "Style",
                            "attributes": [
                                [
                                    "identifier": "lb_f_s",
                                    "attrTypeName": "double",
                                    "value": 12
                                ],
                                [
                                    "identifier": "lb_t_c",
                                    "attrTypeName": "color",
                                    "value": [0, 0.5, 1, 1]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "check-style",
            "app-1",
            "--oid",
            "2",
            "--expect",
            "fontSize",
            "12",
            "--expect",
            "textColor",
            "#0080FF",
            "--tolerance",
            "0.5"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("check-style should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let checks = try XCTUnwrap(data["checks"] as? [[String: Any]])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["checkedCount"] as? Int, 2)
        XCTAssertEqual((data["failures"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(checks.compactMap { $0["attribute"] as? String }, ["fontSize", "textColor"])
        XCTAssertEqual((data["node"] as? [String: Any])?["detailOid"] as? String, "22")
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1"), .fetchNodeDetail("app-1", "22")])
    }

    func testCheckLayoutComparesVerticalSpacingBetweenNodes() throws {
        let service = Fixtures.FakeInspectorService()
        service.hierarchy = [
            "appId": "app-1",
            "displayItems": [
                [
                    "oid": "2",
                    "detailOid": "22",
                    "className": "UILabel",
                    "customDisplayTitle": "Title",
                    "frame": ["x": 16, "y": 20, "width": 80, "height": 20],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ],
                [
                    "oid": "3",
                    "detailOid": "33",
                    "className": "UIButton",
                    "customDisplayTitle": "Save",
                    "frame": ["x": 16, "y": 60, "width": 120, "height": 44],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ]
            ]
        ]

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "check-layout",
            "app-1",
            "--from-oid",
            "2",
            "--to-oid",
            "3",
            "--relation",
            "vertical-spacing",
            "--expect",
            "20",
            "--tolerance",
            "0.5"
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("check-layout should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        XCTAssertEqual(data["passed"] as? Bool, true)
        XCTAssertEqual(data["checkedCount"] as? Int, 1)
        XCTAssertEqual(data["actual"] as? Double, 20)
        XCTAssertEqual((data["fromNode"] as? [String: Any])?["oid"] as? String, "2")
        XCTAssertEqual((data["toNode"] as? [String: Any])?["oid"] as? String, "3")
        XCTAssertEqual(service.calls, [.fetchHierarchy("app-1")])
    }

}

private struct PermissiveScreenInspectionTargetQualityPolicy: ScreenInspectionTargetQualityEvaluating {
    func isEligible(_ context: ScreenInspectionTargetEligibilityContext) -> Bool {
        !context.semanticRoles.contains(.window)
    }

    func priority(
        className: String,
        semanticRoles: Set<NodeSemanticRole>,
        reason: ScreenInspectionTargetReason
    ) -> Int {
        0
    }
}
