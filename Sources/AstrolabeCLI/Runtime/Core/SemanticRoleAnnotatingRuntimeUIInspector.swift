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
        try fetchHierarchy(appId: appId, semanticCapture: nil)
    }

    func fetchHierarchy(appId: String, semanticCapture: RuntimeSemanticCaptureOptions?) throws -> [String: Any] {
        let hierarchy = try base.fetchHierarchy(appId: appId, semanticCapture: semanticCapture)
        let platform = try base.platform(for: appId)
        var resolvedClassifiers: [any NodeSemanticRoleClassifying] = [
            NodeSemanticRoleClassifier()
        ]
        if let platformClassifier = classifiers[platform] {
            resolvedClassifiers.append(platformClassifier)
        }
        var result = hierarchy
        for branch in ["displayItems", "semanticItems"] {
            if let items = hierarchy[branch] {
                result[branch] = annotate(value: items, classifiers: resolvedClassifiers)
            }
        }
        return result
    }

    func fetchNodeDetail(appId: String, oid: String) throws -> [String: Any] {
        try base.fetchNodeDetail(appId: appId, oid: oid)
    }

    func preflightNativeNode(appId: String, oid: String) throws {
        try base.preflightNativeNode(appId: appId, oid: oid)
    }

    func fetchNodeDetail(appId: String, oid: String, runtimeSnapshotID: String) throws -> [String: Any] {
        try base.fetchNodeDetail(appId: appId, oid: oid, runtimeSnapshotID: runtimeSnapshotID)
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
        if node["kind"] as? String == "semantic" {
            node["semanticRoles"] = NodeSemanticRoleClassifier().roles(for: node)
                .map(\.rawValue)
                .sorted()
        } else if node["className"] is String {
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
