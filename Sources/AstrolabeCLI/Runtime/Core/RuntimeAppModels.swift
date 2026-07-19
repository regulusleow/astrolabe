//
//  RuntimeAppModels.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

package struct RuntimeAppDiscoveryDiagnostic: Encodable {
    /// Identifier of the Runtime UI Provider that produced the diagnostic.
    let providerIdentifier: String

    /// Runtime platform of the endpoint.
    let platform: RuntimeUIPlatform

    /// Endpoint connection type, such as simulator or usb.
    let connectionKind: String

    /// Device identifier associated with the endpoint.
    let deviceId: String

    /// Runtime port the Host attempted to connect to.
    let endpointPort: Int

    /// Stable machine-readable error code.
    let errorCode: String

    /// Error description suitable for direct user output.
    let message: String

    /// Suggested action for resolving the connection problem.
    let recoverySuggestion: String

    package init(
        providerIdentifier: String,
        platform: RuntimeUIPlatform,
        connectionKind: String,
        deviceId: String,
        endpointPort: Int,
        errorCode: String,
        message: String,
        recoverySuggestion: String
    ) {
        self.providerIdentifier = providerIdentifier
        self.platform = platform
        self.connectionKind = connectionKind
        self.deviceId = deviceId
        self.endpointPort = endpointPort
        self.errorCode = errorCode
        self.message = message
        self.recoverySuggestion = recoverySuggestion
    }
}

package enum RuntimeCompatibilityStatus: String, Encodable, Equatable {
    case compatible
    case updateRequired
    case incompatible
}

package struct RuntimeProtocolVersionRecord: Encodable {
    /// Protocol major version; a change indicates an incompatible protocol revision.
    let major: UInt16

    /// Protocol minor version; a change indicates backward-compatible capabilities were added.
    let minor: UInt16

    package init(major: UInt16, minor: UInt16) {
        self.major = major
        self.minor = minor
    }
}

package struct RuntimeCompatibilityRecord: Encodable {
    /// Host compatibility assessment for the current Runtime.
    let status: RuntimeCompatibilityStatus

    /// Current Astrolabe Host version.
    let hostVersion: String

    /// Runtime SDK version integrated into the app.
    package let runtimeVersion: String

    /// Protocol version negotiated by the Host and Runtime handshake.
    let negotiatedProtocolVersion: RuntimeProtocolVersionRecord

    /// Raw capabilities declared by the Runtime handshake.
    let runtimeCapabilities: [String]

    /// Capabilities required by the current Host but not provided by the Runtime.
    let missingRuntimeCapabilities: [String]

    /// Recovery suggestion when the Runtime is incompatible or requires an upgrade.
    let recoverySuggestion: String?

    package init(
        status: RuntimeCompatibilityStatus,
        hostVersion: String,
        runtimeVersion: String,
        negotiatedProtocolVersion: RuntimeProtocolVersionRecord,
        runtimeCapabilities: [String],
        missingRuntimeCapabilities: [String],
        recoverySuggestion: String?
    ) {
        self.status = status
        self.hostVersion = hostVersion
        self.runtimeVersion = runtimeVersion
        self.negotiatedProtocolVersion = negotiatedProtocolVersion
        self.runtimeCapabilities = runtimeCapabilities
        self.missingRuntimeCapabilities = missingRuntimeCapabilities
        self.recoverySuggestion = recoverySuggestion
    }
}

package struct InspectableAppRecord: Encodable {
    /// Session-scoped app connection handle that must not be persisted.
    let appId: String

    /// Runtime platform of the app.
    let platform: RuntimeUIPlatform

    /// Identifier of the Runtime UI Provider that discovered and inspects the app.
    let providerIdentifier: String

    /// Runtime UI capabilities provided for the app by the current Provider.
    let capabilities: [RuntimeUICapability]

    /// App display name.
    let displayName: String

    /// Platform application identifier: bundle identifier on iOS or application ID on Android.
    let applicationIdentifier: String

    /// Device display name.
    let deviceName: String

    /// Protocol version of the in-app Runtime UI Provider.
    let providerVersion: String

    /// Connection type used by the Provider, such as simulator, usb, emulator, or adb.
    let connectionKind: String

    /// Device identifier used by the Provider.
    let deviceId: String

    /// Port used by the Host to connect to the in-app Runtime UI Provider.
    let endpointPort: Int

    /// Short-lived process identifier used to detect app restarts or process replacement.
    let processIdentifier: String

    /// Runtime compatibility diagnostic returned when the Provider completes the handshake.
    let compatibility: RuntimeCompatibilityRecord?

    package init(
        appId: String,
        platform: RuntimeUIPlatform,
        providerIdentifier: String,
        capabilities: [RuntimeUICapability],
        displayName: String,
        applicationIdentifier: String,
        deviceName: String,
        providerVersion: String,
        connectionKind: String,
        deviceId: String,
        endpointPort: Int,
        processIdentifier: String,
        compatibility: RuntimeCompatibilityRecord? = nil
    ) {
        self.appId = appId
        self.platform = platform
        self.providerIdentifier = providerIdentifier
        self.capabilities = capabilities
        self.displayName = displayName
        self.applicationIdentifier = applicationIdentifier
        self.deviceName = deviceName
        self.providerVersion = providerVersion
        self.connectionKind = connectionKind
        self.deviceId = deviceId
        self.endpointPort = endpointPort
        self.processIdentifier = processIdentifier
        self.compatibility = compatibility
    }
}
