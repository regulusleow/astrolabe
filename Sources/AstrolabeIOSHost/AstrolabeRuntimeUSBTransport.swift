//
//  AstrolabeRuntimeUSBTransport.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/12.
//

import AstrolabeCLI
import AstrolabeCoreObjC
import AstrolabeIOSDeviceSupport
import AstrolabeProtocol
import AstrolabeRuntimeHostCore
import Foundation

struct USBMuxAstrolabeRuntimeEndpointDiscovery:
    AstrolabeRuntimeEndpointDiscovering {
    private let deviceDiscovery: any USBMuxDeviceDiscovering

    init(
        deviceDiscovery: any USBMuxDeviceDiscovering =
            CoreUSBMuxDeviceDiscovery()
    ) {
        self.deviceDiscovery = deviceDiscovery
    }

    func discoverEndpoints() -> AstrolabeRuntimeEndpointDiscoverySnapshot {
        do {
            let devices = try deviceDiscovery.connectedDevices()
            guard !devices.isEmpty else {
                return snapshotWithDiagnostic(
                    deviceId: "usbmux",
                    errorCode: "usb_device_not_connected",
                    message: "No iOS device connected by USB was found",
                    recoverySuggestion: "Connect and trust a physical iOS device, enable Developer Mode, and try again"
                )
            }
            let endpoints = devices.flatMap { device in
                AstrolabeIOSRuntimePortDefaults.deviceRange.map { port in
                    AstrolabeRuntimeEndpoint(
                        connectionKind: "usb",
                        deviceId: device.deviceIdentifier,
                        host: "usbmux",
                        port: port
                    )
                }
            }
            let diagnostics = devices.compactMap { device in
                guard device.serialNumber?.isEmpty == false else {
                    return RuntimeAppDiscoveryDiagnostic(
                        providerIdentifier: "astrolabe-ios-runtime",
                        platform: .ios,
                        connectionKind: "usb",
                        deviceId: device.deviceIdentifier,
                        endpointPort: 0,
                        errorCode: "usb_device_identity_unavailable",
                        message: "The USB device did not provide a serial number for screenshot binding",
                        recoverySuggestion: "Reconnect and trust the physical device, then try again"
                    )
                }
                return nil
            }
            return AstrolabeRuntimeEndpointDiscoverySnapshot(
                endpoints: endpoints,
                diagnostics: diagnostics
            )
        } catch {
            return snapshotWithDiagnostic(
                deviceId: "usbmux",
                errorCode: "usb_device_discovery_failed",
                message: "USB device discovery failed: \(error.localizedDescription)",
                recoverySuggestion: "Check the usbmux service, USB connection, and device trust state, then try again"
            )
        }
    }

    private func snapshotWithDiagnostic(
        deviceId: String,
        errorCode: String,
        message: String,
        recoverySuggestion: String
    ) -> AstrolabeRuntimeEndpointDiscoverySnapshot {
        AstrolabeRuntimeEndpointDiscoverySnapshot(
            endpoints: [],
            diagnostics: [RuntimeAppDiscoveryDiagnostic(
                providerIdentifier: "astrolabe-ios-runtime",
                platform: .ios,
                connectionKind: "usb",
                deviceId: deviceId,
                endpointPort: 0,
                errorCode: errorCode,
                message: message,
                recoverySuggestion: recoverySuggestion
            )]
        )
    }
}

struct DefaultAstrolabeRuntimeTransportFactory:
    AstrolabeRuntimeTransportCreating {
    private let tcpFactory = TCPAstrolabeRuntimeTransportFactory()
    private let usbFactory = USBMuxAstrolabeRuntimeTransportFactory()

    func makeTransport(
        endpoint: AstrolabeRuntimeEndpoint
    ) throws -> any AstrolabeRuntimeTransport {
        switch endpoint.connectionKind {
        case "simulator":
            return try tcpFactory.makeTransport(endpoint: endpoint)
        case "usb":
            return try usbFactory.makeTransport(endpoint: endpoint)
        default:
            throw AstrolabeRuntimeClientError.connectionFailed(
                "Unsupported Runtime connection kind: \(endpoint.connectionKind)"
            )
        }
    }
}

struct USBMuxAstrolabeRuntimeTransportFactory:
    AstrolabeRuntimeTransportCreating {
    func makeTransport(
        endpoint: AstrolabeRuntimeEndpoint
    ) throws -> any AstrolabeRuntimeTransport {
        guard UInt64(endpoint.deviceId).map({ $0 > 0 }) == true else {
            throw AstrolabeRuntimeClientError.connectionFailed(
                "Invalid USB device identifier: \(endpoint.deviceId)"
            )
        }
        guard let connection = ASTUSBMuxConnection(
            deviceIdentifier: endpoint.deviceId,
            port: endpoint.port
        ) else {
            throw AstrolabeRuntimeClientError.connectionFailed(
                "Invalid USB Runtime endpoint"
            )
        }
        return USBMuxAstrolabeRuntimeTransport(connection: connection)
    }
}

private final class USBMuxAstrolabeRuntimeTransport:
    AstrolabeRuntimeTransport {
    private let connection: ASTUSBMuxConnection
    private let connectTimeout: TimeInterval
    private let requestTimeout: TimeInterval
    private var didConnect = false

    init(
        connection: ASTUSBMuxConnection,
        connectTimeout: TimeInterval = 1,
        requestTimeout: TimeInterval = 30
    ) {
        self.connection = connection
        self.connectTimeout = connectTimeout
        self.requestTimeout = requestTimeout
    }

    func connect() throws {
        guard !didConnect else {
            return
        }
        do {
            try connection.connect(withTimeout: connectTimeout)
        } catch {
            throw AstrolabeRuntimeClientError.connectionFailed(
                error.localizedDescription
            )
        }
        didConnect = true
    }

    func send(_ data: Data) throws {
        guard didConnect else {
            throw AstrolabeRuntimeClientError.connectionClosed
        }
        do {
            try connection.send(data, timeout: requestTimeout)
        } catch {
            throw AstrolabeRuntimeClientError.connectionFailed(
                error.localizedDescription
            )
        }
    }

    func receive(byteCount: Int) throws -> Data {
        guard didConnect else {
            throw AstrolabeRuntimeClientError.connectionClosed
        }
        guard byteCount >= 0 else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "USB Runtime read length cannot be negative"
            )
        }
        do {
            return try connection.receiveData(
                ofLength: UInt(byteCount),
                timeout: requestTimeout
            )
        } catch {
            throw AstrolabeRuntimeClientError.connectionFailed(
                error.localizedDescription
            )
        }
    }

    func close() {
        didConnect = false
        connection.close()
    }
}
