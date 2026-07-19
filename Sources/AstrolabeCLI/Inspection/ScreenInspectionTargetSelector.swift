//
//  ScreenInspectionTargetSelector.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/14.
//

import Foundation

struct ScreenInspectionTargetSelector {
    private let extractor: HierarchyNodeExtractor
    private let qualityPolicy: any ScreenInspectionTargetQualityEvaluating
    private let reasonOrder: [ScreenInspectionTargetReason] = [.text, .control, .image, .visibleNode]

    init(
        extractor: HierarchyNodeExtractor = HierarchyNodeExtractor(),
        qualityPolicy: any ScreenInspectionTargetQualityEvaluating
    ) {
        self.extractor = extractor
        self.qualityPolicy = qualityPolicy
    }

    func rankedTargets(from records: [HierarchyNodeRecord]) -> [[String: Any]] {
        let screenFrame = records
            .first { extractor.semanticRoles(from: $0.node).contains(.window) }
            .flatMap { frame(from: $0.node) }
        let candidates = records.compactMap { record in
            targetSnapshot(from: record, screenFrame: screenFrame)
        }
        let deduplicated = deduplicateNestedContent(candidates)
        let grouped = Dictionary(grouping: deduplicated) { target in
            targetReason(from: target)
        }.mapValues { targets in
            regionDiverseOrder(targets, screenFrame: screenFrame)
        }
        var offsets = Dictionary(uniqueKeysWithValues: reasonOrder.map { ($0, 0) })
        var result: [[String: Any]] = []

        while result.count < deduplicated.count {
            var appendedTarget = false
            for reason in reasonOrder {
                let offset = offsets[reason] ?? 0
                guard let targets = grouped[reason], offset < targets.count else {
                    continue
                }
                result.append(targets[offset])
                offsets[reason] = offset + 1
                appendedTarget = true
            }
            if !appendedTarget {
                break
            }
        }
        return result
    }

    private func targetSnapshot(
        from record: HierarchyNodeRecord,
        screenFrame: ScreenInspectionFrame?
    ) -> [String: Any]? {
        let semanticRoles = extractor.semanticRoles(from: record.node)
        let text = extractor.text(from: record.node)
        guard extractor.nodeIdentifier(from: record.node["detailOid"]) != nil,
              let className = record.node["className"] as? String,
              let targetFrame = frame(from: record.node),
              qualityPolicy.isEligible(ScreenInspectionTargetEligibilityContext(
                  className: className,
                  semanticRoles: semanticRoles,
                  frame: targetFrame,
                  screenFrame: screenFrame,
                  hasText: text != nil
              )),
              targetFrame.width > 1,
              targetFrame.height > 1 else {
            return nil
        }
        var snapshot: [String: Any] = [
            "oid": extractor.nodeIdentifier(from: record.node["oid"]) ?? "",
            "detailOid": extractor.nodeIdentifier(from: record.node["detailOid"])
                ?? extractor.nodeIdentifier(from: record.node["oid"])
                ?? "",
            "className": className,
            "frame": record.node["frame"] ?? [:],
            "semanticRoles": semanticRoles.map(\.rawValue).sorted(),
            "reason": reason(
                className: className,
                semanticRoles: semanticRoles,
                hasText: text != nil
            ).rawValue
        ]
        if let text {
            snapshot["text"] = text
        }
        return snapshot
    }

    private func reason(
        className: String,
        semanticRoles: Set<NodeSemanticRole>,
        hasText: Bool
    ) -> ScreenInspectionTargetReason {
        if !semanticRoles.isDisjoint(with: [.button, .control, .input]) {
            return .control
        }
        if !semanticRoles.isDisjoint(with: [.avatar, .image]) {
            return .image
        }
        if hasText || semanticRoles.contains(.text) {
            return .text
        }
        if className.hasSuffix("Button") || className.hasSuffix("Control") {
            return .control
        }
        if className.hasSuffix("ImageView") || className.hasSuffix("Image") {
            return .image
        }
        return .visibleNode
    }

    private func deduplicateNestedContent(_ targets: [[String: Any]]) -> [[String: Any]] {
        targets.reduce(into: []) { result, candidate in
            guard let duplicateIndex = result.firstIndex(where: { existing in
                representsSameVisibleContent(existing, candidate)
            }) else {
                result.append(candidate)
                return
            }
            if semanticPriority(candidate) < semanticPriority(result[duplicateIndex]) {
                result[duplicateIndex] = candidate
            }
        }
    }

