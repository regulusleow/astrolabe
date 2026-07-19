//
//  HierarchyNodeExtractor.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct HierarchyNodeRecord {
    /// Raw node dictionary returned by the Runtime UI Provider.
    let node: [String: Any]

    /// Stable hierarchy path from the root to the current node.
    let hierarchyPath: String

    /// Depth of the current node, where the root is 0.
    let depth: Int

    /// Index of the current node among its siblings.
    let siblingIndex: Int
}

struct HierarchyNodeVisibility {
    /// Whether the node and its ancestors' hidden and alpha states permit display.
    let hierarchyVisible: Bool

    /// Onscreen visibility computed by the Runtime from screen intersection and ancestor clipping.
    let onscreen: Bool
}

struct HierarchyNodeExtractor {
    private let valueFormatter = NodeDetailValueFormatter()
    private let semanticRoleClassifier = NodeSemanticRoleClassifier()

    func collectNodes(in hierarchy: [String: Any]) -> [[String: Any]] {
        collectNodes(from: hierarchy["displayItems"])
    }

    func collectNodeRecords(in hierarchy: [String: Any]) -> [HierarchyNodeRecord] {
        collectNodeRecords(from: hierarchy["displayItems"], parentPath: "", depth: 0)
    }

    func isVisibleNode(_ node: [String: Any]) -> Bool {
        visibility(from: node).onscreen
    }

    func nodeSnapshot(from node: [String: Any]) -> [String: Any] {
        let visibility = visibility(from: node)
        var snapshot: [String: Any] = [
            "oid": nodeIdentifier(from: node["oid"]) ?? "",
            "detailOid": nodeIdentifier(from: node["detailOid"])
                ?? nodeIdentifier(from: node["oid"])
                ?? "",
            "className": node["className"] as? String ?? "",
            "frame": node["frame"] ?? [:],
            "bounds": node["bounds"] ?? [:],
            "visible": visibility.onscreen,
            "onscreen": visibility.onscreen,
            "hierarchyVisible": visibility.hierarchyVisible,
            "hidden": node["hidden"] as? Bool ?? false,
            "inHiddenHierarchy": node["inHiddenHierarchy"] as? Bool ?? false,
            "alpha": numericValue(from: node["alpha"]) ?? 1,
            "semanticRoles": semanticRoles(from: node).map(\.rawValue).sorted()
        ]
        if let classChain = node["classChain"] as? [String] {
            snapshot["classChain"] = classChain
        }
        if let memoryAddress = node["memoryAddress"] as? String, !memoryAddress.isEmpty {
            snapshot["memoryAddress"] = memoryAddress
        }
        if let backgroundColor = node["backgroundColor"] {
            snapshot["backgroundColor"] = backgroundColor
            if let colorHex = valueFormatter.colorHex(from: backgroundColor, attrTypeName: "color") {
                snapshot["backgroundColorHex"] = colorHex
            }
            if let colorRGBA = valueFormatter.colorRGBA(from: backgroundColor, attrTypeName: "color") {
                snapshot["backgroundColorRGBA"] = colorRGBA
            }
        }
        if let text = text(from: node) {
            snapshot["text"] = text
        }
        if let kind = node["kind"] as? String {
            snapshot["kind"] = kind
        }
        if let indentLevel = node["indentLevel"] {
            snapshot["indentLevel"] = indentLevel
        }
        return snapshot
    }

    func visibility(from node: [String: Any]) -> HierarchyNodeVisibility {
        let hidden = node["hidden"] as? Bool ?? false
        let hiddenByAncestor = node["inHiddenHierarchy"] as? Bool ?? false
        let effectiveAlpha = numericValue(from: node["effectiveAlpha"])
            ?? numericValue(from: node["alpha"])
            ?? 1
        return HierarchyNodeVisibility(
            hierarchyVisible: !hidden && !hiddenByAncestor && effectiveAlpha > 0.01,
            onscreen: node["visible"] as? Bool ?? false
        )
    }

    func nodeSnapshot(from record: HierarchyNodeRecord) -> [String: Any] {
        var snapshot = nodeSnapshot(from: record.node)
        snapshot["hierarchyPath"] = record.hierarchyPath
        snapshot["depth"] = record.depth
        snapshot["siblingIndex"] = record.siblingIndex
        return snapshot
    }

    func textNodeSnapshot(from node: [String: Any]) -> [String: Any]? {
        guard let text = text(from: node) else {
            return nil
        }
        return [
            "oid": nodeIdentifier(from: node["oid"]) ?? "",
            "detailOid": nodeIdentifier(from: node["detailOid"])
                ?? nodeIdentifier(from: node["oid"])
                ?? "",
            "className": node["className"] as? String ?? "",
            "text": text,
            "frame": node["frame"] ?? [:]
        ]
    }

    func textNodeSnapshot(from record: HierarchyNodeRecord) -> [String: Any]? {
        guard var snapshot = textNodeSnapshot(from: record.node) else {
            return nil
        }
        snapshot["hierarchyPath"] = record.hierarchyPath
        snapshot["depth"] = record.depth
        snapshot["siblingIndex"] = record.siblingIndex
        return snapshot
    }

    func text(from node: [String: Any]) -> String? {
        guard let text = node["customDisplayTitle"] as? String, !text.isEmpty else {
            return nil
        }
        return text
    }

    func semanticRoles(from node: [String: Any]) -> Set<NodeSemanticRole> {
        semanticRoleClassifier.roles(for: node)
    }

    func numericValue(from value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let double = value as? Double {
            return double
        }
        if let int = value as? Int {
            return Double(int)
        }
        return nil
    }

    func nodeIdentifier(from value: Any?) -> String? {
        guard let identifier = value as? String, !identifier.isEmpty else {
            return nil
        }
        return identifier
    }

    private func collectNodes(from value: Any?) -> [[String: Any]] {
        guard let value else {
            return []
        }

        var result: [[String: Any]] = []
        var stack: [Any] = [value]
        while let current = stack.popLast() {
            if let array = current as? [Any] {
                stack.append(contentsOf: array.reversed())
                continue
            }
            guard let dictionary = current as? [String: Any] else {
                continue
            }
            if dictionary["className"] is String {
                result.append(dictionary)
            }
            if let subitems = dictionary["subitems"] as? [Any] {
                stack.append(contentsOf: subitems.reversed())
            }
        }
        return result
    }

    private func collectNodeRecords(from value: Any?, parentPath: String, depth: Int) -> [HierarchyNodeRecord] {
        guard let array = value as? [Any] else {
            return []
        }

        var result: [HierarchyNodeRecord] = []
        for (index, item) in array.enumerated() {
            guard let dictionary = item as? [String: Any],
                  dictionary["className"] is String else {
                continue
            }
            let pathComponent = "\(dictionary["className"] as? String ?? "Unknown")[\(index)]"
            let hierarchyPath = parentPath.isEmpty ? pathComponent : "\(parentPath)/\(pathComponent)"
            let record = HierarchyNodeRecord(
                node: dictionary,
                hierarchyPath: hierarchyPath,
                depth: depth,
                siblingIndex: index
            )
            result.append(record)
            result.append(contentsOf: collectNodeRecords(
                from: dictionary["subitems"],
                parentPath: hierarchyPath,
                depth: depth + 1
            ))
        }
        return result
    }
}
