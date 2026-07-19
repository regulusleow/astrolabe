//
//  CLICommandOutput.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

enum CLICommandOutput {
    case appList(CommandResult<AppListPayload>)
    case empty(CommandResult<EmptyPayload>)
    case jsonObject([String: Any])

    func print() throws {
        switch self {
        case .appList(let result):
            try JSONOutput.printJSON(result)
        case .empty(let result):
            try JSONOutput.printJSON(result)
        case .jsonObject(let object):
            try JSONOutput.printJSONObject(object)
        }
    }
}
