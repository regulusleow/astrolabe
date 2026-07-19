//
//  HostPlatformModule.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

import AstrolabeProtocol
import Foundation

package enum HostPlatformModuleValidationError:
    Error,
    Equatable,
    CustomStringConvertible {
    case capabilityImplementationMismatch(
        providerIdentifier: String,
        declared: Set<RuntimeUICapability>,
        registered: Set<RuntimeUICapability>
    )
    case incompleteScreenshotRegistration(platform: RuntimeUIPlatform)
    case incompleteHierarchyRegistration(platform: RuntimeUIPlatform)
    case incompleteNodeDetailRegistration(platform: RuntimeUIPlatform)
    case missingPlatformModule
    case duplicateProviderIdentifier(String)
    case duplicatePlatform(RuntimeUIPlatform)

    package var description: String {
        switch self {
        case let .capabilityImplementationMismatch(identifier, declared, registered):
            return "Provider \(identifier) capability declaration does not match its implementation: declared \(capabilityNames(declared)), registered \(capabilityNames(registered))"
        case .incompleteScreenshotRegistration(let platform):
            return "Screenshot capability registration is incomplete for platform \(platform.rawValue)"
        case .incompleteHierarchyRegistration(let platform):
            return "Hierarchy inspection capability registration is incomplete for platform \(platform.rawValue)"
        case .incompleteNodeDetailRegistration(let platform):
            return "Node-detail semantic capability registration is incomplete for platform \(platform.rawValue)"
        case .missingPlatformModule:
            return "The Host requires at least one platform module"
        case .duplicateProviderIdentifier(let identifier):
            return "Host platform modules contain a duplicate Provider identifier: \(identifier)"
        case .duplicatePlatform(let platform):
            return "Host platform modules contain a duplicate platform: \(platform.rawValue)"
        }
    }

    private func capabilityNames(_ capabilities: Set<RuntimeUICapability>) -> String {
        capabilities.map(\.rawValue).sorted().joined(separator: ",")
    }
}

package struct HostPlatformModule {
    /// Platform owned by this module.
    package var platform: RuntimeUIPlatform {
        providerDescriptor.platform
    }

    /// Provider descriptor associated with this module.
    package let providerDescriptor: RuntimeUIProviderDescriptor

    /// Routing capability that determines whether this module can handle an appId.
    let providerTargeting: any RuntimeUIProviderTargeting

    /// Optional app discovery capability.
    let applicationDiscovery: (any RuntimeApplicationDiscovering)?

    /// Optional app discovery diagnostics capability.
    let appDiscoveryDiagnostics: (any RuntimeUIAppDiscoveryDiagnosing)?

    /// Optional hierarchy capture capability.
    let hierarchyCapture: (any RuntimeUIHierarchyCapturing)?

    /// Optional node-detail capability.
    let nodeDetailProvider: (any RuntimeUINodeDetailProviding)?

    /// Optional patch allowlist discovery capability.
    let patchCatalogProvider: (any RuntimeUIPatchCatalogProviding)?

    /// Optional attribute-patch lifecycle capability.
    let attributePatcher: (any RuntimeUIAttributePatching)?

    /// Optional screenshot option resolution policy.
    let screenshotOptionsBuilder: (any ScreenshotCaptureOptionsBuilding)?

    /// Optional platform screenshot implementation.
    let screenshotProvider: (any PlatformScreenshotProviding)?

    /// Optional screen inspection builder.
    let screenInspectionBuilder: ScreenInspectionBuilder?

    /// Optional platform node semantic-role classifier.
    let semanticRoleClassifier: (any NodeSemanticRoleClassifying)?

    /// Optional platform node-detail attribute semantic mapper.
    let nodeDetailSemanticMapper: (any NodeDetailAttributeSemanticMapping)?

    /// Optional platform node-detail change interpreter.
    let nodeDetailIssueInterpreter: (any NodeDetailSemanticIssueInterpreting)?

    /// Optional platform visual-difference interpreter.
    let visualDiffIssueInterpreter: (any VisualDiffIssueInterpreting)?

    /// Optional platform named screenshot mask resolver.
    let namedMaskResolver: (any ScreenshotNamedMaskResolving)?
}

