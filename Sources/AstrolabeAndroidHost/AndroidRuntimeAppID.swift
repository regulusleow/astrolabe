//
//  AndroidRuntimeAppID.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeRuntimeHostCore
import Foundation

package struct AndroidRuntimeAppID: Equatable, Hashable {
    /// ADB serial used to address the Android device.
    package let deviceSerial: String

    /// Android process identifier owning the Runtime socket.
    package let processIdentifier: Int

    /// Android application identifier reported by the Runtime.
    package let applicationIdentifier: String

    /// Opaque Runtime process instance identifier.
    package let runtimeInstanceIdentifier: String

    package var rawValue: String {
        [
            "android",
            Self.encode(deviceSerial),
            String(processIdentifier),
            Self.encode(applicationIdentifier),
            Self.encode(runtimeInstanceIdentifier)
        ].joined(separator: ":")
    }

    package init(
        deviceSerial: String,
        processIdentifier: Int,
        applicationIdentifier: String,
        runtimeInstanceIdentifier: String
    ) {
        self.deviceSerial = deviceSerial
        self.processIdentifier = processIdentifier
        self.applicationIdentifier = applicationIdentifier
        self.runtimeInstanceIdentifier = runtimeInstanceIdentifier
    }

    package init(rawValue: String) throws {
        let components = rawValue.split(
            separator: ":",
            maxSplits: 4,
            omittingEmptySubsequences: false
        )
        guard components.count == 5,
              components[0] == "android",
              let deviceSerial = Self.decode(String(components[1])),
              !deviceSerial.isEmpty,
              let processIdentifier = Int(components[2]),
              processIdentifier > 0,
              let applicationIdentifier = Self.decode(String(components[3])),
              !applicationIdentifier.isEmpty,
              let runtimeInstanceIdentifier = Self.decode(String(components[4])),
              !runtimeInstanceIdentifier.isEmpty else {
            throw AstrolabeRuntimeClientError.invalidAppID(rawValue)
        }
        self.deviceSerial = deviceSerial
        self.processIdentifier = processIdentifier
        self.applicationIdentifier = applicationIdentifier
        self.runtimeInstanceIdentifier = runtimeInstanceIdentifier
    }

    private static func encode(_ value: String) -> String {
        value.utf8.map { byte in
            if isUnreserved(byte) {
                return String(UnicodeScalar(byte))
            }
            return String(format: "%%%02X", byte)
        }.joined()
    }

    private static func decode(_ value: String) -> String? {
        let bytes = Array(value.utf8)
        var result = [UInt8]()
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x25 {
                guard index + 2 < bytes.count,
                      let high = hexadecimal(bytes[index + 1]),
                      let low = hexadecimal(bytes[index + 2]) else {
                    return nil
                }
                result.append((high << 4) | low)
                index += 3
            } else {
                guard isUnreserved(bytes[index]) else {
                    return nil
                }
                result.append(bytes[index])
                index += 1
            }
        }
        return String(bytes: result, encoding: .utf8)
    }

    private static func isUnreserved(_ byte: UInt8) -> Bool {
        (0x41...0x5A).contains(byte)
            || (0x61...0x7A).contains(byte)
            || (0x30...0x39).contains(byte)
            || [0x2D, 0x2E, 0x5F, 0x7E].contains(byte)
    }

    private static func hexadecimal(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39:
            return byte - 0x30
        case 0x41...0x46:
            return byte - 0x41 + 10
        case 0x61...0x66:
            return byte - 0x61 + 10
        default:
            return nil
        }
    }
}
