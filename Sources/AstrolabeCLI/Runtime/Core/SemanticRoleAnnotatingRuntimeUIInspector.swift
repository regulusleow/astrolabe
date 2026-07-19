//
//  SemanticRoleAnnotatingRuntimeUIInspector.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

import AstrolabeProtocol
import Foundation

struct SemanticRoleAnnotatingRuntimeUIInspector: RuntimeUIInspecting {
    private let base: any RuntimeUIInspecting
    private let classifiers: [RuntimeUIPlatform: any NodeSemanticRoleClassifying]

    init(
        base: any RuntimeUIInspecting,
        classifiers: [RuntimeUIPlatform: any NodeSemanticRoleClassifying]
    ) {
        self.base = base
        self.classifiers = classifiers
    }

    func fetchApps() throws -> [InspectableAppRecord] {
        try base.fetchApps()
    }

    func appDiscoveryDiagnostics() -> [RuntimeAppDiscoveryDiagnostic] {
        base.appDiscoveryDiagnostics()
    }

    func platform(for appId: String) throws -> RuntimeUIPlatform {
        try base.platform(for: appId)
    }

    func fetchHierarchy(appId: String) throws -> [String: Any] {
        let hierarchy = try base.fetchHierarchy(appId: appId)
        let platform = try base.platform(for: appId)
        guard let displayItems = hierarchy["displayItems"] else {
            return hierarchy
        }
        var resolvedClassifiers: [any NodeSemanticRoleClassifying] = [
            NodeSemanticRoleClassifier()
        ]
        if let platformClassifier = classifiers[platform] {
            resolvedClassifiers.append(platformClassifier)
        }
        var result = hierarchy
        result["displayItems"] = annotate(
            value: displayItems,
            classifiers: resolvedClassifiers
        )
        return result
    }

    func fetchNodeDetail(appId: String, oid: String) throws -> [String: Any] {
        try base.fetchNodeDetail(appId: appId, oid: oid)
    }

    func fetchNodeDetails(appId: String, oids: [String]) throws -> RuntimeNodeDetailBatch {
        try base.fetchNodeDetails(appId: appId, oids: oids)
    }

    func fetchPatchableAttributeCatalog(
        appId: String
    ) throws -> RuntimePatchableAttributesPayload {
        try base.fetchPatchableAttributeCatalog(appId: appId)
    }

    func applyAttributePatch(
        appId: String,
        oid: String,
        attributeIdentifier: String,
        value: RuntimeAttributeValue
    ) throws -> [String: Any] {
        try base.applyAttributePatch(
            appId: appId,
            oid: oid,
            attributeIdentifier: attributeIdentifier,
            value: value
        )
    }

    func fetchAttributePatches(appId: String) throws -> [String: Any] {
        try base.fetchAttributePatches(appId: appId)
    }

    func revertAttributePatch(appId: String, patchID: String) throws -> [String: Any] {
        try base.revertAttributePatch(appId: appId, patchID: patchID)
    }

    func clearAttributePatches(appId: String) throws -> [String: Any] {
        try base.clearAttributePatches(appId: appId)
    }

    private func annotate(
        value: Any,
        classifiers: [any NodeSemanticRoleClassifying]
    ) -> Any {
        if let items = value as? [Any] {
            return items.map { annotate(value: $0, classifiers: classifiers) }
        }
        guard var node = value as? [String: Any] else {
            return value
        }
        if node["className"] is String {
            let existingRoles = Set(
                (node["semanticRoles"] as? [String] ?? [])
                    .compactMap(NodeSemanticRole.init(rawValue:))
            )
            let resolvedRoles = classifiers.reduce(into: existingRoles) {
                roles, classifier in
                roles.formUnion(classifier.roles(for: node))
            }
            node["semanticRoles"] = resolvedRoles
                .map(\.rawValue)
                .sorted()
        }
        if let subitems = node["subitems"] {
            node["subitems"] = annotate(
                value: subitems,
                classifiers: classifiers
            )
        }
        return node
    }
}
