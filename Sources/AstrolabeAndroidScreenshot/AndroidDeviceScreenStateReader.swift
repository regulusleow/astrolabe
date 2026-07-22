//
//  AndroidDeviceScreenStateReader.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeAndroidDeviceSupport
import Foundation

struct AndroidDeviceScreenState {
    /// Application identifier owning the top resumed Activity, when available.
    let foregroundApplicationIdentifier: String?

    /// Whether Android reports an active keyguard or lock screen.
    let locked: Bool
}

protocol AndroidDeviceScreenStateReading {
    func read(deviceSerial: String) throws -> AndroidDeviceScreenState
}

struct AndroidDeviceScreenStateReader: AndroidDeviceScreenStateReading {
    private let adbClient: ADBClient

    init(adbClient: ADBClient) {
        self.adbClient = adbClient
    }

    func read(deviceSerial: String) throws -> AndroidDeviceScreenState {
        let activities = try adbClient.shellOutput(
            deviceSerial: deviceSerial,
            arguments: ["dumpsys", "activity", "activities"]
        )
        let policy = try adbClient.shellOutput(
            deviceSerial: deviceSerial,
            arguments: ["dumpsys", "window", "policy"]
        )
        return AndroidDeviceScreenState(
            foregroundApplicationIdentifier: resumedApplicationIdentifier(
                from: activities
            ),
            locked: [
                "isStatusBarKeyguard=true",
                "mShowingLockscreen=true",
                "mDreamingLockscreen=true"
            ].contains { policy.contains($0) }
        )
    }

    private func resumedApplicationIdentifier(from output: String) -> String? {
        guard let line = output
            .split(whereSeparator: \Character.isNewline)
            .first(where: { $0.contains("topResumedActivity=") }) else {
            return nil
        }
        return line
            .split(whereSeparator: \Character.isWhitespace)
            .first(where: { $0.contains("/") })
            .flatMap { token -> String? in
                guard let separator = token.firstIndex(of: "/") else {
                    return nil
                }
                let value = token[..<separator]
                guard !value.isEmpty else {
                    return nil
                }
                return String(value)
            }
    }
}
