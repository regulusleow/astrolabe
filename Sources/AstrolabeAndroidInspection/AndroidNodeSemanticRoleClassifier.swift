//
//  AndroidNodeSemanticRoleClassifier.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeCLI

package struct AndroidNodeSemanticRoleClassifier: NodeSemanticRoleClassifying {
    package init() {}

    package func roles(for node: [String: Any]) -> Set<NodeSemanticRole> {
        let classNames = classNames(from: node).map { $0.lowercased() }
        let runtimeRole = (node["role"] as? String)?.lowercased()
        var roles = roles(forRuntimeRole: runtimeRole)

        if containsAnyClass(classNames, ["recyclerview", "listview", "gridview"]) {
            roles.formUnion([.list, .scroll])
        } else if containsAnyClass(classNames, ["scrollview"]) {
            roles.insert(.scroll)
        }
        if containsAnyClass(classNames, ["edittext", "textinputedittext", "searchview"]) {
            roles.formUnion([.input, .text])
        } else if containsAnyClass(classNames, ["textview"]) {
            roles.insert(.text)
        }
        if containsAnyClass(classNames, ["imageview"]) {
            roles.insert(.image)
        }
        let isToggle = runtimeRole == "toggle" || containsAnyClass(
            classNames,
            ["compoundbutton", "switch", "checkbox", "radiobutton"]
        )
        if !isToggle, containsAnyClass(classNames, ["button"]) {
            roles.formUnion([.button, .control])
        }
        if isToggle || containsAnyClass(classNames, ["seekbar"]) {
            roles.insert(.control)
        }
        if containsAnyClass(classNames, ["webview"]) {
            roles.insert(.web)
        }
        if containsAnyClass(classNames, ["toolbar", "actionbar"]) {
            roles.insert(.navigation)
        }
        if containsAnyClass(classNames, ["bottomnavigationview", "tablayout"]) {
            roles.insert(.tabBar)
        }
        if classNames.contains(where: { $0.hasSuffix("decorview") }) {
            roles.insert(.window)
        }
        return roles
    }

    private func roles(forRuntimeRole runtimeRole: String?) -> Set<NodeSemanticRole> {
        switch runtimeRole {
        case "window":
            return [.window]
        case "button":
            return [.button, .control, .text]
        case "toggle":
            return [.control, .text]
        case "textinput":
            return [.input, .text]
        case "image":
            return [.image]
        case "label":
            return [.text]
        case "scroll":
            return [.scroll]
        default:
            return []
        }
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
            candidates.contains(where: className.contains)
        }
    }
}
