//
//  RuntimeAttributeValueOutputMapper.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/16.
//

import AstrolabeProtocol
import Foundation

package struct RuntimeAttributeValueOutput {
    /// Stable type name used in CLI attribute output.
    package let typeName: String

    /// Attribute value encodable by JSONSerialization.
    package let value: Any
}

package struct RuntimeAttributeValueOutputMapper {
    package init() {}

    package func map(_ value: RuntimeAttributeValue) -> RuntimeAttributeValueOutput {
        switch value {
        case .null:
            return RuntimeAttributeValueOutput(typeName: "null", value: NSNull())
        case let .boolean(value):
            return RuntimeAttributeValueOutput(typeName: "bool", value: value)
        case let .integer(value):
            return RuntimeAttributeValueOutput(typeName: "number", value: NSNumber(value: value))
        case let .number(value):
            return RuntimeAttributeValueOutput(typeName: "number", value: value)
        case let .string(value):
            return RuntimeAttributeValueOutput(typeName: "string", value: value)
        case let .stringList(value):
            return RuntimeAttributeValueOutput(typeName: "stringList", value: value)
        case let .measurement(value):
            return RuntimeAttributeValueOutput(typeName: "measurement", value: measurement(value))
        case let .point(value):
            return RuntimeAttributeValueOutput(typeName: "point", value: point(value))
        case let .size(value):
            return RuntimeAttributeValueOutput(typeName: "size", value: size(value))
        case let .vector(value):
            return RuntimeAttributeValueOutput(typeName: "vector", value: vector(value))
        case let .rect(value):
            return RuntimeAttributeValueOutput(typeName: "rect", value: rect(value))
        case let .insets(value):
            return RuntimeAttributeValueOutput(typeName: "edgeInsets", value: insets(value))
        case let .color(value):
            return RuntimeAttributeValueOutput(typeName: "color", value: color(value))
        case let .textRuns(value):
            return RuntimeAttributeValueOutput(typeName: "attributedTextRuns", value: value.map(textRun))
        case let .layoutRelations(value):
            return RuntimeAttributeValueOutput(typeName: "constraints", value: value.map(layoutRelation))
        case let .array(value):
            return RuntimeAttributeValueOutput(typeName: "array", value: value.map(jsonValue))
        case let .object(value):
            return RuntimeAttributeValueOutput(typeName: "object", value: value.mapValues(jsonValue))
        case let .extensionValue(type, value):
            return RuntimeAttributeValueOutput(typeName: type.rawValue, value: jsonValue(value))
        }
    }

    package func jsonValue(_ value: RuntimeJSONValue) -> Any {
        switch value {
        case .null: return NSNull()
        case let .boolean(value): return value
        case let .integer(value): return NSNumber(value: value)
        case let .number(value): return value
        case let .string(value): return value
        case let .array(value): return value.map(jsonValue)
        case let .object(value): return value.mapValues(jsonValue)
        }
    }

    package func rect(_ value: RuntimeCoordinateRect) -> [String: Any] {
        [
            "x": value.x,
            "y": value.y,
            "width": value.width,
            "height": value.height,
            "coordinateSpace": value.coordinateSpace.rawValue,
            "unit": value.unit.rawValue
        ]
    }

    package func color(_ value: RuntimeColor) -> [Double] {
        [value.red, value.green, value.blue, value.alpha].map { min(1, max(0, $0)) }
    }

    private func measurement(_ value: RuntimeMeasurement) -> [String: Any] {
        ["value": value.value, "unit": value.unit.rawValue]
    }

    private func point(_ value: RuntimeCoordinatePoint) -> [String: Any] {
        [
            "x": value.x,
            "y": value.y,
            "coordinateSpace": value.coordinateSpace.rawValue,
            "unit": value.unit.rawValue
        ]
    }

    private func size(_ value: RuntimeMeasuredSize) -> [String: Any] {
        ["width": value.width, "height": value.height, "unit": value.unit.rawValue]
    }

    private func vector(_ value: RuntimeVector) -> [String: Any] {
        ["dx": value.dx, "dy": value.dy, "unit": value.unit.rawValue]
    }

    private func insets(_ value: RuntimeInsets) -> [String: Any] {
        [
            "top": value.top,
            "left": value.left,
            "bottom": value.bottom,
            "right": value.right,
            "unit": value.unit.rawValue
        ]
    }

    private func textRun(_ value: RuntimeTextRun) -> [String: Any] {
        var result: [String: Any] = [
            "location": value.range.location,
            "length": value.range.length,
            "text": value.text,
            "extensions": value.extensions.values.mapValues(jsonValue)
        ]
        result["fontName"] = value.fontName
        result["fontFamilyName"] = value.fontFamilyName
        result["fontSize"] = value.fontSize.map(measurement)
        result["foregroundColor"] = value.color.map(color)
        return result.compactMapValues { $0 }
    }

    private func layoutRelation(_ value: RuntimeLayoutRelation) -> [String: Any] {
        var result: [String: Any] = [
            "source": anchor(value.source),
            "relation": value.relation.rawValue,
            "multiplier": value.multiplier,
            "offset": measurement(value.offset),
            "extensions": value.extensions.values.mapValues(jsonValue)
        ]
        result["identifier"] = value.identifier
        result["target"] = value.target.map(anchor)
        result["strength"] = value.strength
        result["isActive"] = value.active
        return result.compactMapValues { $0 }
    }

    private func anchor(_ value: RuntimeLayoutAnchor) -> [String: Any] {
        ["nodeID": value.nodeID.rawValue, "attribute": value.anchor]
    }
}
