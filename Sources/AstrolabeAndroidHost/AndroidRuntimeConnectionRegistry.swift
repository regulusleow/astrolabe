//
//  AndroidRuntimeConnectionRegistry.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeAndroidDeviceSupport
import AstrolabeCLI
import AstrolabeProtocol
import AstrolabeRuntimeHostCore
import Foundation

struct AndroidRuntimeDiscoverySnapshot {
    /// Runtime bindings discovered during the current ADB scan.
    let bindings: [AndroidRuntimeBinding]

    /// Device and Runtime diagnostics produced during discovery.
    let diagnostics: [RuntimeAppDiscoveryDiagnostic]
}

final class AndroidRuntimeBinding {
    /// Stable app identity encoded into Host command targets.
    let appID: AndroidRuntimeAppID

    /// ADB device metadata captured during discovery.
    let device: ADBDevice

    /// Shared Runtime session target using the current local forward.
    let sessionTarget: AstrolabeRuntimeSessionTarget

    /// Runtime handshake captured while validating the forward.
    let handshake: RuntimeHandshakePayload

    /// Runtime application information captured during discovery.
    let appInfo: RuntimeApplicationInfoPayload

    /// Runtime compatibility evaluated for the Android Provider.
    let compatibility: AstrolabeRuntimeCompatibility

    /// Owned ADB forward removed when this binding is replaced or released.
    private let forwardLease: ADBForwardLease

    init(
        appID: AndroidRuntimeAppID,
        device: ADBDevice,
        sessionTarget: AstrolabeRuntimeSessionTarget,
        handshake: RuntimeHandshakePayload,
        appInfo: RuntimeApplicationInfoPayload,
        compatibility: AstrolabeRuntimeCompatibility,
        forwardLease: ADBForwardLease
    ) {
        self.appID = appID
        self.device = device
        self.sessionTarget = sessionTarget
        self.handshake = handshake
        self.appInfo = appInfo
        self.compatibility = compatibility
        self.forwardLease = forwardLease
    }

    func close() {
        forwardLease.close()
    }
}

final class AndroidRuntimeConnectionRegistry {
    private struct ProcessKey: Hashable {
        /// ADB serial containing the process.
        let deviceSerial: String

        /// Device process identifier owning the Runtime socket.
        let processIdentifier: Int
    }

    private let adbClient: ADBClient
    private let clientFactory: any AstrolabeRuntimeClientCreating
    private let compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy
    private let lock = NSLock()
    private var bindingsByProcess = [ProcessKey: AndroidRuntimeBinding]()
    private var bindingsByAppID = [String: AndroidRuntimeBinding]()

    init(
        adbClient: ADBClient,
        clientFactory: any AstrolabeRuntimeClientCreating,
        compatibilityPolicy: AstrolabeRuntimeCompatibilityPolicy
    ) {
        self.adbClient = adbClient
        self.clientFactory = clientFactory
        self.compatibilityPolicy = compatibilityPolicy
    }

    deinit {
        close()
    }

    func close() {
        lock.lock()
        let bindings = Array(bindingsByProcess.values)
        bindingsByProcess.removeAll()
        bindingsByAppID.removeAll()
        lock.unlock()
        bindings.forEach { $0.close() }
    }

    func refresh() throws -> AndroidRuntimeDiscoverySnapshot {
        let deviceSnapshot = try adbClient.devices()
        var diagnostics = deviceSnapshot.unavailableDevices.map(deviceDiagnostic)
        var discoveredBindings = [AndroidRuntimeBinding]()
        var activeKeys = Set<ProcessKey>()

        for device in deviceSnapshot.readyDevices {
            let processIdentifiers: [Int]
            do {
                processIdentifiers = try runtimeProcessIdentifiers(deviceSerial: device.serial)
            } catch {
                diagnostics.append(adbDiagnostic(device: device, error: error))
                continue
            }
            var foundRuntime = false
            for processIdentifier in processIdentifiers {
                let key = ProcessKey(
                    deviceSerial: device.serial,
                    processIdentifier: processIdentifier
                )
                switch discover(
                    device: device,
                    processIdentifier: processIdentifier,
                    expectedAppID: nil
                ) {
                case let .success(binding):
                    store(binding, for: key)
                    activeKeys.insert(key)
                    discoveredBindings.append(binding)
                    foundRuntime = true
                case let .diagnostic(diagnostic):
                    diagnostics.append(diagnostic)
                case .unavailable:
                    break
                }
            }
            if !foundRuntime {
                diagnostics.append(runtimeUnavailableDiagnostic(device: device))
            }
        }
        removeBindings(excluding: activeKeys)
        return AndroidRuntimeDiscoverySnapshot(
            bindings: discoveredBindings,
            diagnostics: diagnostics
        )
    }

