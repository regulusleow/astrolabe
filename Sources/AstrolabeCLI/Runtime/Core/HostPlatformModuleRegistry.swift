//
//  HostPlatformModuleRegistry.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

import AstrolabeProtocol
import Foundation

package struct HostPlatformModuleRegistry: RuntimeUIInspecting {
    private let modules: [HostPlatformModule]

    package init(modules: [HostPlatformModule]) throws {
        guard !modules.isEmpty else {
            throw HostPlatformModuleValidationError.missingPlatformModule
        }
        let identifiers = modules.map(\.providerDescriptor.identifier)
        if let duplicate = Self.firstDuplicate(in: identifiers) {
            throw HostPlatformModuleValidationError.duplicateProviderIdentifier(duplicate)
        }
        let platforms = modules.map(\.platform)
        if let duplicate = Self.firstDuplicate(in: platforms) {
            throw HostPlatformModuleValidationError.duplicatePlatform(duplicate)
        }
        self.modules = modules
    }

    package func fetchApps() throws -> [InspectableAppRecord] {
        try modules.compactMap(\.applicationDiscovery).flatMap { try $0.fetchApps() }
    }

    package func appDiscoveryDiagnostics() -> [RuntimeAppDiscoveryDiagnostic] {
        modules.compactMap(\.appDiscoveryDiagnostics)
            .flatMap { $0.appDiscoveryDiagnostics() }
    }

    package func platform(for appId: String) throws -> RuntimeUIPlatform {
        try module(for: appId).platform
    }

    package func fetchHierarchy(appId: String) throws -> [String: Any] {
        let module = try module(for: appId)
        guard let provider = module.hierarchyCapture else {
            throw unsupportedCapability(.hierarchy, appId: appId, module: module)
        }
        return try provider.fetchHierarchy(appId: appId)
    }

    package func fetchNodeDetail(appId: String, oid: String) throws -> [String: Any] {
        let module = try module(for: appId)
        guard let provider = module.nodeDetailProvider else {
            throw unsupportedCapability(.nodeDetail, appId: appId, module: module)
        }
        return try provider.fetchNodeDetail(appId: appId, oid: oid)
    }

    package func fetchNodeDetails(
        appId: String,
        oids: [String]
    ) throws -> RuntimeNodeDetailBatch {
        let module = try module(for: appId)
        guard let provider = module.nodeDetailProvider else {
            throw unsupportedCapability(.nodeDetail, appId: appId, module: module)
        }
        return try provider.fetchNodeDetails(appId: appId, oids: oids)
    }

    package func fetchPatchableAttributeCatalog(
        appId: String
    ) throws -> RuntimePatchableAttributesPayload {
        let module = try module(for: appId)
        guard let provider = module.patchCatalogProvider else {
            throw unsupportedCapability(.attributePatchDiscovery, appId: appId, module: module)
        }
        return try provider.fetchPatchableAttributeCatalog(appId: appId)
    }

    package func applyAttributePatch(
        appId: String,
        oid: String,
        attributeIdentifier: String,
        value: RuntimeAttributeValue
    ) throws -> [String: Any] {
        let module = try module(for: appId)
        guard let provider = module.attributePatcher else {
            throw unsupportedCapability(.attributePatching, appId: appId, module: module)
        }
        return try provider.applyAttributePatch(
            appId: appId,
            oid: oid,
            attributeIdentifier: attributeIdentifier,
            value: value
        )
    }

    package func fetchAttributePatches(appId: String) throws -> [String: Any] {
        let module = try module(for: appId)
        guard let provider = module.attributePatcher else {
            throw unsupportedCapability(.attributePatching, appId: appId, module: module)
        }
        return try provider.fetchAttributePatches(appId: appId)
    }

    package func revertAttributePatch(appId: String, patchID: String) throws -> [String: Any] {
        let module = try module(for: appId)
        guard let provider = module.attributePatcher else {
            throw unsupportedCapability(.attributePatching, appId: appId, module: module)
        }
        return try provider.revertAttributePatch(appId: appId, patchID: patchID)
    }

    package func clearAttributePatches(appId: String) throws -> [String: Any] {
        let module = try module(for: appId)
        guard let provider = module.attributePatcher else {
            throw unsupportedCapability(.attributePatching, appId: appId, module: module)
        }
        return try provider.clearAttributePatches(appId: appId)
    }

    func module(for appId: String) throws -> HostPlatformModule {
        let matches = modules.filter { $0.providerTargeting.canHandle(appId: appId) }
        guard let module = matches.first else {
            throw CLIError.targetProviderNotFound(appId)
        }
        guard matches.count == 1 else {
            throw CLIError.commandFailed("Multiple Host platform modules can handle appId: \(appId)")
        }
        return module
    }

    func modulesByPlatform() -> [RuntimeUIPlatform: HostPlatformModule] {
        Dictionary(uniqueKeysWithValues: modules.map { ($0.platform, $0) })
    }

    private func unsupportedCapability(
        _ capability: RuntimeUICapability,
        appId: String,
        module: HostPlatformModule
    ) -> CLIError {
        .targetCapabilityUnsupported(
            appId: appId,
            providerIdentifier: module.providerDescriptor.identifier,
            capability: capability
        )
    }

    private static func firstDuplicate<Value: Hashable>(
        in values: [Value]
    ) -> Value? {
        var seen = Set<Value>()
        return values.first { !seen.insert($0).inserted }
    }
}
