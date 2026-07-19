//
//  UIKitNodeDetailAttributeSemanticMapper.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeCLI

package struct UIKitNodeDetailAttributeSemanticMapper:
    NodeDetailAttributeSemanticMapping {
    private let semanticsByIdentifier: [String: NodeDetailAttributeSemantics] = [
        "l_f_f": NodeDetailAttributeSemantics(name: "frame", path: "layout.frame"),
        "frame": NodeDetailAttributeSemantics(name: "frame", path: "layout.frame"),
        "l_b_b": NodeDetailAttributeSemantics(name: "bounds", path: "layout.bounds"),
        "bounds": NodeDetailAttributeSemantics(name: "bounds", path: "layout.bounds"),
        "l_s_s": NodeDetailAttributeSemantics(name: "safeAreaInsets", path: "layout.safeAreaInsets"),
        "safeAreaInsets": NodeDetailAttributeSemantics(name: "safeAreaInsets", path: "layout.safeAreaInsets"),
        "l_p_p": NodeDetailAttributeSemantics(name: "position", path: "layout.position"),
        "position": NodeDetailAttributeSemantics(name: "position", path: "layout.position"),
        "l_a_a": NodeDetailAttributeSemantics(name: "anchorPoint", path: "layout.anchorPoint"),
        "anchorPoint": NodeDetailAttributeSemantics(name: "anchorPoint", path: "layout.anchorPoint"),
        "al_h_h": NodeDetailAttributeSemantics(name: "horizontalContentHuggingPriority", path: "autoLayout.horizontalContentHuggingPriority"),
        "horizontalContentHuggingPriority": NodeDetailAttributeSemantics(name: "horizontalContentHuggingPriority", path: "autoLayout.horizontalContentHuggingPriority"),
        "al_h_v": NodeDetailAttributeSemantics(name: "verticalContentHuggingPriority", path: "autoLayout.verticalContentHuggingPriority"),
        "verticalContentHuggingPriority": NodeDetailAttributeSemantics(name: "verticalContentHuggingPriority", path: "autoLayout.verticalContentHuggingPriority"),
        "al_r_h": NodeDetailAttributeSemantics(name: "horizontalCompressionResistancePriority", path: "autoLayout.horizontalCompressionResistancePriority"),
        "horizontalCompressionResistancePriority": NodeDetailAttributeSemantics(name: "horizontalCompressionResistancePriority", path: "autoLayout.horizontalCompressionResistancePriority"),
        "al_r_v": NodeDetailAttributeSemantics(name: "verticalCompressionResistancePriority", path: "autoLayout.verticalCompressionResistancePriority"),
        "verticalCompressionResistancePriority": NodeDetailAttributeSemantics(name: "verticalCompressionResistancePriority", path: "autoLayout.verticalCompressionResistancePriority"),
        "al_c_c": NodeDetailAttributeSemantics(name: "constraints", path: "autoLayout.constraints"),
        "constraints": NodeDetailAttributeSemantics(name: "constraints", path: "autoLayout.constraints"),
        "cl_i_s": NodeDetailAttributeSemantics(name: "intrinsicContentSize", path: "layout.intrinsicContentSize"),
        "intrinsicContentSize": NodeDetailAttributeSemantics(name: "intrinsicContentSize", path: "layout.intrinsicContentSize"),
        "vl_v_h": NodeDetailAttributeSemantics(name: "hidden", path: "view.hidden"),
        "hidden": NodeDetailAttributeSemantics(name: "hidden", path: "view.hidden"),
        "vl_v_o": NodeDetailAttributeSemantics(name: "opacity", path: "layer.opacity"),
        "opacity": NodeDetailAttributeSemantics(name: "opacity", path: "layer.opacity"),
        "alpha": NodeDetailAttributeSemantics(name: "opacity", path: "view.alpha"),
        "vl_i_i": NodeDetailAttributeSemantics(name: "userInteractionEnabled", path: "view.userInteractionEnabled"),
        "userInteractionEnabled": NodeDetailAttributeSemantics(name: "userInteractionEnabled", path: "view.userInteractionEnabled"),
        "vl_i_m": NodeDetailAttributeSemantics(name: "masksToBounds", path: "layer.masksToBounds"),
        "masksToBounds": NodeDetailAttributeSemantics(name: "masksToBounds", path: "layer.masksToBounds"),
        "vl_c_r": NodeDetailAttributeSemantics(name: "cornerRadius", path: "layer.cornerRadius"),
        "cornerRadius": NodeDetailAttributeSemantics(name: "cornerRadius", path: "layer.cornerRadius"),
        "vl_b_b": NodeDetailAttributeSemantics(name: "backgroundColor", path: "view.backgroundColor"),
        "backgroundColor": NodeDetailAttributeSemantics(name: "backgroundColor", path: "view.backgroundColor"),
        "vl_b_c": NodeDetailAttributeSemantics(name: "borderColor", path: "layer.borderColor"),
        "borderColor": NodeDetailAttributeSemantics(name: "borderColor", path: "layer.borderColor"),
        "vl_b_w": NodeDetailAttributeSemantics(name: "borderWidth", path: "layer.borderWidth"),
        "borderWidth": NodeDetailAttributeSemantics(name: "borderWidth", path: "layer.borderWidth"),
        "vl_s_c": NodeDetailAttributeSemantics(name: "shadowColor", path: "layer.shadowColor"),
        "shadowColor": NodeDetailAttributeSemantics(name: "shadowColor", path: "layer.shadowColor"),
        "vl_s_o": NodeDetailAttributeSemantics(name: "shadowOpacity", path: "layer.shadowOpacity"),
        "shadowOpacity": NodeDetailAttributeSemantics(name: "shadowOpacity", path: "layer.shadowOpacity"),
        "vl_s_r": NodeDetailAttributeSemantics(name: "shadowRadius", path: "layer.shadowRadius"),
        "shadowRadius": NodeDetailAttributeSemantics(name: "shadowRadius", path: "layer.shadowRadius"),
        "vl_s_ow": NodeDetailAttributeSemantics(name: "shadowOffsetWidth", path: "layer.shadowOffsetWidth"),
        "shadowOffsetWidth": NodeDetailAttributeSemantics(name: "shadowOffsetWidth", path: "layer.shadowOffsetWidth"),
        "vl_s_oh": NodeDetailAttributeSemantics(name: "shadowOffsetHeight", path: "layer.shadowOffsetHeight"),
        "shadowOffsetHeight": NodeDetailAttributeSemantics(name: "shadowOffsetHeight", path: "layer.shadowOffsetHeight"),
        "vl_c_m": NodeDetailAttributeSemantics(name: "contentMode", path: "view.contentMode"),
        "contentMode": NodeDetailAttributeSemantics(name: "contentMode", path: "view.contentMode"),
        "vl_t_c": NodeDetailAttributeSemantics(name: "tintColor", path: "view.tintColor"),
        "tintColor": NodeDetailAttributeSemantics(name: "tintColor", path: "view.tintColor"),
        "vl_t_m": NodeDetailAttributeSemantics(name: "tintAdjustmentMode", path: "view.tintAdjustmentMode"),
        "tintAdjustmentMode": NodeDetailAttributeSemantics(name: "tintAdjustmentMode", path: "view.tintAdjustmentMode"),
        "vl_t_t": NodeDetailAttributeSemantics(name: "tag", path: "view.tag"),
        "tag": NodeDetailAttributeSemantics(name: "tag", path: "view.tag"),
        "iv_n_n": NodeDetailAttributeSemantics(name: "imageName", path: "imageView.imageName"),
        "imageName": NodeDetailAttributeSemantics(name: "imageName", path: "imageView.imageName"),
        "iv_o_o": NodeDetailAttributeSemantics(name: "imagePreview", path: "imageView.imagePreview"),
        "imagePreview": NodeDetailAttributeSemantics(name: "imagePreview", path: "imageView.imagePreview"),
        "lb_t_t": NodeDetailAttributeSemantics(name: "text", path: "label.text"),
        "text": NodeDetailAttributeSemantics(name: "text", path: "label.text"),
        "lb_f_n": NodeDetailAttributeSemantics(name: "fontName", path: "label.fontName"),
        "fontName": NodeDetailAttributeSemantics(name: "fontName", path: "label.fontName"),
        "lb_f_s": NodeDetailAttributeSemantics(name: "fontSize", path: "label.fontSize"),
        "fontSize": NodeDetailAttributeSemantics(name: "fontSize", path: "label.fontSize"),
        "lb_n_n": NodeDetailAttributeSemantics(name: "numberOfLines", path: "label.numberOfLines"),
        "numberOfLines": NodeDetailAttributeSemantics(name: "numberOfLines", path: "label.numberOfLines"),
        "lb_t_c": NodeDetailAttributeSemantics(name: "textColor", path: "label.textColor"),
        "textColor": NodeDetailAttributeSemantics(name: "textColor", path: "label.textColor"),
        "lb_a_a": NodeDetailAttributeSemantics(name: "textAlignment", path: "label.textAlignment"),
        "textAlignment": NodeDetailAttributeSemantics(name: "textAlignment", path: "label.textAlignment"),
        "lb_b_m": NodeDetailAttributeSemantics(name: "lineBreakMode", path: "label.lineBreakMode"),
        "lineBreakMode": NodeDetailAttributeSemantics(name: "lineBreakMode", path: "label.lineBreakMode"),
        "lb_c_c": NodeDetailAttributeSemantics(name: "adjustsFontSizeToFitWidth", path: "label.adjustsFontSizeToFitWidth"),
        "adjustsFontSizeToFitWidth": NodeDetailAttributeSemantics(name: "adjustsFontSizeToFitWidth", path: "label.adjustsFontSizeToFitWidth"),
        "attributedTextRuns": NodeDetailAttributeSemantics(name: "attributedTextRuns", path: "label.attributedTextRuns"),
        "ct_e_e": NodeDetailAttributeSemantics(name: "enabled", path: "control.enabled"),
        "enabled": NodeDetailAttributeSemantics(name: "enabled", path: "control.enabled"),
        "ct_e_s": NodeDetailAttributeSemantics(name: "selected", path: "control.selected"),
        "selected": NodeDetailAttributeSemantics(name: "selected", path: "control.selected"),
        "ct_v_a": NodeDetailAttributeSemantics(name: "verticalAlignment", path: "control.verticalAlignment"),
        "verticalAlignment": NodeDetailAttributeSemantics(name: "verticalAlignment", path: "control.verticalAlignment"),
        "ct_h_a": NodeDetailAttributeSemantics(name: "horizontalAlignment", path: "control.horizontalAlignment"),
        "horizontalAlignment": NodeDetailAttributeSemantics(name: "horizontalAlignment", path: "control.horizontalAlignment"),
        "ct_o_e": NodeDetailAttributeSemantics(name: "outsideEdge", path: "control.outsideEdge"),
        "outsideEdge": NodeDetailAttributeSemantics(name: "outsideEdge", path: "control.outsideEdge"),
        "bt_c_i": NodeDetailAttributeSemantics(name: "contentInsets", path: "button.contentInsets"),
        "contentInsets": NodeDetailAttributeSemantics(name: "contentInsets", path: "button.contentInsets"),
        "bt_t_i": NodeDetailAttributeSemantics(name: "titleInsets", path: "button.titleInsets"),
        "titleInsets": NodeDetailAttributeSemantics(name: "titleInsets", path: "button.titleInsets"),
        "bt_i_i": NodeDetailAttributeSemantics(name: "imageInsets", path: "button.imageInsets"),
        "imageInsets": NodeDetailAttributeSemantics(name: "imageInsets", path: "button.imageInsets")
    ]

    package init() {}

    package func semantics(
        forIdentifier identifier: String,
        appId: String
    ) -> NodeDetailAttributeSemantics? {
        semanticsByIdentifier[identifier]
    }
}
