//
//  AstrolabeRuntimeConnectionTarget.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/11.
//

import AstrolabeCLI
import AstrolabeIOSDeviceSupport
import AstrolabeProtocol
import Foundation

enum AstrolabeIOSRuntimePortDefaults {
    /// Default discovery port range for simulator Runtimes.
    static let simulatorRange: ClosedRange<UInt16> = 47_200...47_209

    /// Default forwarded port range for physical USB Runtimes.
    static let deviceRange: ClosedRange<UInt16> = 47_210...47_219
}

struct AstrolabeRuntimeEndpoint: Hashable {
    /// Runtime connection type, such as simulator or usb.
    let connectionKind: String

    /// Identifier of the device hosting the Runtime.
    let deviceId: String

    /// Address used by the Host to connect to the Runtime.
    let host: String

    /// Port used by the Host to connect to the Runtime.
    let port: UInt16
}

struct AstrolabeRuntimeAppID: Hashable {
    /// Runtime connection type, such as simulator or usb.
    let connectionKind: String

    /// Identifier of the device hosting the Runtime.
    let deviceId: String

    /// Runtime listening port.
    let port: UInt16

    /// Opaque identifier of the Runtime process instance.
    let runtimeInstanceIdentifier: String

    var rawValue: String {
        IOSRuntimeAppIdentifier(
            connectionKind: connectionKind,
            deviceIdentifier: deviceId,
            port: port,
            runtimeInstanceIdentifier: runtimeInstanceIdentifier
        ).rawValue
    }

    var endpoint: AstrolabeRuntimeEndpoint {
        AstrolabeRuntimeEndpoint(
            connectionKind: connectionKind,
            deviceId: deviceId,
            host: connectionKind == "usb" ? "usbmux" : "127.0.0.1",
            port: port
        )
    }

    init(endpoint: AstrolabeRuntimeEndpoint, runtimeInstanceIdentifier: String) {
        connectionKind = endpoint.connectionKind
        deviceId = endpoint.deviceId
        port = endpoint.port
        self.runtimeInstanceIdentifier = runtimeInstanceIdentifier
    }

    init(rawValue: String) throws {
        guard let identifier = IOSRuntimeAppIdentifier(rawValue: rawValue) else {
            throw AstrolabeRuntimeClientError.invalidAppID(rawValue)
        }
        connectionKind = identifier.connectionKind
        deviceId = identifier.deviceIdentifier
        port = identifier.port
        runtimeInstanceIdentifier = identifier.runtimeInstanceIdentifier
    }
}

struct AstrolabeRuntimeEndpointDiscoverySnapshot {
    /// Runtime endpoints to connect to after this discovery pass.
    let endpoints: [AstrolabeRuntimeEndpoint]

    /// Device or transport diagnostics produced before establishing a Runtime endpoint.
    let diagnostics: [RuntimeAppDiscoveryDiagnostic]
}

protocol AstrolabeRuntimeEndpointDiscovering {
    func discoverEndpoints() -> AstrolabeRuntimeEndpointDiscoverySnapshot
}

struct SimulatorAstrolabeRuntimeEndpointDiscovery: AstrolabeRuntimeEndpointDiscovering {
    func discoverEndpoints() -> AstrolabeRuntimeEndpointDiscoverySnapshot {
        AstrolabeRuntimeEndpointDiscoverySnapshot(
            endpoints: AstrolabeIOSRuntimePortDefaults.simulatorRange.map { port in
                AstrolabeRuntimeEndpoint(
                    connectionKind: "simulator",
                    deviceId: "simulator",
                    host: "127.0.0.1",
                    port: port
                )
            },
            diagnostics: []
        )
    }
}

struct CompositeAstrolabeRuntimeEndpointDiscovery:
    AstrolabeRuntimeEndpointDiscovering {
    private let discoveries: [any AstrolabeRuntimeEndpointDiscovering]

    init(discoveries: [any AstrolabeRuntimeEndpointDiscovering]) {
        self.discoveries = discoveries
    }

    func discoverEndpoints() -> AstrolabeRuntimeEndpointDiscoverySnapshot {
        let snapshots = discoveries.map { $0.discoverEndpoints() }
        return AstrolabeRuntimeEndpointDiscoverySnapshot(
            endpoints: snapshots.flatMap(\.endpoints),
            diagnostics: snapshots.flatMap(\.diagnostics)
        )
    }
}