    func resolve(appID: AndroidRuntimeAppID) throws -> AndroidRuntimeBinding {
        lock.lock()
        if let binding = bindingsByAppID[appID.rawValue] {
            lock.unlock()
            return binding
        }
        lock.unlock()

        let device = ADBDevice(
            serial: appID.deviceSerial,
            state: .device,
            connectionKind: ADBDeviceConnectionKind.classify(
                serial: appID.deviceSerial
            ),
            model: nil,
            product: nil,
            deviceName: nil
        )
        let key = ProcessKey(
            deviceSerial: appID.deviceSerial,
            processIdentifier: appID.processIdentifier
        )
        switch discover(
            device: device,
            processIdentifier: appID.processIdentifier,
            expectedAppID: appID
        ) {
        case let .success(binding):
            store(binding, for: key)
            return binding
        case .diagnostic:
            throw AstrolabeRuntimeClientError.connectionFailed(
                "The Android Runtime endpoint could not be validated"
            )
        case .unavailable:
            throw AstrolabeRuntimeClientError.connectionFailed(
                "No Astrolabe Runtime socket is available for Android process \(appID.processIdentifier)"
            )
        }
    }

    private enum DiscoveryResult {
        case success(AndroidRuntimeBinding)
        case diagnostic(RuntimeAppDiscoveryDiagnostic)
        case unavailable
    }

    private func discover(
        device: ADBDevice,
        processIdentifier: Int,
        expectedAppID: AndroidRuntimeAppID?
    ) -> DiscoveryResult {
        let socketName = "astrolabe_\(processIdentifier)"
        let lease: ADBForwardLease
        do {
            lease = try ADBForwardLease.open(
                client: adbClient,
                deviceSerial: device.serial,
                socketName: socketName
            )
        } catch {
            return .diagnostic(adbDiagnostic(device: device, error: error))
        }
        let endpoint = AstrolabeRuntimeEndpoint(
            connectionKind: device.connectionKind.rawValue,
            deviceId: device.serial,
            host: "127.0.0.1",
            port: lease.localPort
        )
        do {
            let client = try clientFactory.makeClient(endpoint: endpoint)
            defer { client.close() }
            let handshake = try client.handshake()
            let compatibility = compatibilityPolicy.evaluate(handshake: handshake)
            guard compatibility.isExpectedPlatform,
                  compatibility.runtimeCapabilities.contains(.applicationInfo) else {
                lease.close()
                return .diagnostic(runtimeDiagnostic(
                    device: device,
                    endpoint: endpoint,
                    error: .invalidResponse(
                        "The forwarded Runtime is not a compatible Android Runtime"
                    )
                ))
            }
            let appInfo = try client.appInfo()
            guard appInfo.target.identifier == handshake.runtime.instanceID,
                  appInfo.target.processIdentifier == String(processIdentifier) else {
                throw AstrolabeRuntimeClientError.invalidResponse(
                    "App information does not match the discovered Runtime process"
                )
            }
            let appID = AndroidRuntimeAppID(
                deviceSerial: device.serial,
                processIdentifier: processIdentifier,
                applicationIdentifier: appInfo.application.identifier,
                runtimeInstanceIdentifier: handshake.runtime.instanceID.rawValue
            )
            if let expectedAppID, expectedAppID != appID {
                throw AstrolabeRuntimeClientError.staleApp(
                    runtimeInstanceIdentifier: handshake.runtime.instanceID.rawValue
                )
            }
            return .success(AndroidRuntimeBinding(
                appID: appID,
                device: device,
                sessionTarget: AstrolabeRuntimeSessionTarget(
                    appID: appID.rawValue,
                    runtimeInstanceIdentifier: appID.runtimeInstanceIdentifier,
                    endpoint: endpoint
                ),
                handshake: handshake,
                appInfo: appInfo,
                compatibility: compatibility,
                forwardLease: lease
            ))
        } catch let error as AstrolabeRuntimeClientError {
            lease.close()
            switch error {
            case .connectionFailed, .connectionClosed:
                return .unavailable
            case let .timeout(operation)
                where operation == "Connect to Astrolabe Runtime":
                return .unavailable
            default:
                return .diagnostic(runtimeDiagnostic(
                    device: device,
                    endpoint: endpoint,
                    error: error
                ))
            }
        } catch {
            lease.close()
            return .unavailable
        }
    }

