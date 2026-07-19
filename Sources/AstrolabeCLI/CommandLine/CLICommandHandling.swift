//
//  CLICommandHandling.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

protocol CLICommandHandling {
    var supportedCommands: [String] { get }
    func run(command: String, arguments: [String]) throws -> CLICommandOutput
}

enum CLICommandResponse {
    static func success(command: String, data: [String: Any]) -> CLICommandOutput {
        .jsonObject([
            "schemaVersion": CLIOutputSchema.currentVersion,
            "command": command,
            "success": true,
            "data": data
        ])
    }
}
