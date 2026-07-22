//
//  AndroidNodeDetailAttributeSemanticMapper.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeCLI

package struct AndroidNodeDetailAttributeSemanticMapper:
    NodeDetailAttributeSemanticMapping {
    private let semanticsByIdentifier: [String: NodeDetailAttributeSemantics] = [
        "android.view.runtimeType": .init(name: "runtimeType", path: "view.runtimeType"),
        "android.view.classChain": .init(name: "classChain", path: "view.classChain"),
        "android.view.resourceName": .init(name: "resourceName", path: "view.resourceName"),
        "android.view.resourceID": .init(name: "resourceID", path: "view.resourceID"),
        "android.view.bounds": .init(name: "bounds", path: "layout.bounds"),
        "android.view.frameInParent": .init(name: "frame", path: "layout.frame"),
        "android.view.frameInScreen": .init(name: "frameInScreen", path: "layout.frameInScreen"),
        "android.view.padding": .init(name: "padding", path: "layout.padding"),
        "android.view.visibility": .init(name: "visibility", path: "view.visibility"),
        "android.view.hidden": .init(name: "hidden", path: "view.hidden"),
        "android.view.hiddenByAncestor": .init(
            name: "hiddenByAncestor",
            path: "view.hiddenByAncestor"
        ),
        "android.view.alpha": .init(name: "opacity", path: "view.alpha"),
        "android.view.effectiveAlpha": .init(
            name: "effectiveOpacity",
            path: "view.effectiveAlpha"
        ),
        "android.view.onscreen": .init(name: "onscreen", path: "view.onscreen"),
        "android.view.backgroundColor": .init(
            name: "backgroundColor",
            path: "view.backgroundColor"
        ),
        "android.view.enabled": .init(name: "enabled", path: "view.enabled"),
        "android.view.clickable": .init(name: "clickable", path: "view.clickable"),
        "android.view.longClickable": .init(
            name: "longClickable",
            path: "view.longClickable"
        ),
        "android.view.focusable": .init(name: "focusable", path: "view.focusable"),
        "android.view.selected": .init(name: "selected", path: "view.selected"),
        "android.view.activated": .init(name: "activated", path: "view.activated"),
        "android.text.text": .init(name: "text", path: "text.text"),
        "android.text.hint": .init(name: "hint", path: "text.hint"),
        "android.text.fontSize": .init(name: "fontSize", path: "text.fontSize"),
        "android.text.color": .init(name: "textColor", path: "text.textColor"),
        "android.text.typefaceStyle": .init(
            name: "typefaceStyle",
            path: "text.typefaceStyle"
        ),
        "android.text.typefaceWeight": .init(
            name: "typefaceWeight",
            path: "text.typefaceWeight"
        ),
        "android.text.lineCount": .init(name: "numberOfLines", path: "text.numberOfLines"),
        "android.text.maxLines": .init(name: "maximumLines", path: "text.maximumLines"),
        "android.text.gravity": .init(name: "textAlignment", path: "text.gravity"),
        "android.text.ellipsize": .init(name: "lineBreakMode", path: "text.ellipsize"),
        "android.text.letterSpacing": .init(name: "letterSpacing", path: "text.letterSpacing"),
        "android.text.includeFontPadding": .init(
            name: "includeFontPadding",
            path: "text.includeFontPadding"
        ),
        "android.textInput.inputType": .init(name: "inputType", path: "textInput.inputType"),
        "android.textInput.imeOptions": .init(name: "imeOptions", path: "textInput.imeOptions"),
        "android.textInput.singleLine": .init(
            name: "singleLine",
            path: "textInput.singleLine"
        ),
        "android.textInput.cursorVisible": .init(
            name: "cursorVisible",
            path: "textInput.cursorVisible"
        ),
        "android.textInput.selectionStart": .init(
            name: "selectionStart",
            path: "textInput.selectionStart"
        ),
        "android.textInput.selectionEnd": .init(
            name: "selectionEnd",
            path: "textInput.selectionEnd"
        ),
        "android.image.present": .init(name: "imagePresent", path: "image.present"),
        "android.image.scaleType": .init(name: "scaleType", path: "image.scaleType"),
        "android.image.drawableType": .init(name: "imageType", path: "image.drawableType"),
        "android.image.intrinsicSize": .init(
            name: "intrinsicContentSize",
            path: "image.intrinsicSize"
        ),
        "android.image.tintColor": .init(name: "tintColor", path: "image.tintColor"),
        "android.control.enabled": .init(name: "enabled", path: "control.enabled"),
        "android.control.selected": .init(name: "selected", path: "control.selected"),
        "android.control.activated": .init(name: "activated", path: "control.activated"),
        "android.control.checked": .init(name: "checked", path: "control.checked"),
        "android.scroll.offsetX": .init(name: "contentOffsetX", path: "scroll.offsetX"),
        "android.scroll.offsetY": .init(name: "contentOffsetY", path: "scroll.offsetY"),
        "android.scroll.canScrollLeft": .init(
            name: "canScrollLeft",
            path: "scroll.canScrollLeft"
        ),
        "android.scroll.canScrollRight": .init(
            name: "canScrollRight",
            path: "scroll.canScrollRight"
        ),
        "android.scroll.canScrollUp": .init(
            name: "canScrollUp",
            path: "scroll.canScrollUp"
        ),
        "android.scroll.canScrollDown": .init(
            name: "canScrollDown",
            path: "scroll.canScrollDown"
        ),
        "android.accessibility.contentDescription": .init(
            name: "accessibilityLabel",
            path: "accessibility.contentDescription"
        ),
        "android.accessibility.importance": .init(
            name: "accessibilityImportance",
            path: "accessibility.importance"
        ),
        "android.accessibility.heading": .init(
            name: "accessibilityHeading",
            path: "accessibility.heading"
        ),
        "android.accessibility.tooltip": .init(
            name: "accessibilityHint",
            path: "accessibility.tooltip"
        ),
        "android.accessibility.stateDescription": .init(
            name: "accessibilityValue",
            path: "accessibility.stateDescription"
        )
    ]

    package init() {}

    package func semantics(
        forIdentifier identifier: String,
        appId: String
    ) -> NodeDetailAttributeSemantics? {
        semanticsByIdentifier[identifier]
    }
}
