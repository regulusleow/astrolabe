//
//  ADBDeviceModels.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import Foundation

package enum ADBDeviceConnectionKind: String, Equatable {
    case emulator
    case usb
    case wireless

    package static func classify(
        serial: String,
        hasUSBMetadata: Bool? = nil
    ) -> ADBDeviceConnectionKind {
        if serial.hasPrefix("emulator-") {
            return .emulator
        }
        if let hasUSBMetadata {
            return hasUSBMetadata ? .usb : .wireless
        }
        return serial.contains(":") || serial.contains("._adb-tls-connect._tcp")
            ? .wireless
            : .usb
    }
}

package enum ADBDeviceState: String, Equatable {
    case device
    case unauthorized
    case offline
    case unknown
}

package struct ADBDevice: Equatable {
    /// Stable ADB serial used to target every device-scoped command.
    package let serial: String

    /// Current ADB transport state.
    package let state: ADBDeviceState

    /// Physical or virtual connection classification.
    package let connectionKind: ADBDeviceConnectionKind

    /// Device model reported by `adb devices -l`.
    package let model: String?

    /// Product identifier reported by `adb devices -l`.
    package let product: String?

    /// Device codename reported by `adb devices -l`.
    package let deviceName: String?

    package init(
        serial: String,
        state: ADBDeviceState,
        connectionKind: ADBDeviceConnectionKind,
        model: String?,
        product: String?,
        deviceName: String?
    ) {
        self.serial = serial
        self.state = state
        self.connectionKind = connectionKind
        self.model = model
        self.product = product
        self.deviceName = deviceName
    }
}

package struct ADBDeviceListSnapshot: Equatable {
    /// Devices ready to execute ADB commands.
    package let readyDevices: [ADBDevice]

    /// Devices visible to ADB but unavailable for inspection.
    package let unavailableDevices: [ADBDevice]
}

package struct ADBDeviceListParser {
    package init() {}

    package func parse(_ output: String) -> ADBDeviceListSnapshot {
        let devices = output
            .split(whereSeparator: \Character.isNewline)
            .compactMap(parseDevice)
        return ADBDeviceListSnapshot(
            readyDevices: devices.filter { $0.state == .device },
            unavailableDevices: devices.filter { $0.state != .device }
        )
    }

    private func parseDevice(_ line: Substring) -> ADBDevice? {
        let fields = line.split(whereSeparator: \Character.isWhitespace)
        guard fields.count >= 2, fields[0] != "List" else {
            return nil
        }
        let serial = String(fields[0])
        let state = ADBDeviceState(rawValue: String(fields[1])) ?? .unknown
        let metadata = fields.dropFirst(2).reduce(into: [String: String]()) {
            result, field in
                let components = field.split(separator: ":", maxSplits: 1)
                guard components.count == 2 else {
                    return
                }
                result[String(components[0])] = String(components[1])
            }
        return ADBDevice(
            serial: serial,
            state: state,
            connectionKind: ADBDeviceConnectionKind.classify(
                serial: serial,
                hasUSBMetadata: metadata["usb"] != nil
            ),
            model: metadata["model"],
            product: metadata["product"],
            deviceName: metadata["device"]
        )
    }

}
