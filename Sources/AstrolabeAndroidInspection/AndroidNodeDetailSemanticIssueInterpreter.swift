//
//  AndroidNodeDetailSemanticIssueInterpreter.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeCLI

package struct AndroidNodeDetailSemanticIssueInterpreter:
    NodeDetailSemanticIssueInterpreting {
    package init() {}

    package func issueName(for semanticName: String, appId: String) -> String {
        switch semanticName {
        case "fontSize":
            return "fontSizeChanged"
        case "textColor":
            return "textColorChanged"
        case "backgroundColor":
            return "backgroundColorChanged"
        case "hidden", "hiddenByAncestor", "visibility", "onscreen":
            return "visibilityChanged"
        case "opacity", "effectiveOpacity":
            return "opacityChanged"
        case "enabled", "selected", "activated", "checked":
            return "controlStateChanged"
        case "clickable", "longClickable", "focusable":
            return "interactionChanged"
        case "scaleType":
            return "contentModeChanged"
        case "imagePresent", "imageType":
            return "imageChanged"
        case "frame", "frameInScreen", "bounds", "padding", "intrinsicContentSize":
            return "layoutChanged"
        case "text", "hint", "numberOfLines", "maximumLines", "lineBreakMode":
            return "textLayoutChanged"
        case "textAlignment":
            return "alignmentChanged"
        case "tintColor":
            return "tintColorChanged"
        default:
            return "\(semanticName)Changed"
        }
    }
}
