//
//  AstrolabeRuntimeProtocolClient.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/11.
//

import AstrolabeCLI
import AstrolabeProtocol
import Foundation

package enum AstrolabeRuntimeClientError: Error, CustomStringConvertible {
    case invalidAppID(String)
    case connectionFailed(String)
    case connectionClosed
    case timeout(String)
    case invalidResponse(String)
    case staleApp(runtimeInstanceIdentifier: String)
    case protocolVersionMismatch(host: RuntimeProtocolVersion, runtime: RuntimeProtocolVersion)
    case updateRequired(runtimeVersion: String, missingCapabilities: [String])
    case remote(RuntimeError)

    package var description: String {
        switch self {
        case let .invalidAppID(appID):
            return "Invalid Astrolabe Runtime appId: \(appID)"
        case let .connectionFailed(message):
            return "Astrolabe Runtime connection failed: \(message)"
        case .connectionClosed:
            return "Astrolabe Runtime connection closed"
        case let .timeout(operation):
            return "\(operation) timed out"
        case let .invalidResponse(message):
            return "Invalid Astrolabe Runtime response: \(message)"
        case let .staleApp(runtimeInstanceIdentifier):
            return "The Astrolabe Runtime app restarted; current instance: \(runtimeInstanceIdentifier)"
        case let .protocolVersionMismatch(host, runtime):
            return "Astrolabe Host protocol \(host.major).\(host.minor) is incompatible with Runtime protocol \(runtime.major).\(runtime.minor)"
        case let .updateRequired(runtimeVersion, missingCapabilities):
            return "Astrolabe Runtime \(runtimeVersion) is missing capabilities: \(missingCapabilities.joined(separator: ", "))"
        case let .remote(error):
            return "Astrolabe Runtime returned error \(error.code.rawValue): \(error.message)"
        }
    }

    var code: String {
        switch self {
        case .invalidAppID:
            return "astrolabe_runtime_invalid_app_id"
        case .connectionFailed, .connectionClosed:
            return "astrolabe_runtime_connection_failed"
        case .timeout:
            return "astrolabe_runtime_request_timeout"
        case .invalidResponse:
            return "astrolabe_runtime_invalid_response"
        case .staleApp:
            return "astrolabe_runtime_stale_app"
        case .protocolVersionMismatch:
            return "astrolabe_runtime_protocol_version_mismatch"
        case .updateRequired:
            return "astrolabe_runtime_update_required"
        case let .remote(error):
            return "astrolabe_runtime_\(error.code.rawValue)"
        }
    }

    var recoverySuggestion: String {
        switch self {
        case .invalidAppID, .staleApp:
            return "Run list-apps again and use the current appId"
        case .connectionFailed, .connectionClosed, .timeout:
            return "Ensure the target app remains in the foreground and Astrolabe Runtime is running"
        case .invalidResponse:
            return "Ensure the Host and Astrolabe Runtime protocol versions match"
        case let .protocolVersionMismatch(host, runtime):
            if runtime.major < host.major {
                return "Update astrolabe-runtime-ios, then rebuild and launch the app"
            }
            return "Update Astrolabe Host and try again"
        case let .updateRequired(runtimeVersion, missingCapabilities):
            return AstrolabeRuntimeCompatibilityMessage.updateSuggestion(
                runtimeVersion: runtimeVersion,
                missingCapabilities: missingCapabilities
            )
        case let .remote(error):
            return error.recoverySuggestion ?? "Follow the Runtime error details and try again"
        }
    }
}

extension AstrolabeRuntimeClientError: CLIErrorMetadataProviding {
    package var errorCode: String { code }
    package var errorRecoverySuggestion: String { recoverySuggestion }
}

protocol AstrolabeRuntimeClient: AnyObject {
    func handshake() throws -> RuntimeHandshakePayload
    func appInfo() throws -> RuntimeApplicationInfoPayload
    func hierarchySnapshot() throws -> RuntimeHierarchySnapshotPayload
    func nodeDetail(nodeID: RuntimeOpaqueIdentifier) throws -> RuntimeNodeDetailPayload
    func patchableAttributes() throws -> RuntimePatchableAttributesPayload
    func applyAttributePatch(_ parameters: RuntimeApplyAttributePatchParameters) throws -> RuntimeAttributePatch
    func attributePatches() throws -> RuntimeAttributePatchListPayload
    func revertAttributePatch(_ parameters: RuntimeRevertAttributePatchParameters) throws -> RuntimeRevertAttributePatchPayload
    func clearAttributePatches() throws -> RuntimeClearAttributePatchesPayload
    func close()
}

protocol AstrolabeRuntimeClientCreating {
    func makeClient(endpoint: AstrolabeRuntimeEndpoint) throws -> any AstrolabeRuntimeClient
}

struct AstrolabeRuntimeProtocolClientFactory: AstrolabeRuntimeClientCreating {
    private let transportFactory: any AstrolabeRuntimeTransportCreating

    init(transportFactory: any AstrolabeRuntimeTransportCreating = DefaultAstrolabeRuntimeTransportFactory()) {
        self.transportFactory = transportFactory
    }

