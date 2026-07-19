//
//  NodeSemanticRoleClassifier.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/10.
//

import Foundation

package enum NodeSemanticRole: String, CaseIterable, Hashable {
    case avatar
    case button
    case control
    case image
    case input
    case list
    case navigation
    case scroll
    case stack
    case tabBar
    case text
    case timer
    case web
    case window

    static func parse(_ value: String) throws -> NodeSemanticRole {
        guard let role = allCases.first(where: { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame }) else {
            let supportedRoles = allCases.map(\.rawValue).sorted().joined(separator: ", ")
            throw CLIError.invalidArgument("Unknown semantic role: \(value). Supported roles: \(supportedRoles)")
        }
        return role
    }
}

package protocol NodeSemanticRoleClassifying {
    func roles(for node: [String: Any]) -> Set<NodeSemanticRole>
}

struct NodeSemanticRoleClassifier: NodeSemanticRoleClassifying {
    func roles(for node: [String: Any]) -> Set<NodeSemanticRole> {
        let classNames = classNames(from: node).map { $0.lowercased() }
        let classText = classNames.joined(separator: " ")
        let semanticText = semanticStrings(from: node).joined(separator: " ").lowercased()
        var roles = Set(
            (node["semanticRoles"] as? [String] ?? [])
                .compactMap(NodeSemanticRole.init(rawValue:))
        )

        appendDomainRoles(classText: classText, semanticText: semanticText, to: &roles)
        return roles
    }

    private func appendDomainRoles(
        classText: String,
        semanticText: String,
        to roles: inout Set<NodeSemanticRole>
    ) {
        let searchableText = "\(classText) \(semanticText)"
        if containsAny(searchableText, ["avatar", "profileimage", "profile_image", "userimage", "userpic"]) {
            roles.insert(.avatar)
            roles.insert(.image)
        }
        if containsAny(searchableText, ["timer", "countdown"]) || containsTimeValue(in: semanticText) {
            roles.insert(.timer)
            roles.insert(.text)
        }
    }

    private func classNames(from node: [String: Any]) -> [String] {
        var names = node["classChain"] as? [String] ?? []
        if let className = node["className"] as? String, !className.isEmpty {
            names.append(className)
        }
        return names
    }

    private func semanticStrings(from node: [String: Any]) -> [String] {
        var values = [
            node["customDisplayTitle"] as? String,
            node["danceuiSource"] as? String,
            node["specialTrace"] as? String
        ].compactMap { $0 }.filter { !$0.isEmpty }

        if let customInfo = node["customInfo"] as? [String: Any] {
            values.append(contentsOf: ["title", "subtitle", "danceuiSource"].compactMap { key in
                guard let value = customInfo[key] as? String, !value.isEmpty else {
                    return nil
                }
                return value
            })
        }
        return values
    }

    private func containsAny(_ value: String, _ candidates: [String]) -> Bool {
        candidates.contains { value.contains($0) }
    }

    private func containsTimeValue(in text: String) -> Bool {
        text.split(whereSeparator: { $0.isWhitespace }).contains { token in
            let components = token.split(separator: ":", omittingEmptySubsequences: false)
            guard components.count == 2 || components.count == 3 else {
                return false
            }
            return components.enumerated().allSatisfy { index, component in
                guard !component.isEmpty, component.allSatisfy(\.isNumber) else {
                    return false
                }
                return index == 0 || component.count == 2
            }
        }
    }
}
