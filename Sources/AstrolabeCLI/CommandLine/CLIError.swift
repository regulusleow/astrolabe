//
//  CLIError.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

package protocol CLIErrorMetadataProviding: Error {
    var errorCode: String { get }
    var errorRecoverySuggestion: String { get }
}

package enum CLIError: Error, CustomStringConvertible {
    case missingCommand
    case missingArgument(String)
    case unsupportedCommand(String)
    case invalidArgument(String)
    case commandFailed(String)
    case invalidJSONObject
    case invalidScreenshot(String)
    case invalidBaseline(String)
    case timeout(String)
    case nodeNotFound
    case invalidHierarchySnapshot
    case hierarchySnapshotExpired
    case hierarchySnapshotMismatch
    case hierarchySnapshotStorageLimitExceeded
    case snapshotNodeNotFound
    case invalidPaginationCursor
    case paginationCursorMismatch
    case paginationSnapshotChanged
    case paginationSnapshotExpired
    case paginationSnapshotStorageLimitExceeded
    case targetProviderNotFound(String)
    case targetCapabilityUnsupported(
        appId: String,
        providerIdentifier: String,
        capability: RuntimeUICapability
    )

    package var description: String {
        switch self {
        case .missingCommand:
            return "Missing command"
        case .missingArgument(let argument):
            return "Missing argument: \(argument)"
        case .unsupportedCommand(let command):
            return "Unsupported command: \(command)"
        case .invalidArgument(let message):
            return "Invalid argument: \(message)"
        case .commandFailed(let message):
            return "Command failed: \(message)"
        case .invalidJSONObject:
            return "Invalid JSON data"
        case .invalidScreenshot(let message):
            return "Invalid screenshot data: \(message)"
        case .invalidBaseline(let message):
            return "Invalid baseline: \(message)"
        case .timeout(let operation):
            return "\(operation) timed out"
        case .nodeNotFound:
            return "No matching UI node found"
        case .invalidHierarchySnapshot:
            return "Invalid page hierarchy snapshot"
        case .hierarchySnapshotExpired:
            return "Page hierarchy snapshot expired"
        case .hierarchySnapshotMismatch:
            return "Page hierarchy snapshot does not match the current app"
        case .hierarchySnapshotStorageLimitExceeded:
            return "Page hierarchy snapshot exceeds the local storage limit"
        case .snapshotNodeNotFound:
            return "The requested node does not exist in the page hierarchy snapshot"
        case .invalidPaginationCursor:
            return "Invalid pagination cursor"
        case .paginationCursorMismatch:
            return "Pagination cursor does not match the current app or query"
        case .paginationSnapshotChanged:
            return "Pagination snapshot data is no longer valid"
        case .paginationSnapshotExpired:
            return "Pagination snapshot expired"
        case .paginationSnapshotStorageLimitExceeded:
            return "Pagination snapshot exceeds the local storage limit"
        case .targetProviderNotFound(let appId):
            return "No Runtime UI Provider can handle appId: \(appId)"
        case .targetCapabilityUnsupported(let appId, let providerIdentifier, let capability):
            return "Runtime UI Provider \(providerIdentifier) does not support \(capability.rawValue): \(appId)"
        }
    }

    var code: String {
        switch self {
        case .missingCommand:
            return "missing_command"
        case .missingArgument:
            return "missing_argument"
        case .unsupportedCommand:
            return "unsupported_command"
        case .invalidArgument:
            return "invalid_argument"
        case .commandFailed:
            return "command_failed"
        case .invalidJSONObject:
            return "invalid_json_object"
        case .invalidScreenshot:
            return "invalid_screenshot"
        case .invalidBaseline:
            return "invalid_baseline"
        case .timeout:
            return "timeout"
        case .nodeNotFound:
            return "node_not_found"
        case .invalidHierarchySnapshot:
            return "invalid_hierarchy_snapshot"
        case .hierarchySnapshotExpired:
            return "hierarchy_snapshot_expired"
        case .hierarchySnapshotMismatch:
            return "hierarchy_snapshot_mismatch"
        case .hierarchySnapshotStorageLimitExceeded:
            return "hierarchy_snapshot_storage_limit_exceeded"
        case .snapshotNodeNotFound:
            return "snapshot_node_not_found"
        case .invalidPaginationCursor:
            return "invalid_pagination_cursor"
        case .paginationCursorMismatch:
            return "pagination_cursor_mismatch"
        case .paginationSnapshotChanged:
            return "pagination_snapshot_changed"
        case .paginationSnapshotExpired:
            return "pagination_snapshot_expired"
        case .paginationSnapshotStorageLimitExceeded:
            return "pagination_snapshot_storage_limit_exceeded"
        case .targetProviderNotFound:
            return "target_provider_not_found"
        case .targetCapabilityUnsupported:
            return "target_capability_unsupported"
        }
    }

    var recoverySuggestion: String {
        switch self {
        case .missingCommand:
            return "Specify a command to run"
        case .missingArgument:
            return "Provide the missing argument and try again"
        case .unsupportedCommand:
            return "Check the command name and argument spelling"
        case .invalidArgument:
            return "Check that the argument combination is valid"
        case .commandFailed:
            return "Verify local command-line tools, device connectivity, and execution permissions, then try again"
        case .invalidJSONObject:
            return "Check the Runtime UI Provider response and local output structure"
        case .invalidScreenshot:
            return "Ensure the target screen is awake and visible, then capture another screenshot"
        case .invalidBaseline:
            return "Use a manifest generated by the current record-baseline command"
        case .timeout:
            return "Ensure the target app is running and its Runtime UI Provider is reachable"
        case .nodeNotFound:
            return "Use find-nodes or inspect-screen to locate an inspectable node first"
        case .invalidHierarchySnapshot:
            return "Use the complete snapshotId returned by a hierarchy tool"
        case .hierarchySnapshotExpired:
            return "Capture the current page again and use the new snapshotId"
        case .hierarchySnapshotMismatch:
            return "Use a snapshotId captured for the current appId"
        case .hierarchySnapshotStorageLimitExceeded:
            return "Reduce the current hierarchy size or wait for older snapshots to expire"
        case .snapshotNodeNotFound:
            return "Find the node in the specified snapshot instead of reusing an oid from another page"
        case .invalidPaginationCursor:
            return "Use the complete nextCursor returned by the previous find-nodes call"
        case .paginationCursorMismatch:
            return "Keep appId and query filters unchanged, or restart from the first page"
        case .paginationSnapshotChanged:
            return "Restart find-nodes from the first page to avoid combining results from different UI snapshots"
        case .paginationSnapshotExpired:
            return "Restart find-nodes from the first page to create a new frozen snapshot"
        case .paginationSnapshotStorageLimitExceeded:
            return "Narrow the node query or wait for older pagination snapshots to expire"
        case .targetProviderNotFound:
            return "Run list-apps again and use the current appId"
        case .targetCapabilityUnsupported:
            return "Check the capabilities returned by list-apps and select an app that supports the required capability"
        }
    }

    static func code(for error: Error) -> String {
        if let cliError = error as? CLIError {
            return cliError.code
        }
        if let metadata = error as? any CLIErrorMetadataProviding {
            return metadata.errorCode
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain || nsError.domain == NSPOSIXErrorDomain {
            return "file_io_failed"
        }
        return "unknown_error"
    }

    static func recoverySuggestion(for error: Error) -> String {
        if let cliError = error as? CLIError {
            return cliError.recoverySuggestion
        }
        if let metadata = error as? any CLIErrorMetadataProviding {
            return metadata.errorRecoverySuggestion
        }
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain || nsError.domain == NSPOSIXErrorDomain {
            return "Check that input and output paths exist and have the required permissions"
        }
        return "Review the failure details and try again"
    }

}
