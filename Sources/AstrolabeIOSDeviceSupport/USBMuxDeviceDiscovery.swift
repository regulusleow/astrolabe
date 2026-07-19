//
//  USBMuxDeviceDiscovery.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

import AstrolabeCoreObjC
import Foundation

package struct USBMuxDeviceIdentity: Hashable {
    /// Numeric device identifier used by usbmux to establish a port connection.
    package let deviceIdentifier: String

    /// Stable serial number reported by usbmux, usually equal to the iOS UDID.
    package let serialNumber: String?

    package init(deviceIdentifier: String, serialNumber: String?) {
        self.deviceIdentifier = deviceIdentifier
        self.serialNumber = serialNumber
    }
}

package protocol USBMuxDeviceDiscovering {
    func connectedDevices() throws -> [USBMuxDeviceIdentity]
}

package struct CoreUSBMuxDeviceDiscovery: USBMuxDeviceDiscovering {
    private let discovery: ASTUSBMuxDeviceDiscovery
    private let timeout: TimeInterval

    package init(
        discovery: ASTUSBMuxDeviceDiscovery = ASTUSBMuxDeviceDiscovery(),
        timeout: TimeInterval = 1
    ) {
        self.discovery = discovery
        self.timeout = timeout
    }

    package func connectedDevices() throws -> [USBMuxDeviceIdentity] {
        try discovery.connectedDevices(withTimeout: timeout).map { device in
            USBMuxDeviceIdentity(
                deviceIdentifier: device.deviceIdentifier,
                serialNumber: device.serialNumber
            )
        }
    }
}
