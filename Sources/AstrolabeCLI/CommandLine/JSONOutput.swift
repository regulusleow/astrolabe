//
//  JSONOutput.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

enum JSONOutput {
    static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            return
        }
        print(string)
    }

    static func printJSONObject(_ value: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(value) else {
            throw CLIError.invalidJSONObject
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else {
            return
        }
        print(string)
    }
}