    private func store(_ binding: AndroidRuntimeBinding, for key: ProcessKey) {
        lock.lock()
        let replacedBinding = bindingsByProcess.updateValue(binding, forKey: key)
        if let replacedBinding,
           replacedBinding !== binding,
           replacedBinding.appID.rawValue != binding.appID.rawValue {
            bindingsByAppID.removeValue(forKey: replacedBinding.appID.rawValue)
        }
        bindingsByAppID[binding.appID.rawValue] = binding
        lock.unlock()
        if let replacedBinding, replacedBinding !== binding {
            replacedBinding.close()
        }
    }

    private func removeBindings(excluding activeKeys: Set<ProcessKey>) {
        lock.lock()
        let staleKeys = bindingsByProcess.keys.filter { !activeKeys.contains($0) }
        let staleBindings = staleKeys.compactMap { key -> AndroidRuntimeBinding? in
            guard let binding = bindingsByProcess.removeValue(forKey: key) else {
                return nil
            }
            bindingsByAppID.removeValue(forKey: binding.appID.rawValue)
            return binding
        }
        lock.unlock()
        staleBindings.forEach { $0.close() }
    }

    private func runtimeProcessIdentifiers(deviceSerial: String) throws -> [Int] {
        let socketPrefix = "astrolabe_"
        return try adbClient.abstractSocketNames(deviceSerial: deviceSerial)
            .compactMap { socketName -> Int? in
                guard socketName.hasPrefix(socketPrefix) else {
                    return nil
                }
                let suffix = socketName.dropFirst(socketPrefix.count)
                guard let processIdentifier = Int(suffix), processIdentifier > 0 else {
                    return nil
                }
                return processIdentifier
            }
            .sorted()
    }

    private func deviceDiagnostic(_ device: ADBDevice) -> RuntimeAppDiscoveryDiagnostic {
        RuntimeAppDiscoveryDiagnostic(
            providerIdentifier: "astrolabe-android-runtime",
            platform: .android,
            connectionKind: device.connectionKind.rawValue,
            deviceId: device.serial,
            endpointPort: 0,
            errorCode: "adb_device_\(device.state.rawValue)",
            message: "ADB device \(device.serial) is \(device.state.rawValue)",
            recoverySuggestion: device.state == .unauthorized
                ? "Authorize the Android device for USB debugging"
                : "Reconnect the Android device and wait for ADB to report device state"
        )
    }

    private func adbDiagnostic(
        device: ADBDevice,
        error: Error
    ) -> RuntimeAppDiscoveryDiagnostic {
        RuntimeAppDiscoveryDiagnostic(
            providerIdentifier: "astrolabe-android-runtime",
            platform: .android,
            connectionKind: device.connectionKind.rawValue,
            deviceId: device.serial,
            endpointPort: 0,
            errorCode: "adb_command_failed",
            message: String(describing: error),
            recoverySuggestion: "Verify ADB access to the selected device and try again"
        )
    }

    private func runtimeDiagnostic(
        device: ADBDevice,
        endpoint: AstrolabeRuntimeEndpoint,
        error: AstrolabeRuntimeClientError
    ) -> RuntimeAppDiscoveryDiagnostic {
        RuntimeAppDiscoveryDiagnostic(
            providerIdentifier: "astrolabe-android-runtime",
            platform: .android,
            connectionKind: device.connectionKind.rawValue,
            deviceId: device.serial,
            endpointPort: Int(endpoint.port),
            errorCode: error.code,
            message: error.description,
            recoverySuggestion: error.recoverySuggestion
        )
    }

    private func runtimeUnavailableDiagnostic(
        device: ADBDevice
    ) -> RuntimeAppDiscoveryDiagnostic {
        RuntimeAppDiscoveryDiagnostic(
            providerIdentifier: "astrolabe-android-runtime",
            platform: .android,
            connectionKind: device.connectionKind.rawValue,
            deviceId: device.serial,
            endpointPort: 0,
            errorCode: "android_runtime_unavailable",
            message: "No Astrolabe Android Runtime socket was found on the device",
            recoverySuggestion: "Launch an app that integrates astrolabe-runtime-android"
        )
    }
}
