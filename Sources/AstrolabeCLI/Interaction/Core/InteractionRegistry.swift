//
//  InteractionRegistry.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/17.
//

import Foundation

package final class InteractionRegistry {
    /// Resolver used to derive Runtime platform from the current app identifier.
    private let platformResolver: any RuntimeUIPlatformResolving

    /// Registered interaction Provider strategies.
    private let providers: [any PlatformInteractionPerforming]

    package init(
        platformResolver: any RuntimeUIPlatformResolving,
        providers: [any PlatformInteractionPerforming]
    ) throws {
        let identifiers = providers.map(\.descriptor.identifier)
        if let duplicate = Self.firstDuplicate(in: identifiers) {
            throw InteractionError.duplicateProviderIdentifier(duplicate)
        }
        self.platformResolver = platformResolver
        self.providers = providers
    }

    package func perform(_ request: InteractionRequest) throws -> InteractionResult {
        let platform = try platformResolver.platform(for: request.target.appId)
        let contextualProviders = providers.filter {
            $0.descriptor.platform == platform
                && $0.descriptor.supportedDeviceKinds.contains(request.target.deviceKind)
        }
        guard !contextualProviders.isEmpty else {
            throw InteractionError.providerUnavailable(
                platform: platform,
                deviceKind: request.target.deviceKind
            )
        }
        let actionProviders = contextualProviders.filter {
            $0.descriptor.supportedActionKinds.contains(request.action.kind)
        }
        guard !actionProviders.isEmpty else {
            throw InteractionError.unsupportedAction(request.action.kind)
        }
        let capableProviders = actionProviders.filter { $0.canHandle(target: request.target) }
        guard !capableProviders.isEmpty else {
            throw InteractionError.providerUnavailable(
                platform: platform,
                deviceKind: request.target.deviceKind
            )
        }
        guard capableProviders.count == 1 else {
            throw InteractionError.ambiguousProviders(capableProviders.map(\.descriptor.identifier))
        }
        return try capableProviders[0].perform(request)
    }

    private static func firstDuplicate<Value: Hashable>(in values: [Value]) -> Value? {
        var seen = Set<Value>()
        return values.first { !seen.insert($0).inserted }
    }
}