package struct HostPlatformModuleBuilder {
    private let provider: any RuntimeUIProviderTargeting
    private var applicationDiscoveryProvider: (any RuntimeApplicationDiscovering)?
    private var appDiscoveryDiagnosticProvider: (any RuntimeUIAppDiscoveryDiagnosing)?
    private var hierarchyCaptureProvider: (any RuntimeUIHierarchyCapturing)?
    private var nodeDetailProvider: (any RuntimeUINodeDetailProviding)?
    private var patchCatalogProvider: (any RuntimeUIPatchCatalogProviding)?
    private var attributePatcher: (any RuntimeUIAttributePatching)?
    private var captureOptionsBuilder: (any ScreenshotCaptureOptionsBuilding)?
    private var platformScreenshotProvider: (any PlatformScreenshotProviding)?
    private var inspectionBuilder: ScreenInspectionBuilder?
    private var roleClassifier: (any NodeSemanticRoleClassifying)?
    private var detailSemanticMapper: (any NodeDetailAttributeSemanticMapping)?
    private var detailIssueInterpreter: (any NodeDetailSemanticIssueInterpreting)?
    private var diffIssueInterpreter: (any VisualDiffIssueInterpreting)?
    private var maskResolver: (any ScreenshotNamedMaskResolving)?

    package init(provider: any RuntimeUIProviderTargeting) {
        self.provider = provider
    }

    package func applicationDiscovery(
        _ value: any RuntimeApplicationDiscovering
    ) -> Self {
        var result = self
        result.applicationDiscoveryProvider = value
        return result
    }

    package func hierarchyCapture(_ value: any RuntimeUIHierarchyCapturing) -> Self {
        var result = self
        result.hierarchyCaptureProvider = value
        return result
    }

    package func appDiscoveryDiagnostics(
        _ value: any RuntimeUIAppDiscoveryDiagnosing
    ) -> Self {
        var result = self
        result.appDiscoveryDiagnosticProvider = value
        return result
    }

    package func nodeDetail(_ value: any RuntimeUINodeDetailProviding) -> Self {
        var result = self
        result.nodeDetailProvider = value
        return result
    }

    package func patchCatalog(_ value: any RuntimeUIPatchCatalogProviding) -> Self {
        var result = self
        result.patchCatalogProvider = value
        return result
    }

    package func attributePatching(_ value: any RuntimeUIAttributePatching) -> Self {
        var result = self
        result.attributePatcher = value
        return result
    }

    package func screenshotOptionsBuilder(
        _ value: any ScreenshotCaptureOptionsBuilding
    ) -> Self {
        var result = self
        result.captureOptionsBuilder = value
        return result
    }

    package func screenshotProvider(_ value: any PlatformScreenshotProviding) -> Self {
        var result = self
        result.platformScreenshotProvider = value
        return result
    }

    package func screenInspectionBuilder(_ value: ScreenInspectionBuilder) -> Self {
        var result = self
        result.inspectionBuilder = value
        return result
    }

    package func semanticRoleClassifier(
        _ value: any NodeSemanticRoleClassifying
    ) -> Self {
        var result = self
        result.roleClassifier = value
        return result
    }

    package func nodeDetailSemanticMapper(
        _ value: any NodeDetailAttributeSemanticMapping
    ) -> Self {
        var result = self
        result.detailSemanticMapper = value
        return result
    }

    package func nodeDetailIssueInterpreter(
        _ value: any NodeDetailSemanticIssueInterpreting
    ) -> Self {
        var result = self
        result.detailIssueInterpreter = value
        return result
    }

    package func visualDiffIssueInterpreter(
        _ value: any VisualDiffIssueInterpreting
    ) -> Self {
        var result = self
        result.diffIssueInterpreter = value
        return result
    }

    package func namedMaskResolver(_ value: any ScreenshotNamedMaskResolving) -> Self {
        var result = self
        result.maskResolver = value
        return result
    }

    package func build() throws -> HostPlatformModule {
        let registeredCapabilities = registeredCapabilities
        guard provider.descriptor.capabilities == registeredCapabilities else {
            throw HostPlatformModuleValidationError.capabilityImplementationMismatch(
                providerIdentifier: provider.descriptor.identifier,
                declared: provider.descriptor.capabilities,
                registered: registeredCapabilities
            )
        }
        let hasScreenshotOptions = captureOptionsBuilder != nil
        let hasScreenshotProvider = platformScreenshotProvider != nil
        let hasVisualDiffInterpreter = diffIssueInterpreter != nil
        guard hasScreenshotOptions == hasScreenshotProvider,
              !hasScreenshotProvider || hasVisualDiffInterpreter else {
            throw HostPlatformModuleValidationError.incompleteScreenshotRegistration(
                platform: provider.descriptor.platform
            )
        }
        if hierarchyCaptureProvider != nil,
           (inspectionBuilder == nil || roleClassifier == nil) {
            throw HostPlatformModuleValidationError.incompleteHierarchyRegistration(
                platform: provider.descriptor.platform
            )
        }
        if nodeDetailProvider != nil,
           (detailSemanticMapper == nil || detailIssueInterpreter == nil) {
            throw HostPlatformModuleValidationError.incompleteNodeDetailRegistration(
                platform: provider.descriptor.platform
            )
        }
        return HostPlatformModule(
            providerDescriptor: provider.descriptor,
            providerTargeting: provider,
            applicationDiscovery: applicationDiscoveryProvider,
            appDiscoveryDiagnostics: appDiscoveryDiagnosticProvider,
            hierarchyCapture: hierarchyCaptureProvider,
            nodeDetailProvider: nodeDetailProvider,
            patchCatalogProvider: patchCatalogProvider,
            attributePatcher: attributePatcher,
            screenshotOptionsBuilder: captureOptionsBuilder,
            screenshotProvider: platformScreenshotProvider,
            screenInspectionBuilder: inspectionBuilder,
            semanticRoleClassifier: roleClassifier,
            nodeDetailSemanticMapper: detailSemanticMapper,
            nodeDetailIssueInterpreter: detailIssueInterpreter,
            visualDiffIssueInterpreter: diffIssueInterpreter,
            namedMaskResolver: maskResolver
        )
    }

    private var registeredCapabilities: Set<RuntimeUICapability> {
        var result = Set<RuntimeUICapability>()
        if applicationDiscoveryProvider != nil {
            result.insert(.appDiscovery)
        }
        if hierarchyCaptureProvider != nil {
            result.insert(.hierarchy)
        }
        if nodeDetailProvider != nil {
            result.insert(.nodeDetail)
        }
        if patchCatalogProvider != nil {
            result.insert(.attributePatchDiscovery)
        }
        if attributePatcher != nil {
            result.insert(.attributePatching)
        }
        return result
    }
}
