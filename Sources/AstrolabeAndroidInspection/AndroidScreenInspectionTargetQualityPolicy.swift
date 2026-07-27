//
//  AndroidScreenInspectionTargetQualityPolicy.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeCLI

package struct AndroidScreenInspectionTargetQualityPolicy:
    ScreenInspectionTargetQualityEvaluating {
    private let excludedClassSuffixes = ["decorview", "viewrootimpl", "viewstub"]
    private let structuralRoles: Set<NodeSemanticRole> = [
        .list,
        .navigation,
        .scroll,
        .tabBar,
        .web
    ]

    package init() {}

    package func isEligible(_ context: ScreenInspectionTargetEligibilityContext) -> Bool {
        if context.semanticRoles.contains(.window) {
            return false
        }
        let className = context.className.lowercased()
        if excludedClassSuffixes.contains(where: className.hasSuffix) {
            return false
        }
        if className == "android.view.view",
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
        if reason != .visibleNode || !semanticRoles.isDisjoint(with: structuralRoles) {
            return 0
        }
        if !isFrameworkClass(className) {
            return 1
        }
        if className == "android.view.View" {
            return 3
        }
        return 2
    }

    private func isFrameworkClass(_ className: String) -> Bool {
        className.hasPrefix("android.")
            || className.hasPrefix("androidx.")
            || className.hasPrefix("com.google.android.")
    }
}
