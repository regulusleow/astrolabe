//
//  AstrolabeRuntimeCompatibility.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeCLI
import AstrolabeProtocol

package struct AstrolabeRuntimeCompatibility {
    /// Compatibility diagnostic suitable for direct CLI and MCP output.
    package let record: RuntimeCompatibilityRecord

    /// Host Provider capabilities supported by the Runtime.
    package let supportedProviderCapabilities: Set<RuntimeUICapability>

    /// Raw capability set declared by the Runtime handshake.
    package let runtimeCapabilities: Set<RuntimeCapability>

    /// Whether the Runtime platform matches the current Provider.
    package let isExpectedPlatform: Bool
}

package struct AstrolabeRuntimeCompatibilityPolicy {
    private let platform: RuntimeUIPlatform
    private let runtimePackageName: String
    private let requirementsByProviderCapability: [
        RuntimeUICapability: Set<RuntimeCapability>
    ] = [
        .appDiscovery: [],
        .hierarchy: [.applicationInfo, .hierarchySnapshot],
        .nodeDetail: [.applicationInfo, .hierarchySnapshot, .nodeDetail],
        .attributePatchDiscovery: [.applicationInfo, .attributePatchDiscovery],
        .attributePatching: [
            .applicationInfo,
            .hierarchySnapshot,
            .nodeDetail,
            .attributePatchDiscovery,
            .attributePatching
        ]
    ]

    package init(
        platform: RuntimeUIPlatform,
        runtimePackageName: String
    ) {
        self.platform = platform
        self.runtimePackageName = runtimePackageName
    }

    package func evaluate(
        handshake: RuntimeHandshakePayload
    ) -> AstrolabeRuntimeCompatibility {
        let runtimeCapabilities = Set(handshake.capabilities)
        let isExpectedPlatform = handshake.platform == platform.rawValue
        let requiredCapabilities = requirementsByProviderCapability.values
            .reduce(into: Set<RuntimeCapability>()) { result, requirements in
                result.formUnion(requirements)
            }
        let missingCapabilities = requiredCapabilities
            .subtracting(runtimeCapabilities)
            .map(\.rawValue)
            .sorted()
        let status: RuntimeCompatibilityStatus
        if !isExpectedPlatform {
            status = .incompatible
        } else if missingCapabilities.isEmpty {
            status = .compatible
        } else {
            status = .updateRequired
        }
        return AstrolabeRuntimeCompatibility(
            record: RuntimeCompatibilityRecord(
                status: status,
                hostVersion: AstrolabeHostMetadata.version,
                runtimeVersion: handshake.runtime.version,
                negotiatedProtocolVersion: RuntimeProtocolVersionRecord(
                    major: handshake.negotiatedProtocolVersion.major,
                    minor: handshake.negotiatedProtocolVersion.minor
                ),
                runtimeCapabilities: runtimeCapabilities.map(\.rawValue).sorted(),
                missingRuntimeCapabilities: missingCapabilities,
                recoverySuggestion: suggestion(
                    status: status,
                    runtimeVersion: handshake.runtime.version,
                    missingCapabilities: missingCapabilities
                )
            ),
            supportedProviderCapabilities: supportedProviderCapabilities(
                runtimeCapabilities: runtimeCapabilities,
                isExpectedPlatform: isExpectedPlatform
            ),
            runtimeCapabilities: runtimeCapabilities,
            isExpectedPlatform: isExpectedPlatform
        )
    }

    package func require(
        _ capability: RuntimeUICapability,
        compatibility: AstrolabeRuntimeCompatibility
    ) throws {
        guard let requirements = requirementsByProviderCapability[capability] else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "The \(platform.rawValue) Runtime Provider does not define compatibility requirements for \(capability.rawValue)"
            )
        }
        try requireRuntimeCapabilities(requirements, compatibility: compatibility)
    }

    package func requireRuntimeCapabilities(
        _ requirements: Set<RuntimeCapability>,
        compatibility: AstrolabeRuntimeCompatibility
    ) throws {
        guard compatibility.isExpectedPlatform else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "The target Runtime platform is not \(platform.rawValue)"
            )
        }
        let missingCapabilities = requirements
            .subtracting(compatibility.runtimeCapabilities)
            .map(\.rawValue)
            .sorted()
        guard missingCapabilities.isEmpty else {
            throw AstrolabeRuntimeClientError.updateRequired(
                runtimeVersion: compatibility.record.runtimeVersion,
                missingCapabilities: missingCapabilities,
                runtimePackageName: runtimePackageName
            )
        }
    }

    private func supportedProviderCapabilities(
        runtimeCapabilities: Set<RuntimeCapability>,
        isExpectedPlatform: Bool
    ) -> Set<RuntimeUICapability> {
        guard isExpectedPlatform else {
            return []
        }
        return Set(requirementsByProviderCapability.compactMap { capability, requirements in
            requirements.isSubset(of: runtimeCapabilities) ? capability : nil
        })
    }

    private func suggestion(
        status: RuntimeCompatibilityStatus,
        runtimeVersion: String,
        missingCapabilities: [String]
    ) -> String? {
        switch status {
        case .compatible:
            return nil
        case .updateRequired:
            return AstrolabeRuntimeCompatibilityMessage.updateSuggestion(
                runtimeVersion: runtimeVersion,
                missingCapabilities: missingCapabilities,
                runtimePackageName: runtimePackageName
            )
        case .incompatible:
            return "The current Runtime platform is incompatible with the \(platform.rawValue) Provider; ensure the app integrates \(runtimePackageName)"
        }
    }
}

package enum AstrolabeRuntimeCompatibilityMessage {
    package static func updateSuggestion(
        runtimeVersion: String,
        missingCapabilities: [String],
        runtimePackageName: String
    ) -> String {
        "Astrolabe Runtime \(runtimeVersion) is missing capabilities: \(missingCapabilities.joined(separator: ", ")). Update \(runtimePackageName), then rebuild and launch the app"
    }
}
