//
//  AttributePatchCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/13.
//

import AstrolabeProtocol
import Foundation

struct ApplyAttributePatchCommand {
    /// Session node to modify.
    let oid: String

    /// Stable semantic path of the presentation attribute.
    let attributeIdentifier: String

    /// Unparsed value supplied by the CLI caller.
    let rawValue: String
}

struct AttributePatchCommandParser {
    func parseApply(arguments: [String]) throws -> ApplyAttributePatchCommand {
        guard let oid = arguments.first, !oid.isEmpty else {
            throw CLIError.missingArgument("valid oid")
        }
        var attributeIdentifier: String?
        var rawValue: String?
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--attribute":
                attributeIdentifier = try value(after: &index, in: arguments)
            case "--value":
                rawValue = try value(after: &index, in: arguments)
            case "--json":
                break
            default:
                throw CLIError.invalidArgument("Unknown attribute patch argument: \(arguments[index])")
            }
            index += 1
        }
        guard let attributeIdentifier, !attributeIdentifier.isEmpty else {
            throw CLIError.missingArgument("--attribute")
        }
        guard let rawValue else {
            throw CLIError.missingArgument("--value")
        }
        return ApplyAttributePatchCommand(
            oid: oid,
            attributeIdentifier: attributeIdentifier,
            rawValue: rawValue
        )
    }

    func parsePatchID(_ value: String?) throws -> String {
        guard let value, !value.isEmpty else {
            throw CLIError.missingArgument("valid patchId")
        }
        return value
    }

    private func value(after index: inout Int, in arguments: [String]) throws -> String {
        index += 1
        guard index < arguments.count else {
            throw CLIError.missingArgument(arguments[index - 1])
        }
        return arguments[index]
    }
}

struct RuntimeAttributePatchValueParser {
    func parse(
        _ rawValue: String,
        valueType: RuntimePatchValueType
    ) throws -> RuntimeAttributeValue {
        switch valueType.rawValue {
        case "string":
            return .string(rawValue)
        case "color":
            return .color(try color(rawValue))
        case "size":
            return .size(try size(rawValue))
        case "number":
            return .number(try decimal(rawValue))
        default:
            throw CLIError.invalidArgument(
                "The Host does not support patch value type: \(valueType.rawValue)"
            )
        }
    }

    func parse(
        _ rawValue: String,
        for attribute: RuntimePatchableAttribute
    ) throws -> RuntimeAttributeValue {
        let value = try parse(rawValue, valueType: attribute.valueType)
        try validate(value, for: attribute)
        return value
    }

    private func decimal(_ value: String) throws -> Double {
        guard let result = Double(value), result.isFinite else {
            throw CLIError.invalidArgument("The patch attribute requires a finite number")
        }
        return result
    }

    private func color(_ value: String) throws -> RuntimeColor {
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard hex.count == 6 || hex.count == 8,
              let encoded = UInt64(hex, radix: 16) else {
            throw CLIError.invalidArgument("Color must use #RRGGBB or #RRGGBBAA format")
        }
        let includesAlpha = hex.count == 8
        let redShift: UInt64 = includesAlpha ? 24 : 16
        let greenShift: UInt64 = includesAlpha ? 16 : 8
        let blueShift: UInt64 = includesAlpha ? 8 : 0
        let alpha = includesAlpha ? Double(encoded & 0xFF) / 255 : 1
        return RuntimeColor(
            colorSpace: "srgb",
            red: Double((encoded >> redShift) & 0xFF) / 255,
            green: Double((encoded >> greenShift) & 0xFF) / 255,
            blue: Double((encoded >> blueShift) & 0xFF) / 255,
            alpha: alpha
        )
    }

    private func size(_ value: String) throws -> RuntimeMeasuredSize {
        let components = value.split(separator: ",", omittingEmptySubsequences: false)
        guard components.count == 2,
              let width = Double(components[0]), width.isFinite,
              let height = Double(components[1]), height.isFinite,
              width >= 0, height >= 0 else {
            throw CLIError.invalidArgument("Size must use width,height format")
        }
        return RuntimeMeasuredSize(width: width, height: height, unit: .logical)
    }

    private func validate(
        _ value: RuntimeAttributeValue,
        for attribute: RuntimePatchableAttribute
    ) throws {
        guard case let .number(number) = value,
              let constraints = attribute.valueConstraints else {
            return
        }
        if let minimum = constraints.minimum {
            let valid = constraints.minimumExclusive
                ? number > minimum
                : number >= minimum
            guard valid else {
                throw CLIError.invalidArgument(
                    "\(attribute.attributePattern) is below the allowed minimum"
                )
            }
        }
        if let maximum = constraints.maximum {
            let valid = constraints.maximumExclusive
                ? number < maximum
                : number <= maximum
            guard valid else {
                throw CLIError.invalidArgument(
                    "\(attribute.attributePattern) is above the allowed maximum"
                )
            }
        }
    }
}