    func makeClient(endpoint: AstrolabeRuntimeEndpoint) throws -> any AstrolabeRuntimeClient {
        AstrolabeRuntimeProtocolClient(transport: try transportFactory.makeTransport(endpoint: endpoint))
    }
}

final class AstrolabeRuntimeProtocolClient: AstrolabeRuntimeClient {
    private let transport: any AstrolabeRuntimeTransport
    private let frameCodec: RuntimeFrameCodec
    private let messageCodec = RuntimeMessageCodec()
    private var handshakePayload: RuntimeHandshakePayload?
    private var didConnect = false

    init(transport: any AstrolabeRuntimeTransport, frameCodec: RuntimeFrameCodec = RuntimeFrameCodec()) {
        self.transport = transport
        self.frameCodec = frameCodec
    }

    deinit { transport.close() }

    func handshake() throws -> RuntimeHandshakePayload {
        if let handshakePayload { return handshakePayload }
        try connectIfNeeded()
        let payload: RuntimeHandshakePayload = try request(
            method: .handshake,
            parameters: RuntimeHandshakeParameters(
                client: RuntimeClientDescriptor(name: "Astrolabe", version: AstrolabeHostMetadata.version),
                supportedProtocolRange: .v2
            )
        )
        handshakePayload = payload
        return payload
    }

    func appInfo() throws -> RuntimeApplicationInfoPayload {
        try ensureHandshake()
        return try request(method: .applicationInfo, parameters: RuntimeApplicationInfoParameters())
    }

    func hierarchySnapshot() throws -> RuntimeHierarchySnapshotPayload {
        try ensureHandshake()
        return try request(method: .hierarchySnapshot, parameters: RuntimeHierarchySnapshotParameters())
    }

    func nodeDetail(nodeID: RuntimeOpaqueIdentifier) throws -> RuntimeNodeDetailPayload {
        try ensureHandshake()
        return try request(method: .nodeDetail, parameters: RuntimeNodeDetailParameters(nodeID: nodeID))
    }

    func patchableAttributes() throws -> RuntimePatchableAttributesPayload {
        try ensureHandshake()
        return try request(method: .patchableAttributes, parameters: RuntimePatchableAttributesParameters())
    }

    func applyAttributePatch(_ parameters: RuntimeApplyAttributePatchParameters) throws -> RuntimeAttributePatch {
        try ensureHandshake()
        return try request(method: .applyAttributePatch, parameters: parameters)
    }

    func attributePatches() throws -> RuntimeAttributePatchListPayload {
        try ensureHandshake()
        return try request(method: .listAttributePatches, parameters: RuntimeListAttributePatchesParameters())
    }

    func revertAttributePatch(_ parameters: RuntimeRevertAttributePatchParameters) throws -> RuntimeRevertAttributePatchPayload {
        try ensureHandshake()
        return try request(method: .revertAttributePatch, parameters: parameters)
    }

    func clearAttributePatches() throws -> RuntimeClearAttributePatchesPayload {
        try ensureHandshake()
        return try request(method: .clearAttributePatches, parameters: RuntimeClearAttributePatchesParameters())
    }

    func close() {
        didConnect = false
        transport.close()
    }

    private func connectIfNeeded() throws {
        guard !didConnect else { return }
        try transport.connect()
        didConnect = true
    }

    private func ensureHandshake() throws {
        if handshakePayload == nil { _ = try handshake() }
    }

    private func request<Parameters, Payload>(
        method: RuntimeMethod,
        parameters: Parameters
    ) throws -> Payload
    where Parameters: Codable & Equatable & Sendable,
          Payload: Codable & Equatable & Sendable {
        let request = try RuntimeRequest(method: method, parameters: parameters)
        let requestPayload = try messageCodec.encode(request)
        try transport.send(try frameCodec.encode(payload: requestPayload))

        let responsePayload = try receivePayload()
        let response: RuntimeResponse<Payload>
        do {
            response = try messageCodec.decode(RuntimeResponse<Payload>.self, from: responsePayload)
        } catch let RuntimeProtocolVersionError.unsupportedVersion(runtimeVersion) {
            throw AstrolabeRuntimeClientError.protocolVersionMismatch(host: .v2, runtime: runtimeVersion)
        } catch RuntimeMessageRoutingError.methodMismatch {
            throw AstrolabeRuntimeClientError.invalidResponse("Response method does not match the request")
        }
        guard response.requestID == request.requestID else {
            throw AstrolabeRuntimeClientError.invalidResponse("Response requestID does not match the request")
        }
        guard response.method == method else {
            throw AstrolabeRuntimeClientError.invalidResponse("Response method does not match the request")
        }
        switch response.outcome {
        case let .success(payload):
            return payload
        case let .failure(error):
            throw AstrolabeRuntimeClientError.remote(error)
        }
    }

    private func receivePayload() throws -> Data {
        let header = try transport.receive(byteCount: MemoryLayout<UInt32>.size)
        let payloadLength = header.reduce(UInt32(0)) { partialResult, byte in
            (partialResult << 8) | UInt32(byte)
        }
        guard payloadLength <= UInt32(frameCodec.maximumPayloadSize) else {
            throw AstrolabeRuntimeClientError.invalidResponse("Response exceeds the maximum frame size: \(payloadLength)")
        }
        return try transport.receive(byteCount: Int(payloadLength))
    }
}
