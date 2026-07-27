//
//  AttributePatchCommandTests.swift
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

final class AttributePatchCommandTests: XCTestCase {
    func testPatchValueParserBuildsMeasurementFromCatalogUnit() throws {
        let attribute = try RuntimePatchableAttribute(
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

        let value = try RuntimeAttributePatchValueParser().parse("20", for: attribute)

        XCTAssertEqual(
            value,
            .measurement(RuntimeMeasurement(value: 20, unit: .scaledLogical))
        )
    }

    func testPatchValueParserRejectsValuesOutsideTheCatalogAllowlist() throws {
        let attribute = try RuntimePatchableAttribute(
            attributePattern: "android.image.scaleType",
            valueType: RuntimePatchValueType(rawValue: "string"),
            targetRoles: ["image"],
            valueConstraints: RuntimePatchValueConstraints(
                minimum: nil,
                maximum: nil,
                minimumExclusive: false,
                maximumExclusive: false,
                acceptedFormats: [],
                allowedValues: [.string("CENTER"), .string("FIT_CENTER")]
            ),
            extensions: RuntimeExtensionMap()
        )

        XCTAssertThrowsError(
            try RuntimeAttributePatchValueParser().parse("INVALID", for: attribute)
        )
    }

    func testAttributePatchCommandsRouteTypedValues() throws {
        let service = Fixtures.FakeInspectorService()
        service.attributePatchResult = ["patchCount": 1]
        service.patchableAttributeCatalog = RuntimePatchableAttributesPayload(
            attributes: [
                try RuntimePatchableAttribute(
                    attributePattern: "label.fontSize",
                    valueType: RuntimePatchValueType(rawValue: "number"),
                    targetRoles: ["label"],
                    valueConstraints: RuntimePatchValueConstraints(
                        minimum: 0,
                        maximum: nil,
                        minimumExclusive: true,
                        maximumExclusive: false,
                        acceptedFormats: [],
                        allowedValues: []
                    ),
                    extensions: RuntimeExtensionMap()
                )
            ]
        )
        let runner = Fixtures.makeRunner(service: service)
        let patchID = UUID()

        _ = try runner.run(arguments: [
            "apply-attribute-patch",
            "app-1",
            "17",
            "--attribute",
            "label.fontSize",
            "--value",
            "8",
            "--json"
        ])
        let catalogOutput = try runner.run(arguments: [
            "list-patchable-attributes",
            "app-1"
        ])
        _ = try runner.run(arguments: [
            "list-attribute-patches",
            "app-1"
        ])
        _ = try runner.run(arguments: [
            "revert-attribute-patch",
            "app-1",
            patchID.uuidString
        ])
        _ = try runner.run(arguments: [
            "clear-attribute-patches",
            "app-1"
        ])

        XCTAssertEqual(service.calls, [
            .fetchPatchableAttributeCatalog("app-1"),
            .applyAttributePatch("app-1", "17", "label.fontSize", .number(8)),
            .fetchPatchableAttributeCatalog("app-1"),
            .fetchAttributePatches("app-1"),
            .revertAttributePatch("app-1", patchID.uuidString),
            .clearAttributePatches("app-1")
        ])
        guard case let .jsonObject(catalogObject) = catalogOutput,
              let data = catalogObject["data"] as? [String: Any],
              let attributes = data["attributes"] as? [[String: Any]],
              let firstAttribute = attributes.first,
              let constraints = firstAttribute["valueConstraints"] as? [String: Any] else {
            return XCTFail("The patchable attribute catalog should contain structured constraints")
        }
        XCTAssertEqual(data["attributeCount"] as? Int, 1)
        XCTAssertEqual(firstAttribute["attributePattern"] as? String, "label.fontSize")
        XCTAssertEqual(firstAttribute["valueType"] as? String, "number")
        XCTAssertEqual(firstAttribute["targetRoles"] as? [String], ["label"])
        XCTAssertEqual(constraints["minimum"] as? Double, 0)
        XCTAssertEqual(constraints["minimumExclusive"] as? Bool, true)
        XCTAssertNil(constraints["maximumExclusive"])
        XCTAssertNil(constraints["acceptedFormats"])
    }

    func testAttributePatchValueParserSupportsColorSizeAndConstraint() throws {
        let parser = RuntimeAttributePatchValueParser()

        XCTAssertEqual(
            try parser.parse("#FF800080", valueType: RuntimePatchValueType(rawValue: "color")),
            .color(RuntimeColor(colorSpace: "srgb", red: 1, green: 128.0 / 255, blue: 0, alpha: 128.0 / 255))
        )
        XCTAssertEqual(
            try parser.parse("3,2", valueType: RuntimePatchValueType(rawValue: "size")),
            .size(RuntimeMeasuredSize(width: 3, height: 2, unit: .logical))
        )
        XCTAssertEqual(
            try parser.parse(
                "24",
                valueType: RuntimePatchValueType(rawValue: "number")
            ),
            .number(24)
        )
    }

    func testPatchCatalogMatcherSupportsParameterizedIdentifiers() throws {
        let attribute = try RuntimePatchableAttribute(
            attributePattern: "layout.constraint.<identifier>.constant",
            valueType: RuntimePatchValueType(rawValue: "number"),
            targetRoles: ["view"],
            valueConstraints: nil,
            extensions: RuntimeExtensionMap()
        )
        let catalog = RuntimePatchableAttributesPayload(attributes: [attribute])
        let matcher = RuntimePatchableAttributeCatalogMatcher()

        XCTAssertEqual(
            matcher.attribute(
                identifiedBy: "layout.constraint.cardWidth.constant",
                in: catalog
            ),
            attribute
        )
        XCTAssertNil(
            matcher.attribute(
                identifiedBy: "layout.constraint..constant",
                in: catalog
            )
        )
    }

    func testAttributePatchValueParserEnforcesRuntimeNumericBounds() throws {
        let attribute = try RuntimePatchableAttribute(
            attributePattern: "label.fontSize",
            valueType: RuntimePatchValueType(rawValue: "number"),
            targetRoles: ["label"],
            valueConstraints: RuntimePatchValueConstraints(
                minimum: 0,
                maximum: nil,
                minimumExclusive: true,
                maximumExclusive: false,
                acceptedFormats: [],
                allowedValues: []
            ),
            extensions: RuntimeExtensionMap()
        )

        XCTAssertThrowsError(
            try RuntimeAttributePatchValueParser().parse("0", for: attribute)
        ) { error in
            XCTAssertEqual(CLIError.code(for: error), "invalid_argument")
        }
    }

    func testAttributePatchRejectsUnsupportedAttributeBeforeRuntimeCall() throws {
        let service = Fixtures.FakeInspectorService()

        XCTAssertThrowsError(try Fixtures.makeRunner(service: service).run(arguments: [
            "apply-attribute-patch",
            "app-1",
            "17",
            "--attribute",
            "view.frame",
            "--value",
            "0"
        ])) { error in
            XCTAssertEqual(CLIError.code(for: error), "invalid_argument")
        }
        XCTAssertEqual(
            service.calls,
            [.fetchPatchableAttributeCatalog("app-1")]
        )
    }
}
