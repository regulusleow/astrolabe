//
//  NodeDetailValueFormatter.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct NodeDetailValueFormatter {
    func previewString(from value: Any) -> String {
        if value is NSNull {
            return "null"
        }
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let array = value as? [Any] {
            return array.map { previewString(from: $0) }.joined(separator: ",")
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.keys.sorted().map { key in
                "\(key):\(previewString(from: dictionary[key] ?? NSNull()))"
            }.joined(separator: ",")
        }
        return String(describing: value)
    }

    func colorHex(from value: Any, attrTypeName: String) -> String? {
        guard let components = normalizedColorComponents(from: value, attrTypeName: attrTypeName) else {
            return nil
        }

        if components.alpha < 1 {
            return String(
                format: "#%02X%02X%02X%02X",
                components.red,
                components.green,
                components.blue,
                alphaByte(from: components.alpha)
            )
        }
        return String(format: "#%02X%02X%02X", components.red, components.green, components.blue)
    }

    func colorRGBA(from value: Any, attrTypeName: String) -> [String: Any]? {
        guard let components = normalizedColorComponents(from: value, attrTypeName: attrTypeName) else {
            return nil
        }
        return [
            "red": components.red,
            "green": components.green,
            "blue": components.blue,
            "alpha": components.alpha
        ]
    }

    private func normalizedColorComponents(from value: Any, attrTypeName: String) -> ColorComponents? {
        guard attrTypeName == "color",
              let rawComponents = value as? [Any],
              rawComponents.count == 3 || rawComponents.count == 4 else {
            return nil
        }

        let numbers = rawComponents.compactMap { numericValue(from: $0) }
        guard numbers.count == rawComponents.count else {
            return nil
        }

        return ColorComponents(
            red: byteValue(from: numbers[0]),
            green: byteValue(from: numbers[1]),
            blue: byteValue(from: numbers[2]),
            alpha: alphaValue(from: numbers.indices.contains(3) ? numbers[3] : nil)
        )
    }

    private func numericValue(from value: Any) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private func byteValue(from value: Double) -> Int {
        let scaled = value <= 1 ? value * 255 : value
        return Int(round(min(255, max(0, scaled))))
    }

    private func alphaValue(from value: Double?) -> Double {
        guard let value else {
            return 1
        }
        let scaled = value > 1 ? value / 255 : value
        return min(1, max(0, scaled))
    }

    private func alphaByte(from value: Double) -> Int {
        Int(round(min(255, max(0, value * 255))))
    }
}

private struct ColorComponents {
    /// Red channel, in the range 0...255.
    let red: Int
    /// Green channel, in the range 0...255.
    let green: Int
    /// Blue channel, in the range 0...255.
    let blue: Int
    /// Alpha channel, in the range 0...1.
    let alpha: Double
}
