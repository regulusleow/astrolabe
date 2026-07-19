//
//  AstrolabeRuntimeResponseMapper.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/11.
//

import AstrolabeCLI
import AstrolabeProtocol
import Foundation

struct AstrolabeRuntimeResponseMapper {
    private let valueMapper = RuntimeAttributeValueOutputMapper()

    func hierarchy(
        appID: AstrolabeRuntimeAppID,
        handshake: RuntimeHandshakePayload,
        appInfo: RuntimeApplicationInfoPayload,
        snapshot: RuntimeHierarchySnapshotPayload
    ) -> [String: Any] {
        [
            "appId": appID.rawValue,
            "serverVersion": handshake.runtime.version,
            "snapshotId": snapshot.snapshotID.rawValue,
            "capturedAtUnixTime": snapshot.capturedAtUnixTime,
            "interfaceOrientation": snapshot.orientation,
            "viewport": valueMapper.rect(snapshot.viewport),
            "app": appDictionary(appInfo, runtimeVersion: handshake.runtime.version),
            "displayItems": snapshot.roots.enumerated().map { index, node in
                nodeDictionary(node, depth: 0, siblingIndex: index)
            }
        ]
    }

    func nodeDetail(
        appID: AstrolabeRuntimeAppID,
        requestedNodeID: RuntimeOpaqueIdentifier,
        detail: RuntimeNodeDetailPayload
    ) -> [String: Any] {
        [
            "appId": appID.rawValue,
            "requestedOid": requestedNodeID.rawValue,
            "resolvedOid": detail.nodeID.rawValue,
            "attributeGroups": detail.sections.map(attributeGroup)
        ]
    }

    func attributePatch(appID: AstrolabeRuntimeAppID, patch: RuntimeAttributePatch) -> [String: Any] {
        ["appId": appID.rawValue, "patch": attributePatchDictionary(patch)]
    }

    func attributePatchList(
        appID: AstrolabeRuntimeAppID,
        list: RuntimeAttributePatchListPayload
    ) -> [String: Any] {
        [
            "appId": appID.rawValue,
            "patchCount": list.patches.count,
            "patches": list.patches.map(attributePatchDictionary)
        ]
    }

    func attributePatchRevert(
        appID: AstrolabeRuntimeAppID,
        response: RuntimeRevertAttributePatchPayload
    ) -> [String: Any] {
        [
            "appId": appID.rawValue,
            "revertedPatchId": response.revertedPatchID.rawValue,
            "restoredValue": optionalAttributeValueDictionary(response.restoredValue),
            "remainingPatchCount": response.remainingPatchCount
        ]
    }

    func attributePatchClear(
        appID: AstrolabeRuntimeAppID,
        response: RuntimeClearAttributePatchesPayload
    ) -> [String: Any] {
        [
            "appId": appID.rawValue,
            "revertedPatchIds": response.revertedPatchIDs.map(\.rawValue),
            "remainingPatchCount": response.remainingPatchCount
        ]
    }

    private func appDictionary(
        _ appInfo: RuntimeApplicationInfoPayload,
        runtimeVersion: String
    ) -> [String: Any] {
        var result: [String: Any] = [
            "displayName": appInfo.application.displayName,
            "bundleIdentifier": appInfo.application.identifier,
            "processIdentifier": appInfo.target.processIdentifier ?? "",
            "runtimeVersion": runtimeVersion,
            "device": [
                "name": appInfo.environment.deviceName ?? "",
                "model": appInfo.environment.deviceModel ?? "",
                "systemName": appInfo.environment.platform,
                "systemVersion": appInfo.environment.operatingSystemVersion,
                "idiom": appInfo.environment.deviceCategory,
                "virtualDevice": appInfo.environment.virtualDevice
            ],
            "screen": displayDictionary(appInfo.environment.display)
        ]
        result["version"] = appInfo.application.version
        result["buildVersion"] = appInfo.application.buildVersion
        result["locale"] = appInfo.environment.locale
        return result.compactMapValues { $0 }
    }

    private func displayDictionary(_ display: RuntimeDisplayInfo) -> [String: Any] {
        var result: [String: Any] = [
            "width": display.logicalSize.width,
            "height": display.logicalSize.height,
            "nativeWidth": display.pixelSize.width,
            "nativeHeight": display.pixelSize.height,
            "scaleX": display.logicalToPixelScale.x,
            "scaleY": display.logicalToPixelScale.y,
            "scale": display.logicalToPixelScale.x
        ]
        result["maximumFramesPerSecond"] = display.maximumRefreshRate
        return result.compactMapValues { $0 }
    }

