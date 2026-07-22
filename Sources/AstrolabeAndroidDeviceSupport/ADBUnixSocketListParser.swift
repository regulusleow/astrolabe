//
//  ADBUnixSocketListParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import Foundation

package struct ADBUnixSocketListParser {
    package init() {}

    package func abstractSocketNames(from output: String) -> [String] {
        var names = [String]()
        var seenNames = Set<String>()
        for line in output.split(whereSeparator: \Character.isNewline) {
            guard let path = line.split(whereSeparator: \Character.isWhitespace).last,
                  path.first == "@" else {
                continue
            }
            let name = String(path.dropFirst())
            guard !name.isEmpty, seenNames.insert(name).inserted else {
                continue
            }
            names.append(name)
        }
        return names
    }
}
