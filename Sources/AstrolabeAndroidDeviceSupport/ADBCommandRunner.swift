//
//  ADBCommandRunner.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import Foundation

package struct ADBCommandResult: Equatable {
    /// Raw standard output bytes, including binary screenshot data.
    package let standardOutput: Data

    /// Raw standard error bytes returned by ADB.
    package let standardError: Data

    /// Process exit status returned by ADB.
    package let exitCode: Int32

    package init(
        standardOutput: Data,
        standardError: Data,
        exitCode: Int32
    ) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exitCode = exitCode
    }
}

package protocol ADBCommandRunning {
    func run(arguments: [String]) throws -> ADBCommandResult
}

package struct ProcessADBCommandRunner: ADBCommandRunning {
    package init() {}

    package func run(arguments: [String]) throws -> ADBCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["adb"] + arguments

        let outputURL = temporaryURL(suffix: "stdout")
        let errorURL = temporaryURL(suffix: "stderr")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        process.standardOutput = outputHandle
        process.standardError = errorHandle
        try process.run()
        process.waitUntilExit()
        try outputHandle.close()
        try errorHandle.close()

        return ADBCommandResult(
            standardOutput: try Data(contentsOf: outputURL),
            standardError: try Data(contentsOf: errorURL),
            exitCode: process.terminationStatus
        )
    }

    private func temporaryURL(suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("astrolabe-adb-\(UUID().uuidString)-\(suffix)")
    }
}

package struct ADBCommandFailure: Error, CustomStringConvertible {
    /// ADB arguments used by the failed command.
    package let arguments: [String]

    /// Exit status returned by ADB.
    package let exitCode: Int32

    /// Human-readable standard error returned by ADB.
    package let standardError: String

    package var description: String {
        if !standardError.isEmpty {
            return standardError
        }
        return "adb \(arguments.joined(separator: " ")) exited with code \(exitCode)"
    }
}
