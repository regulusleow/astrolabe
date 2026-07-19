//
//  AstrolabeRuntimeCompatibility.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/11.
//

import AstrolabeCLI
import AstrolabeProtocol

enum AstrolabeRuntimeCompatibilityMessage {
    static func updateSuggestion(
        runtimeVersion: String,
        missingCapabilities: [String]
    ) -> String {
        "Astrolabe Runtime \(runtimeVersion) is missing capabilities: \(missingCapabilities.joined(separator: ", ")). Update astrolabe-runtime-ios, then rebuild and launch the app"
    }
}

struct AstrolabeRuntimeCompatibility {
    /// Compatibility diagnostic suitable for direct CLI and MCP output.
    let record: RuntimeCompatibilityRecord

    /// Host Provider capabilities actually supported by the current Runtime.
    let supportedProviderCapabilities: Set<RuntimeUICapability>

    /// Raw capability set declared by the Runtime handshake.
    let runtimeCapabilities: Set<RuntimeCapability>

    /// Whether the Runtime runs on the platform owned by the current Provider.
    let isExpectedPlatform: Bool
}

struct AstrolabeRuntimeCompatibilityPolicy {
    private let expectedPlatform = "ios"
    private let requirementsByProviderCapability: [
        RuntimeUICapability: Set<RuntimeCapability>
    ] = [
        .appDiscovery: [],
        .hierarchy: [.applicationInfo, .hierarchySnapshot],
        .nodeDetail: [.applicationInfo, .hierarchySnapshot, .nodeDetail],
        .attributePatchDiscovery: [
            .applicationInfo,
            .attributePatchDiscovery
        ],
        .attributePatching: [
            .applicationInfo,
            .hierarchySnapshot,
            .nodeDetail,
            .attributePatchDiscovery,
            .attributePatching
        ]
    ]

    func evaluate(
        handshake: RuntimeHandshakePayload
    ) -> AstrolabeRuntimeCompatibility {
        let runtimeCapabilities = Set(handshake.capabilities)
        let isExpectedPlatform = handshake.platform == expectedPlatform
        let fullySupportedCapabilities = requirementsByProviderCapability.values
            .reduce(into: Set<RuntimeCapability>()) { result, requirements in
                result.formUnion(requirements)
            }
        let missingCapabilities = fullySupportedCapabilities
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
        let recoverySuggestion = suggestion(
            status: status,
            runtimeVersion: handshake.runtime.version,
            missingCapabilities: missingCapabilities
        )
        return AstrolabeRuntimeCompatibility(
            record: RuntimeCompatibilityRecord(
                status: status,
                hostVersion: AstrolabeHostMetadata.version,
                runtimeVersion: handshake.runtime.version,
                negotiatedProtocolVersion: RuntimeProtocolVersionRecord(
                    major: handshake.negotiatedProtocolVersion.major,
                    minor: handshake.negotiatedProtocolVersion.minor
                ),
                runtimeCapabilities: runtimeCapabilities
                    .map(\.rawValue)
                    .sorted(),
                missingRuntimeCapabilities: missingCapabilities,
                recoverySuggestion: recoverySuggestion
            ),
            supportedProviderCapabilities: supportedProviderCapabilities(
                runtimeCapabilities: runtimeCapabilities,
                isExpectedPlatform: isExpectedPlatform
            ),
            runtimeCapabilities: runtimeCapabilities,
            isExpectedPlatform: isExpectedPlatform
        )
    }

    func require(
        _ capability: RuntimeUICapability,
        compatibility: AstrolabeRuntimeCompatibility
    ) throws {
        guard let requirements = requirementsByProviderCapability[capability] else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "The iOS Runtime Provider does not define compatibility requirements for \(capability.rawValue)"
            )
        }
        try requireRuntimeCapabilities(
            requirements,
            compatibility: compatibility
        )
    }

    func requireRuntimeCapabilities(
        _ requirements: Set<RuntimeCapability>,
        compatibility: AstrolabeRuntimeCompatibility
    ) throws {
        guard compatibility.isExpectedPlatform else {
            throw AstrolabeRuntimeClientError.invalidResponse(
                "The target Runtime platform is not iOS"
            )
        }
        let missingCapabilities = requirements
            .subtracting(compatibility.runtimeCapabilities)
            .map(\.rawValue)
            .sorted()
        guard missingCapabilities.isEmpty else {
            throw AstrolabeRuntimeClientError.updateRequired(
                runtimeVersion: compatibility.record.runtimeVersion,
                missingCapabilities: missingCapabilities
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
                missingCapabilities: missingCapabilities
            )
        case .incompatible:
            return "The current Runtime platform is incompatible with the iOS Provider; ensure the app integrates astrolabe-runtime-ios"
        }
    }
}
