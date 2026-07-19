//
//  SimulatorScreenshotCapturer.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeCLI
import Foundation

protocol SimulatorScreenshotCapturing {
    func singleBootedSimulatorUDID() throws -> String
    func captureScreenshot(udid: String) throws -> Data
}

struct SimctlScreenshotCapturer: SimulatorScreenshotCapturing {
    private let commandRunner: CommandRunning

    init(commandRunner: CommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
    }

    func singleBootedSimulatorUDID() throws -> String {
        let data = try commandRunner.run("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "booted", "-j"])
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesByRuntime = json["devices"] as? [String: Any] else {
            throw CLIError.invalidJSONObject
        }

        let bootedDevices = devicesByRuntime.values
            .compactMap { $0 as? [[String: Any]] }
            .flatMap { $0 }
            .filter { ($0["state"] as? String) == "Booted" }
        if bootedDevices.count == 1, let udid = bootedDevices.first?["udid"] as? String, !udid.isEmpty {
            return udid
        }
        if bootedDevices.isEmpty {
            throw CLIError.missingArgument("a booted simulator")
        }
            throw CLIError.missingArgument("--target-id when multiple simulators are booted")
    }

    func captureScreenshot(udid: String) throws -> Data {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("astrolabe-\(UUID().uuidString)")
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        _ = try commandRunner.run("/usr/bin/xcrun", arguments: ["simctl", "io", udid, "screenshot", outputURL.path])
        return try Data(contentsOf: outputURL)
    }
}
