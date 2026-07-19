//
//  UIKitNodeSemanticRoleClassifier.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

import AstrolabeCLI

package struct UIKitNodeSemanticRoleClassifier: NodeSemanticRoleClassifying {
    package init() {}

    package func roles(for node: [String: Any]) -> Set<NodeSemanticRole> {
        let classNames = classNames(from: node).map { $0.lowercased() }
        let hasDisplayText = (node["customDisplayTitle"] as? String)?.isEmpty == false
        var roles: Set<NodeSemanticRole> = []

        if classNames.contains(where: { $0.hasSuffix("window") }) {
            roles.insert(.window)
        }
        if containsAnyClass(classNames, ["navigationbar", "navigationcontroller"]) {
            roles.insert(.navigation)
        }
        if containsAnyClass(classNames, ["tabbar"]) {
            roles.insert(.tabBar)
        }
        if containsAnyClass(classNames, ["tableview", "collectionview"]) {
            roles.insert(.list)
        }
        if containsAnyClass(classNames, ["scrollview"]) {
            roles.insert(.scroll)
        }
        if containsAnyClass(classNames, ["stackview"]) {
            roles.insert(.stack)
        }
        if containsAnyClass(classNames, ["label", "textview"]) || hasDisplayText {
            roles.insert(.text)
        }
        if containsAnyClass(classNames, ["imageview"]) {
            roles.insert(.image)
        }
        if classNames.contains(where: { $0.hasSuffix("button") }) {
            roles.insert(.button)
        }
        if containsAnyClass(classNames, ["textfield", "uitextview", "searchbar"]) {
            roles.insert(.input)
        }
        if roles.contains(.button) || classNames.contains("uicontrol") ||
            containsAnyClass(classNames, ["switch", "slider", "stepper", "segmentedcontrol"]) {
            roles.insert(.control)
        }
        if containsAnyClass(classNames, ["webview"]) {
            roles.insert(.web)
        }
        return roles
    }

    private func classNames(from node: [String: Any]) -> [String] {
        var names = node["classChain"] as? [String] ?? []
        if let className = node["className"] as? String, !className.isEmpty {
            names.append(className)
        }
        return names
    }

    private func containsAnyClass(_ classNames: [String], _ candidates: [String]) -> Bool {
        classNames.contains { className in
            candidates.contains { className.contains($0) }
        }
    }
}