    private func nodeDictionary(
        _ node: RuntimeNode,
        depth: Int,
        siblingIndex: Int
    ) -> [String: Any] {
        let hierarchyVisible = !node.visibility.hidden &&
            !node.visibility.hiddenByAncestor &&
            node.visibility.effectiveOpacity > 0.01
        var result: [String: Any] = [
            "oid": node.nodeID.rawValue,
            "detailOid": node.nodeID.rawValue,
            "className": node.runtimeType.name,
            "classChain": [node.runtimeType.name] + node.runtimeType.ancestors,
            "kind": node.role == "layer" ? "layer" : "view",
            "runtimeRole": node.role,
            "frame": valueMapper.rect(node.geometry.frameInScreen),
            "bounds": valueMapper.rect(node.geometry.bounds),
            "hidden": node.visibility.hidden,
            "inHiddenHierarchy": node.visibility.hiddenByAncestor,
            "alpha": node.visibility.opacity,
            "effectiveAlpha": node.visibility.effectiveOpacity,
            "visible": node.visibility.onscreen,
            "onscreen": node.visibility.onscreen,
            "hierarchyVisible": hierarchyVisible,
            "intersectsViewport": node.visibility.intersectsViewport,
            "fullyClippedByAncestor": node.visibility.fullyClippedByAncestor,
            "clipsToBounds": node.clipsContent,
            "indentLevel": depth,
            "siblingIndex": siblingIndex,
            "supportedDetailCategories": node.availableDetailCategories.map(\.rawValue),
            "interaction": interactionDictionary(node.interaction),
            "extensions": node.extensions.values.mapValues(valueMapper.jsonValue),
            "subitems": node.children.enumerated().map { index, child in
                nodeDictionary(child, depth: depth + 1, siblingIndex: index)
            }
        ]
        result["parentOid"] = node.parentID?.rawValue
        result["frameInParent"] = node.geometry.frameInParent.map(valueMapper.rect)
        if let backgroundColor = node.backgroundColor {
            result["backgroundColor"] = colorComponents(backgroundColor)
        }
        if let text = node.text, !text.isEmpty {
            result["customDisplayTitle"] = text
        }
        result["accessibility"] = node.accessibility.map(accessibilityDictionary)
        return result.compactMapValues { $0 }
    }

    private func accessibilityDictionary(_ accessibility: RuntimeAccessibility) -> [String: Any] {
        var result: [String: Any] = [
            "isElement": accessibility.element,
            "traits": accessibility.traits
        ]
        result["identifier"] = accessibility.identifier
        result["label"] = accessibility.label
        result["value"] = accessibility.value
        result["hint"] = accessibility.hint
        return result.compactMapValues { $0 }
    }

    private func interactionDictionary(_ interaction: RuntimeInteraction) -> [String: Any] {
        var result: [String: Any] = ["interactive": interaction.interactive]
        result["enabled"] = interaction.enabled
        result["selected"] = interaction.selected
        result["focused"] = interaction.focused
        return result.compactMapValues { $0 }
    }

    private func attributeGroup(_ section: RuntimeAttributeSection) -> [String: Any] {
        [
            "identifier": section.category.rawValue,
            "userCustomTitle": section.category.rawValue,
            "sections": [[
                "identifier": "properties",
                "attributes": section.attributes.map(attributeDictionary)
            ]]
        ]
    }

    private func attributeDictionary(_ attribute: RuntimeAttribute) -> [String: Any] {
        let identifier = attribute.identifier.rawValue
            .split(separator: ".")
            .last
            .map(String.init) ?? attribute.identifier.rawValue
        let mappedValue = valueMapper.map(attribute.value)
        return [
            "identifier": identifier,
            "semanticPath": attribute.identifier.rawValue,
            "displayTitle": identifier,
            "attrTypeName": mappedValue.typeName,
            "value": mappedValue.value
        ]
    }

    private func attributePatchDictionary(_ patch: RuntimeAttributePatch) -> [String: Any] {
        [
            "patchId": patch.patchID.rawValue,
            "oid": patch.nodeID.rawValue,
            "attribute": patch.attributeIdentifier.rawValue,
            "originalValue": optionalAttributeValueDictionary(patch.originalValue),
            "requestedValue": attributeValueDictionary(patch.requestedValue),
            "actualValue": optionalAttributeValueDictionary(patch.actualValue),
            "appliedAtUnixTime": patch.appliedAtUnixTime
        ]
    }

    private func optionalAttributeValueDictionary(_ value: RuntimeAttributeValue?) -> Any {
        guard let value else { return NSNull() }
        return attributeValueDictionary(value)
    }

    private func attributeValueDictionary(_ value: RuntimeAttributeValue) -> [String: Any] {
        let mappedValue = valueMapper.map(value)
        return ["type": mappedValue.typeName, "value": mappedValue.value]
    }

    private func colorComponents(_ color: RuntimeColor) -> [Double] {
        [color.red, color.green, color.blue, color.alpha].map { min(1, max(0, $0)) }
    }
}
