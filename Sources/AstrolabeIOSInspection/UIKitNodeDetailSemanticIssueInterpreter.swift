//
//  UIKitNodeDetailSemanticIssueInterpreter.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeCLI

package struct UIKitNodeDetailSemanticIssueInterpreter:
    NodeDetailSemanticIssueInterpreting {
    package init() {}

    package func issueName(for semanticName: String, appId: String) -> String {
        switch semanticName {
        case "fontSize":
            return "fontSizeChanged"
        case "fontName":
            return "fontNameChanged"
        case "textColor":
            return "textColorChanged"
        case "backgroundColor":
            return "backgroundColorChanged"
        case "cornerRadius":
            return "cornerRadiusChanged"
        case "hidden":
            return "visibilityChanged"
        case "opacity":
            return "opacityChanged"
        case "enabled", "selected":
            return "controlStateChanged"
        case "userInteractionEnabled":
            return "interactionChanged"
        case "contentMode":
            return "contentModeChanged"
        case "imageName", "imagePreview":
            return "imageChanged"
        case "contentInsets", "titleInsets", "imageInsets", "safeAreaInsets", "intrinsicContentSize":
            return "layoutInsetChanged"
        case "horizontalAlignment", "verticalAlignment", "textAlignment":
            return "alignmentChanged"
        case "horizontalContentHuggingPriority",
             "verticalContentHuggingPriority",
             "horizontalCompressionResistancePriority",
             "verticalCompressionResistancePriority",
             "constraints":
            return "autoLayoutChanged"
        case "frame", "bounds", "position", "anchorPoint":
            return "layoutChanged"
        case "text", "numberOfLines", "lineBreakMode", "adjustsFontSizeToFitWidth":
            return "textLayoutChanged"
        case "attributedTextRuns":
            return "attributedTextStyleChanged"
        case "tag":
            return "tagChanged"
        case "masksToBounds":
            return "clippingChanged"
        case "tintColor":
            return "tintColorChanged"
        case "tintAdjustmentMode":
            return "tintAdjustmentModeChanged"
        case "outsideEdge":
            return "outsideEdgeChanged"
        default:
            if semanticName.hasPrefix("border") {
                return "borderChanged"
            }
            if semanticName.hasPrefix("shadow") {
                return "shadowChanged"
            }
            return "\(semanticName)Changed"
        }
    }
}
