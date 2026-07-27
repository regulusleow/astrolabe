//
//  AndroidSystemScreenshotProvider.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeAndroidDeviceSupport
import AstrolabeAndroidHost
import AstrolabeCLI
import AstrolabeScreenshotSupport
import Foundation

package struct AndroidSystemScreenshotProvider: PlatformScreenshotProviding {
    private let adbClient: ADBClient
    private let screenStateReader: any AndroidDeviceScreenStateReading
    private let imageContentInspector: any ScreenshotImageContentInspecting
    private let payloadBuilder: any SystemScreenshotPayloadBuilding

    package init() {
        let adbClient = ADBClient()
        self.init(
            adbClient: adbClient,
            screenStateReader: AndroidDeviceScreenStateReader(adbClient: adbClient),
            imageContentInspector: ScreenshotImageContentInspector(),
            payloadBuilder: SystemScreenshotPayloadBuilder()
        )
    }

    init(
        adbClient: ADBClient,
        screenStateReader: (any AndroidDeviceScreenStateReading)? = nil,
        imageContentInspector: any ScreenshotImageContentInspecting =
            ScreenshotImageContentInspector(),
        payloadBuilder: any SystemScreenshotPayloadBuilding =
            SystemScreenshotPayloadBuilder()
    ) {
        self.adbClient = adbClient
        self.screenStateReader = screenStateReader
            ?? AndroidDeviceScreenStateReader(adbClient: adbClient)
        self.imageContentInspector = imageContentInspector
        self.payloadBuilder = payloadBuilder
    }

    package func capture(
        appId: String,
        options: ScreenshotCaptureOptions,
        screenMetadata: () throws -> [String: Any]
    ) throws -> [String: Any] {
        let appID = try AndroidRuntimeAppID(rawValue: appId)
        try validateTarget(appID: appID, options: options)
        let screenState = try screenStateReader.read(
            deviceSerial: appID.deviceSerial
        )
        guard !screenState.locked else {
            throw AndroidScreenshotError.deviceLocked(appID.deviceSerial)
        }
        guard let foregroundApplicationIdentifier =
            screenState.foregroundApplicationIdentifier else {
            throw AndroidScreenshotError.foregroundAppUnavailable
        }
        if foregroundApplicationIdentifier != appID.applicationIdentifier {
            throw AndroidScreenshotError.targetNotForeground(
                expected: appID.applicationIdentifier,
                actual: foregroundApplicationIdentifier
            )
        }
        let hierarchy = try screenMetadata()
        let pngData = try adbClient.captureScreenshot(
            deviceSerial: appID.deviceSerial
        )
        guard pngData.starts(with: [
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A
        ]) else {
            throw AndroidScreenshotError.invalidPNG
        }
        guard try !imageContentInspector.isCompletelyBlack(pngData) else {
            throw AndroidScreenshotError.secureWindow
        }
        return try payloadBuilder.payload(
            appId: appId,
            hierarchy: hierarchy,
            pngData: pngData,
            source: "adb",
            sourceMetadata: [
                "deviceSerial": appID.deviceSerial,
                "connectionKind": ADBDeviceConnectionKind.classify(
                    serial: appID.deviceSerial
                ).rawValue
            ]
        )
    }

    private func validateTarget(
        appID: AndroidRuntimeAppID,
        options: ScreenshotCaptureOptions
    ) throws {
        if let targetIdentifier = options.targetIdentifier,
           targetIdentifier != appID.deviceSerial {
            throw CLIError.invalidArgument(
                "--target-id does not match the Android device running the Runtime"
            )
        }
        let isEmulator = appID.deviceSerial.hasPrefix("emulator-")
        switch options.target {
        case .automatic:
            return
        case .virtualDevice:
            guard isEmulator else {
                throw CLIError.invalidArgument(
                    "The virtual screenshot source does not match a physical Android appId"
                )
            }
        case .physicalDevice:
            guard !isEmulator else {
                throw CLIError.invalidArgument(
                    "The physical screenshot source does not match an Android emulator appId"
                )
            }
        }
    }
}

private enum AndroidScreenshotError:
    CLIErrorMetadataProviding,
    CustomStringConvertible {
    case deviceLocked(String)
    case foregroundAppUnavailable
    case targetNotForeground(expected: String, actual: String)
    case secureWindow
    case invalidPNG

    var description: String {
        switch self {
        case let .deviceLocked(serial):
            return "The Android device is locked: \(serial)"
        case .foregroundAppUnavailable:
            return "Android did not report a focused application window"
        case let .targetNotForeground(expected, actual):
            return "The target app is not foreground; expected \(expected), found \(actual)"
        case .secureWindow:
            return "Android returned an all-black screenshot for the foreground app"
        case .invalidPNG:
            return "ADB screencap did not return valid PNG data"
        }
    }

    var errorCode: String {
        switch self {
        case .deviceLocked:
            return "android_device_locked"
        case .foregroundAppUnavailable:
            return "android_foreground_app_unavailable"
        case .targetNotForeground:
            return "android_target_not_foreground"
        case .secureWindow:
            return "android_secure_window_capture_blocked"
        case .invalidPNG:
            return "android_screenshot_invalid_png"
        }
    }

    var errorRecoverySuggestion: String {
        switch self {
        case .deviceLocked:
            return "Unlock the Android device, keep the screen awake, and try again"
        case .foregroundAppUnavailable:
            return "Bring the target app to the foreground, wait for its window to focus, and try again"
        case .targetNotForeground:
            return "Bring the target app to the foreground and capture again"
        case .secureWindow:
            return "Disable FLAG_SECURE for the debug screen or capture a non-secure window"
        case .invalidPNG:
            return "Verify adb exec-out screencap works for the selected device"
        }
    }
}
