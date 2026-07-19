//
//  DeviceScreenshotCapturer.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeCLI
import Foundation

protocol DeviceScreenshotCapturing {
    func captureScreenshot(deviceIdentifier: String) throws -> Data
}

struct DeviceLockState {
    /// Whether the current device requires a passcode before screen content can be accessed.
    let passcodeRequired: Bool
}

protocol DeviceLockStateReading {
    func lockState(deviceIdentifier: String) throws -> DeviceLockState
}

struct DevicectlDeviceLockStateReader: DeviceLockStateReading {
    private let commandRunner: CommandRunning

    init(commandRunner: CommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func lockState(deviceIdentifier: String) throws -> DeviceLockState {
        let data = try commandRunner.run("/usr/bin/xcrun", arguments: [
            "devicectl",
            "device",
            "info",
            "lockState",
            "--device",
            deviceIdentifier,
            "--json-output",
            "-",
            "--quiet"
        ])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let passcodeRequired = result["passcodeRequired"] as? Bool else {
            throw CLIError.invalidJSONObject
        }
        return DeviceLockState(passcodeRequired: passcodeRequired)
    }
}

struct DevicectlScreenshotCapturer: DeviceScreenshotCapturing {
    private let commandRunner: CommandRunning

    init(commandRunner: CommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func captureScreenshot(deviceIdentifier: String) throws -> Data {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("astrolabe-\(UUID().uuidString)")
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        _ = try commandRunner.run("/usr/bin/xcrun", arguments: [
            "devicectl",
            "device",
            "capture",
            "screenshot",
            "--quiet",
            "--device",
            deviceIdentifier,
            "--destination",
            outputURL.path
        ])
        return try Data(contentsOf: outputURL)
    }
}
