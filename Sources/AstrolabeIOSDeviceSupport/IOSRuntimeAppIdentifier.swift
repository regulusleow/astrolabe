//
//  IOSRuntimeAppIdentifier.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

import Foundation

package struct IOSRuntimeAppIdentifier: Hashable {
    package static let marker = "astrolabe"

    /// Runtime connection type, such as simulator or usb.
    package let connectionKind: String

    /// Identifier of the device hosting the Runtime.
    package let deviceIdentifier: String

    /// Runtime listening port.
    package let port: UInt16

    /// Opaque identifier of the Runtime process instance.
    package let runtimeInstanceIdentifier: String

    package var rawValue: String {
        [
            connectionKind,
            deviceIdentifier,
            String(port),
            encodedRuntimeInstanceIdentifier,
            Self.marker
        ].joined(separator: ":")
    }

    package init(
        connectionKind: String,
        deviceIdentifier: String,
        port: UInt16,
        runtimeInstanceIdentifier: String
    ) {
        self.connectionKind = connectionKind
        self.deviceIdentifier = deviceIdentifier
        self.port = port
        self.runtimeInstanceIdentifier = runtimeInstanceIdentifier
    }

    package init?(rawValue: String) {
        let components = rawValue.split(
            separator: ":",
            omittingEmptySubsequences: false
        )
        guard components.count == 5,
              components[4] == Substring(Self.marker),
              let port = UInt16(components[2]),
              port > 0,
              let runtimeInstanceIdentifier = Self.decodeRuntimeInstanceIdentifier(String(components[3])),
              !runtimeInstanceIdentifier.isEmpty,
              components[0] == "simulator" || components[0] == "usb",
              !components[1].isEmpty else {
            return nil
        }
        connectionKind = String(components[0])
        deviceIdentifier = String(components[1])
        self.port = port
        self.runtimeInstanceIdentifier = runtimeInstanceIdentifier
    }

    private var encodedRuntimeInstanceIdentifier: String {
        Data(runtimeInstanceIdentifier.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decodeRuntimeInstanceIdentifier(_ value: String) -> String? {
        let normalized = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        guard let data = Data(base64Encoded: normalized + padding) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
