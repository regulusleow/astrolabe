//
//  IOSSystemScreenshotProvider.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeCLI
import AstrolabeIOSDeviceSupport
import Foundation

package struct IOSSystemScreenshotProvider: PlatformScreenshotProviding {
    private let simctl: SimulatorScreenshotCapturing
    private let devicectl: DeviceScreenshotCapturing
    private let deviceIdentifierResolver: DeviceIdentifierResolving
    private let deviceLockStateReader: DeviceLockStateReading
    private let imageContentInspector: ScreenshotImageContentInspecting
    private let payloadBuilder: ScreenshotPayloadBuilding

    package init() {
        self.init(
            simctl: SimctlScreenshotCapturer(),
            devicectl: DevicectlScreenshotCapturer(),
            deviceIdentifierResolver: DevicectlDeviceIdentifierResolver(),
            deviceLockStateReader: DevicectlDeviceLockStateReader(),
            imageContentInspector: ScreenshotImageContentInspector(),
            payloadBuilder: ScreenshotPayloadBuilder()
        )
    }

    init(
        simctl: SimulatorScreenshotCapturing,
        devicectl: DeviceScreenshotCapturing,
        deviceIdentifierResolver: DeviceIdentifierResolving,
        deviceLockStateReader: DeviceLockStateReading,
        imageContentInspector: ScreenshotImageContentInspecting,
        payloadBuilder: ScreenshotPayloadBuilding
    ) {
        self.simctl = simctl
        self.devicectl = devicectl
        self.deviceIdentifierResolver = deviceIdentifierResolver
        self.deviceLockStateReader = deviceLockStateReader
        self.imageContentInspector = imageContentInspector
        self.payloadBuilder = payloadBuilder
    }

    package func capture(
        appId: String,
        options: ScreenshotCaptureOptions,
        screenMetadata: () throws -> [String: Any]
    ) throws -> [String: Any] {
        guard let appIdentifier = IOSRuntimeAppIdentifier(rawValue: appId) else {
            throw CLIError.invalidArgument("Invalid iOS Runtime appId: \(appId)")
        }
        try validateTarget(
            connectionKind: appIdentifier.connectionKind,
            options: options
        )
        switch options.target {
        case .virtualDevice:
            return try simulatorPayload(
                appId: appId,
                simulatorUDID: options.targetIdentifier,
                screenMetadata: screenMetadata
            )
        case .physicalDevice:
            return try devicePayload(
                appId: appId,
                usbMuxDeviceIdentifier: appIdentifier.deviceIdentifier,
                requestedDeviceIdentifier: options.targetIdentifier,
                screenMetadata: screenMetadata
            )
        case .automatic:
            if appIdentifier.connectionKind == "simulator" {
                return try simulatorPayload(
                    appId: appId,
                    simulatorUDID: options.targetIdentifier,
                    screenMetadata: screenMetadata
                )
            }
            if appIdentifier.connectionKind == "usb" {
                return try devicePayload(
                    appId: appId,
                    usbMuxDeviceIdentifier: appIdentifier.deviceIdentifier,
                    requestedDeviceIdentifier: options.targetIdentifier,
                    screenMetadata: screenMetadata
                )
            }
            throw CLIError.targetProviderNotFound(appId)
        }
    }

    private func simulatorPayload(
        appId: String,
        simulatorUDID: String?,
        screenMetadata: () throws -> [String: Any]
    ) throws -> [String: Any] {
        let hierarchy = try screenMetadata()
        let udid: String
        if let simulatorUDID {
            udid = simulatorUDID
        } else {
            udid = try simctl.singleBootedSimulatorUDID()
        }
        let pngData = try simctl.captureScreenshot(udid: udid)
        return try payloadBuilder.simulatorPayload(appId: appId, hierarchy: hierarchy, pngData: pngData, simulatorUDID: udid)
    }

    private func devicePayload(
        appId: String,
        usbMuxDeviceIdentifier: String,
        requestedDeviceIdentifier: String?,
        screenMetadata: () throws -> [String: Any]
    ) throws -> [String: Any] {
        let deviceIdentifier = try deviceIdentifierResolver
            .resolvePhysicalIOSDeviceIdentifier(
                usbMuxDeviceIdentifier: usbMuxDeviceIdentifier,
                requestedIdentifier: requestedDeviceIdentifier
            )
        try ensureDeviceUnlocked(deviceIdentifier)
        let hierarchy = try screenMetadata()
        let pngData = try devicectl.captureScreenshot(deviceIdentifier: deviceIdentifier)
        if try imageContentInspector.isCompletelyBlack(pngData) {
            try ensureDeviceUnlocked(deviceIdentifier)
            throw CLIError.invalidScreenshot("The physical device returned an all-black image")
        }
        return try payloadBuilder.devicePayload(appId: appId, hierarchy: hierarchy, pngData: pngData, deviceIdentifier: deviceIdentifier)
    }

    private func ensureDeviceUnlocked(_ deviceIdentifier: String) throws {
        let lockState = try deviceLockStateReader.lockState(
            deviceIdentifier: deviceIdentifier
        )
        guard !lockState.passcodeRequired else {
            throw IOSSystemScreenshotError.deviceLocked(deviceIdentifier)
        }
    }

    private func validateTarget(
        connectionKind: String,
        options: ScreenshotCaptureOptions
    ) throws {
        switch connectionKind {
        case "simulator":
            if options.target == .physicalDevice {
                throw CLIError.invalidArgument(
                    "The physical screenshot source does not match a simulator appId"
                )
            }
        case "usb":
            if options.target == .virtualDevice {
                throw CLIError.invalidArgument(
                    "The virtual screenshot source does not match a USB appId"
                )
            }
        default:
            throw CLIError.invalidArgument(
                "Unsupported iOS Runtime connection kind: \(connectionKind)"
            )
        }
    }
}

private enum IOSSystemScreenshotError:
    CLIErrorMetadataProviding,
    CustomStringConvertible {
    case deviceLocked(String)

    var description: String {
        switch self {
        case .deviceLocked(let identifier):
            return "The physical device is locked: \(identifier)"
        }
    }

    var errorCode: String {
        "device_locked"
    }

    var errorRecoverySuggestion: String {
        "Unlock the physical device, keep the screen awake, and try again"
    }
}
