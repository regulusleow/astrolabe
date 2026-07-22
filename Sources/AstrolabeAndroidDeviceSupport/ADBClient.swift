//
//  ADBClient.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import Foundation

package final class ADBClient {
    private let commandRunner: any ADBCommandRunning
    private let deviceParser: ADBDeviceListParser
    private let unixSocketParser: ADBUnixSocketListParser

    package init(
        commandRunner: any ADBCommandRunning = ProcessADBCommandRunner(),
        deviceParser: ADBDeviceListParser = ADBDeviceListParser(),
        unixSocketParser: ADBUnixSocketListParser = ADBUnixSocketListParser()
    ) {
        self.commandRunner = commandRunner
        self.deviceParser = deviceParser
        self.unixSocketParser = unixSocketParser
    }

    package func devices() throws -> ADBDeviceListSnapshot {
        let result = try checked(arguments: ["devices", "-l"])
        return deviceParser.parse(try text(from: result.standardOutput))
    }

    package func abstractSocketNames(deviceSerial: String) throws -> [String] {
        let output = try shellOutput(
            deviceSerial: deviceSerial,
            arguments: ["cat", "/proc/net/unix"]
        )
        return unixSocketParser.abstractSocketNames(from: output)
    }

    package func forward(
        deviceSerial: String,
        socketName: String
    ) throws -> UInt16 {
        let result = try checked(arguments: target(deviceSerial) + [
            "forward", "tcp:0", "localabstract:\(socketName)"
        ])
        let value = try text(from: result.standardOutput)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let port = UInt16(value), port > 0 else {
            throw ADBCommandFailure(
                arguments: ["forward", "tcp:0", "localabstract:\(socketName)"],
                exitCode: result.exitCode,
                standardError: "ADB returned an invalid local forward port: \(value)"
            )
        }
        return port
    }

    package func removeForward(
        deviceSerial: String,
        localPort: UInt16
    ) throws {
        _ = try checked(arguments: target(deviceSerial) + [
            "forward", "--remove", "tcp:\(localPort)"
        ])
    }

    package func captureScreenshot(deviceSerial: String) throws -> Data {
        try checked(arguments: target(deviceSerial) + [
            "exec-out", "screencap", "-p"
        ]).standardOutput
    }

    package func shellOutput(
        deviceSerial: String,
        arguments: [String]
    ) throws -> String {
        let result = try checked(arguments: target(deviceSerial) + ["shell"] + arguments)
        return try text(from: result.standardOutput)
    }

    private func target(_ serial: String) -> [String] {
        ["-s", serial]
    }

    private func checked(arguments: [String]) throws -> ADBCommandResult {
        let result = try commandRunner.run(arguments: arguments)
        guard result.exitCode == 0 else {
            throw ADBCommandFailure(
                arguments: arguments,
                exitCode: result.exitCode,
                standardError: String(data: result.standardError, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        }
        return result
    }

    private func text(from data: Data) throws -> String {
        guard let value = String(data: data, encoding: .utf8) else {
            throw ADBCommandFailure(
                arguments: [],
                exitCode: 0,
                standardError: "ADB returned non-UTF-8 command output"
            )
        }
        return value
    }
}
