//
//  AstrolabeMacOSHostFactory.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/11/20.
//

import AstrolabeCLI

package enum AstrolabeMacOSHostFactory {
    package static func makePlatformModule() throws -> HostPlatformModule {
        let provider = AstrolabeMacOSRuntimeProvider()
        let strategy = AppKitInspectionStrategy()
        return try HostPlatformModuleBuilder(provider: provider)
            .applicationDiscovery(provider)
            .appDiscoveryDiagnostics(provider)
            .hierarchyCapture(provider)
            .nodeDetail(provider)
            .screenInspectionBuilder(ScreenInspectionBuilder(qualityPolicy: strategy))
            .semanticRoleClassifier(strategy)
            .nodeDetailSemanticMapper(strategy)
            .nodeDetailIssueInterpreter(PlatformNeutralNodeDetailSemanticIssueInterpreter())
            .build()
    }
}

private struct AppKitInspectionStrategy:
    ScreenInspectionTargetQualityEvaluating,
    NodeSemanticRoleClassifying,
    NodeDetailAttributeSemanticMapping
{
    func roles(for node: [String: Any]) -> Set<NodeSemanticRole> {
        guard let value = node["runtimeRole"] as? String,
              let role = NodeSemanticRole(rawValue: value) else { return [] }
        return [role]
    }

    func isEligible(_ context: ScreenInspectionTargetEligibilityContext) -> Bool {
        !context.semanticRoles.contains(.window) && (context.hasText || !context.semanticRoles.isEmpty)
    }

    func priority(
        className: String,
        semanticRoles: Set<NodeSemanticRole>,
        reason: ScreenInspectionTargetReason
    ) -> Int {
        0
    }

    func semantics(forIdentifier identifier: String, appId: String) -> NodeDetailAttributeSemantics? {
        guard identifier.hasPrefix("common."), let name = identifier.split(separator: ".").last else { return nil }
        return NodeDetailAttributeSemantics(name: String(name), path: identifier)
    }
}
