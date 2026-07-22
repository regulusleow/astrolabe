//
//  AstrolabeRuntimeEndpoint.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import Foundation

package struct AstrolabeRuntimeEndpoint: Hashable {
    /// Runtime transport classification used for diagnostics and transport selection.
    package let connectionKind: String

    /// Platform device identifier associated with the endpoint.
    package let deviceId: String

    /// Hostname used by the Host transport.
    package let host: String

    /// TCP or platform-forwarded port used by the Host transport.
    package let port: UInt16

    package init(
        connectionKind: String,
        deviceId: String,
        host: String,
        port: UInt16
    ) {
        self.connectionKind = connectionKind
        self.deviceId = deviceId
        self.host = host
        self.port = port
    }
}

package struct AstrolabeRuntimeSessionTarget: Hashable {
    /// Opaque Host app identifier exposed to CLI and MCP clients.
    package let appID: String

    /// Runtime process instance expected by the Host.
    package let runtimeInstanceIdentifier: String

    /// Connection endpoint bound to the Runtime process.
    package let endpoint: AstrolabeRuntimeEndpoint

    package init(
        appID: String,
        runtimeInstanceIdentifier: String,
        endpoint: AstrolabeRuntimeEndpoint
    ) {
        self.appID = appID
        self.runtimeInstanceIdentifier = runtimeInstanceIdentifier
        self.endpoint = endpoint
    }
}
