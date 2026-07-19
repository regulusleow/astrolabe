//
//  HostPlatformStrategyAdapters.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

struct HostPlatformNodeDetailSemanticMapper: NodeDetailAttributeSemanticMapping {
    private let registry: HostPlatformModuleRegistry

    init(registry: HostPlatformModuleRegistry) {
        self.registry = registry
    }

    func semantics(
        forIdentifier identifier: String,
        appId: String
    ) -> NodeDetailAttributeSemantics? {
        guard let module = try? registry.module(for: appId),
              let mapper = module.nodeDetailSemanticMapper else {
            return nil
        }
        return mapper.semantics(forIdentifier: identifier, appId: appId)
    }
}

struct HostPlatformNodeDetailIssueInterpreter: NodeDetailSemanticIssueInterpreting {
    private let registry: HostPlatformModuleRegistry

    init(registry: HostPlatformModuleRegistry) {
        self.registry = registry
    }

    func issueName(for semanticName: String, appId: String) -> String {
        guard let module = try? registry.module(for: appId),
              let interpreter = module.nodeDetailIssueInterpreter else {
            return "\(semanticName)Changed"
        }
        return interpreter.issueName(for: semanticName, appId: appId)
    }
}

struct HostPlatformVisualDiffIssueInterpreter: VisualDiffIssueInterpreting {
    private let registry: HostPlatformModuleRegistry
    private let fallback = PlatformNeutralVisualDiffIssueInterpreter()

    init(registry: HostPlatformModuleRegistry) {
        self.registry = registry
    }

    func interpretation(
        for node: [String: Any],
        suspectedIssues: [String],
        appId: String
    ) -> VisualDiffIssueInterpretation {
        let interpreter = resolvedInterpreter(appId: appId)
        return interpreter.interpretation(
            for: node,
            suspectedIssues: suspectedIssues,
            appId: appId
        )
    }

    func categoryRank(for category: String, appId: String) -> Int {
        resolvedInterpreter(appId: appId).categoryRank(
            for: category,
            appId: appId
        )
    }

    func semanticWeight(for node: [String: Any], appId: String) -> Double {
        resolvedInterpreter(appId: appId).semanticWeight(for: node, appId: appId)
    }

    func suspectedIssues(for node: [String: Any], appId: String) -> [String] {
        resolvedInterpreter(appId: appId).suspectedIssues(for: node, appId: appId)
    }

    private func resolvedInterpreter(appId: String) -> any VisualDiffIssueInterpreting {
        guard let module = try? registry.module(for: appId),
              let interpreter = module.visualDiffIssueInterpreter else {
            return fallback
        }
        return interpreter
    }
}
