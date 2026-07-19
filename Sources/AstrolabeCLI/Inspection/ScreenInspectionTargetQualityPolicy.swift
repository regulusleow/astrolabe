//
//  ScreenInspectionTargetQualityPolicy.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

package enum ScreenInspectionTargetReason: String, Hashable {
    case text
    case control
    case image
    case visibleNode
}

package struct ScreenInspectionFrame {
    /// Frame's top-left x coordinate.
    package let x: Double

    /// Frame's top-left y coordinate.
    package let y: Double

    /// Frame width.
    package let width: Double

    /// Frame height.
    package let height: Double

    package func isNearlyEqual(to other: ScreenInspectionFrame, tolerance: Double = 0.5) -> Bool {
        abs(x - other.x) <= tolerance
            && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

package struct ScreenInspectionTargetEligibilityContext {
    /// Concrete class name of the Runtime node.
    package let className: String

    /// Semantic role normalized by the Host from node attributes.
    package let semanticRoles: Set<NodeSemanticRole>

    /// Node frame in screen coordinates.
    package let frame: ScreenInspectionFrame

    /// Current screen frame, or nil when the hierarchy provides no window.
    package let screenFrame: ScreenInspectionFrame?

    /// Whether the node contains displayable text.
    package let hasText: Bool
}

package protocol ScreenInspectionTargetQualityEvaluating {
    func isEligible(_ context: ScreenInspectionTargetEligibilityContext) -> Bool

    func priority(
        className: String,
        semanticRoles: Set<NodeSemanticRole>,
        reason: ScreenInspectionTargetReason
    ) -> Int
}