    private func representsSameVisibleContent(
        _ lhs: [String: Any],
        _ rhs: [String: Any]
    ) -> Bool {
        guard let lhsFrame = frame(from: lhs),
              let rhsFrame = frame(from: rhs) else {
            return false
        }
        let hasSameText = normalizedText(from: lhs).flatMap { lhsText in
            normalizedText(from: rhs).map { rhsText in lhsText == rhsText }
        } ?? false
        if hasSameText && framesIntersect(lhsFrame, rhsFrame) {
            return true
        }
        let reasons = Set([targetReason(from: lhs), targetReason(from: rhs)])
        return reasons == [.control, .image] && framesNearlyEqual(lhsFrame, rhsFrame)
    }

    private func regionDiverseOrder(
        _ targets: [[String: Any]],
        screenFrame: ScreenInspectionFrame?
    ) -> [[String: Any]] {
        guard let screenFrame, screenFrame.height > 0 else {
            return targets.sorted(by: isHigherQualityOnScreen)
        }
        let grouped = Dictionary(grouping: targets) { target in
            verticalRegion(for: target, screenFrame: screenFrame)
        }.mapValues { $0.sorted(by: isHigherQualityOnScreen) }
        var offsets = [0: 0, 1: 0, 2: 0]
        var result: [[String: Any]] = []
        while result.count < targets.count {
            var appendedTarget = false
            for region in 0...2 {
                let offset = offsets[region] ?? 0
                guard let regionTargets = grouped[region], offset < regionTargets.count else {
                    continue
                }
                result.append(regionTargets[offset])
                offsets[region] = offset + 1
                appendedTarget = true
            }
            if !appendedTarget {
                break
            }
        }
        return result
    }

    private func verticalRegion(for target: [String: Any], screenFrame: ScreenInspectionFrame) -> Int {
        guard let targetFrame = frame(from: target) else {
            return 0
        }
        let relativeCenterY = (targetFrame.y + targetFrame.height / 2 - screenFrame.y) / screenFrame.height
        if relativeCenterY < 1.0 / 3.0 {
            return 0
        }
        if relativeCenterY < 2.0 / 3.0 {
            return 1
        }
        return 2
    }

    private func isBeforeOnScreen(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        guard let lhsFrame = frame(from: lhs) else {
            return false
        }
        guard let rhsFrame = frame(from: rhs) else {
            return true
        }
        if lhsFrame.y != rhsFrame.y {
            return lhsFrame.y < rhsFrame.y
        }
        return lhsFrame.x < rhsFrame.x
    }

    private func isHigherQualityOnScreen(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        let lhsPriority = qualityPriority(for: lhs)
        let rhsPriority = qualityPriority(for: rhs)
        if lhsPriority != rhsPriority {
            return lhsPriority < rhsPriority
        }
        return isBeforeOnScreen(lhs, rhs)
    }

    private func qualityPriority(for target: [String: Any]) -> Int {
        let semanticRoles = Set(
            (target["semanticRoles"] as? [String] ?? []).compactMap(NodeSemanticRole.init(rawValue:))
        )
        return qualityPolicy.priority(
            className: target["className"] as? String ?? "",
            semanticRoles: semanticRoles,
            reason: targetReason(from: target)
        )
    }

    private func semanticPriority(_ target: [String: Any]) -> Int {
        switch targetReason(from: target) {
        case .control:
            return 0
        case .image:
            return 1
        case .text:
            return 2
        case .visibleNode:
            return 3
        }
    }

    private func targetReason(from target: [String: Any]) -> ScreenInspectionTargetReason {
        guard let rawValue = target["reason"] as? String,
              let reason = ScreenInspectionTargetReason(rawValue: rawValue) else {
            return .visibleNode
        }
        return reason
    }

    private func normalizedText(from target: [String: Any]) -> String? {
        guard let text = target["text"] as? String else {
            return nil
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func frame(from node: [String: Any]) -> ScreenInspectionFrame? {
        guard let value = node["frame"] as? [String: Any],
              let x = extractor.numericValue(from: value["x"]),
              let y = extractor.numericValue(from: value["y"]),
              let width = extractor.numericValue(from: value["width"]),
              let height = extractor.numericValue(from: value["height"]) else {
            return nil
        }
        return ScreenInspectionFrame(x: x, y: y, width: width, height: height)
    }

    private func framesIntersect(_ lhs: ScreenInspectionFrame, _ rhs: ScreenInspectionFrame) -> Bool {
        lhs.x < rhs.x + rhs.width
            && rhs.x < lhs.x + lhs.width
            && lhs.y < rhs.y + rhs.height
            && rhs.y < lhs.y + lhs.height
    }

    private func framesNearlyEqual(_ lhs: ScreenInspectionFrame, _ rhs: ScreenInspectionFrame) -> Bool {
        lhs.isNearlyEqual(to: rhs)
    }
}
