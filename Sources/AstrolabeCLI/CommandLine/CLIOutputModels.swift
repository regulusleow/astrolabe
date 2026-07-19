//
//  CLIOutputModels.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

enum CLIOutputSchema {
    static let currentVersion = 4
}

struct CommandResult<Payload: Encodable>: Encodable {
    /// Output schema version used by MCP and AI tools to determine JSON contract compatibility.
    let schemaVersion: Int

    /// Name of the CLI command being executed.
    let command: String?

    /// Whether the command succeeded.
    let success: Bool

    /// Stable machine-matchable error code for failures.
    let errorCode: String?

    /// Error message returned on failure.
    let error: String?

    /// Suggested next recovery step for AI or users after a failure.
    let recoverySuggestion: String?

    /// Data returned by the command.
    let data: Payload?

    init(
        success: Bool,
        error: String?,
        data: Payload?,
        schemaVersion: Int = CLIOutputSchema.currentVersion,
        command: String? = nil,
        errorCode: String? = nil,
        recoverySuggestion: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.command = command
        self.success = success
        self.errorCode = errorCode
        self.error = error
        self.recoverySuggestion = recoverySuggestion
        self.data = data
    }
}
struct EmptyPayload: Encodable {
}

struct AppListPayload: Encodable {
    /// Currently discovered inspectable apps.
    let apps: [InspectableAppRecord]

    /// Diagnostics for connected Runtime endpoints that failed to complete the handshake.
    let diagnostics: [RuntimeAppDiscoveryDiagnostic]

    init(
        apps: [InspectableAppRecord],
        diagnostics: [RuntimeAppDiscoveryDiagnostic] = []
    ) {
        self.apps = apps
        self.diagnostics = diagnostics
    }
}
