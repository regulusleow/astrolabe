//
//  ADBForwardLease.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import Foundation

package final class ADBForwardLease {
    /// Local TCP port allocated by ADB.
    package let localPort: UInt16

    /// ADB serial owning the forward.
    package let deviceSerial: String

    /// Device abstract socket targeted by the forward.
    package let socketName: String

    private let client: ADBClient
    private let lock = NSLock()
    private var isClosed = false

    private init(
        client: ADBClient,
        deviceSerial: String,
        socketName: String,
        localPort: UInt16
    ) {
        self.client = client
        self.deviceSerial = deviceSerial
        self.socketName = socketName
        self.localPort = localPort
    }

    deinit {
        close()
    }

    package static func open(
        client: ADBClient,
        deviceSerial: String,
        socketName: String
    ) throws -> ADBForwardLease {
        ADBForwardLease(
            client: client,
            deviceSerial: deviceSerial,
            socketName: socketName,
            localPort: try client.forward(
                deviceSerial: deviceSerial,
                socketName: socketName
            )
        )
    }

    package func close() {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        isClosed = true
        lock.unlock()
        try? client.removeForward(
            deviceSerial: deviceSerial,
            localPort: localPort
        )
    }
}
