//
//  UIKitScreenInspectionTargetQualityPolicy.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

import AstrolabeCLI

package struct UIKitScreenInspectionTargetQualityPolicy: ScreenInspectionTargetQualityEvaluating {
    package init() {}
    private let excludedClassNames: Set<String> = [
        "CALayer",
        "UIDropShadowView",
        "UILayoutContainerView",
        "UINavigationTransitionView",
        "UITableViewCellContentView",
        "UITransitionView",
        "UIViewControllerWrapperView"
    ]

    private let structuralRoles: Set<NodeSemanticRole> = [
        .list,
        .navigation,
        .scroll,
        .stack,
        .tabBar,
        .web
    ]

    private let systemClassPrefixes = ["_", "CA", "UI"]

    package func isEligible(_ context: ScreenInspectionTargetEligibilityContext) -> Bool {
        guard !context.semanticRoles.contains(.window),
              !excludedClassNames.contains(context.className) else {
            return false
        }
        let isUIKitBackingLayer = context.className.hasSuffix("Layer")
            && (context.className.hasPrefix("_") || context.className.hasPrefix("UI"))
        if isUIKitBackingLayer {
            return false
        }
        if context.className == "UIControl",
           !context.hasText,
           let screenFrame = context.screenFrame,
           context.frame.isNearlyEqual(to: screenFrame) {
            return false
        }
        return true
    }

    package func priority(
        className: String,
        semanticRoles: Set<NodeSemanticRole>,
        reason: ScreenInspectionTargetReason
    ) -> Int {
        guard reason == .visibleNode else {
            return 0
        }
        if !semanticRoles.isDisjoint(with: structuralRoles) {
            return 0
        }
        if !systemClassPrefixes.contains(where: className.hasPrefix) {
            return 1
        }
        if className == "UIView" {
            return 3
        }
        return 2
    }
}
