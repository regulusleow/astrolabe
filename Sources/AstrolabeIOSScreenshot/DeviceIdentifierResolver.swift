//
//  DeviceIdentifierResolver.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeCLI
import AstrolabeIOSDeviceSupport
import Foundation

protocol CommandRunning {
    func run(_ executable: String, arguments: [String]) throws -> Data
}

struct ProcessCommandRunner: CommandRunning {
    func run(_ executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outputURL = temporaryOutputURL(suffix: "stdout")
        let errorURL = temporaryOutputURL(suffix: "stderr")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        _ = FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        var outputHandleClosed = false
        var errorHandleClosed = false
        defer {
            if !outputHandleClosed {
                try? outputHandle.close()
            }
            if !errorHandleClosed {
                try? errorHandle.close()
            }
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        process.standardOutput = outputHandle
        process.standardError = errorHandle
        try process.run()
        process.waitUntilExit()
        try outputHandle.close()
        outputHandleClosed = true
        try errorHandle.close()
        errorHandleClosed = true

        let output = try Data(contentsOf: outputURL)
        if process.terminationStatus == 0 {
            return output
        }

        let errorData = try Data(contentsOf: errorURL)
        let errorText = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let detail: String
        if let errorText, !errorText.isEmpty {
            detail = errorText
        } else {
            detail = "\(executable) exit code \(process.terminationStatus)"
        }
        throw CLIError.commandFailed(detail)
    }

    private func temporaryOutputURL(suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("astrolabe-command-\(UUID().uuidString)-\(suffix)")
            .appendingPathExtension("log")
    }
}

protocol DeviceIdentifierResolving {
    func resolvePhysicalIOSDeviceIdentifier(
        usbMuxDeviceIdentifier: String,
        requestedIdentifier: String?
    ) throws -> String
}

struct DevicectlDeviceIdentifierResolver: DeviceIdentifierResolving {
    private let commandRunner: CommandRunning
    private let usbMuxDeviceDiscovery: any USBMuxDeviceDiscovering

    init(
        commandRunner: CommandRunning = ProcessCommandRunner(),
        usbMuxDeviceDiscovery: any USBMuxDeviceDiscovering =
            CoreUSBMuxDeviceDiscovery()
    ) {
        self.commandRunner = commandRunner
        self.usbMuxDeviceDiscovery = usbMuxDeviceDiscovery
    }

    func resolvePhysicalIOSDeviceIdentifier(
        usbMuxDeviceIdentifier: String,
        requestedIdentifier: String?
    ) throws -> String {
        let usbMuxDevices = try usbMuxDeviceDiscovery.connectedDevices()
        guard let usbMuxDevice = usbMuxDevices.first(where: {
            $0.deviceIdentifier == usbMuxDeviceIdentifier
        }) else {
            throw CLIError.invalidScreenshot(
                "No usbmux device matches appId: \(usbMuxDeviceIdentifier)"
            )
        }
        guard let serialNumber = usbMuxDevice.serialNumber,
              !serialNumber.isEmpty else {
            throw CLIError.invalidScreenshot(
                "The USB Runtime device has no serial number for binding a system screenshot"
            )
        }
        let devices = try physicalIOSDevices()
        guard let device = devices.first(where: {
            $0.udid.caseInsensitiveCompare(serialNumber) == .orderedSame
        }) else {
            throw CLIError.invalidScreenshot(
                "devicectl did not find the physical device for the USB Runtime: \(serialNumber)"
            )
        }
        if let requestedIdentifier {
            guard device.matches(requestedIdentifier) else {
                throw CLIError.invalidArgument(
                "--target-id does not match the physical device running the USB Runtime"
                )
            }
            return requestedIdentifier
        }
        return device.udid
    }

    private func physicalIOSDevices() throws -> [DevicectlPhysicalIOSDevice] {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("astrolabe-devices-\(UUID().uuidString)")
            .appendingPathExtension("json")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        _ = try commandRunner.run("/usr/bin/xcrun", arguments: [
            "devicectl",
            "list",
            "devices",
            "--json-output",
            outputURL.path,
            "--quiet"
        ])

        let data = try Data(contentsOf: outputURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let devices = result["devices"] as? [[String: Any]] else {
            throw CLIError.invalidJSONObject
        }

        return devices.compactMap(physicalIOSDevice(_:))
    }

    private func physicalIOSDevice(
        _ device: [String: Any]
    ) -> DevicectlPhysicalIOSDevice? {
        guard let hardware = device["hardwareProperties"] as? [String: Any],
              let connection = device["connectionProperties"] as? [String: Any],
              let properties = device["deviceProperties"] as? [String: Any],
              hardware["reality"] as? String == "physical",
              hardware["platform"] as? String == "iOS",
              connection["transportType"] as? String == "wired",
              let udid = hardware["udid"] as? String,
              !udid.isEmpty else {
            return nil
        }
        return DevicectlPhysicalIOSDevice(
            identifier: device["identifier"] as? String,
            udid: udid,
            name: properties["name"] as? String
        )
    }
}

private struct DevicectlPhysicalIOSDevice {
    /// CoreDevice session device identifier.
    let identifier: String?

    /// iOS UDID corresponding to the usbmux SerialNumber.
    let udid: String

    /// Device display name accepted by devicectl.
    let name: String?

    func matches(_ candidate: String) -> Bool {
        [identifier, udid, name]
            .compactMap { $0 }
            .contains { value in
                value.caseInsensitiveCompare(candidate) == .orderedSame
            }
    }
}
