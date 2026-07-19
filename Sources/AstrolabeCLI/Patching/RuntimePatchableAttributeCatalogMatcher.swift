//
//  RuntimePatchableAttributeCatalogMatcher.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/13.
//

import AstrolabeProtocol

struct RuntimePatchableAttributeCatalogMatcher {
    private static let placeholder = "<identifier>"

    func attribute(
        identifiedBy identifier: String,
        in catalog: RuntimePatchableAttributesPayload
    ) -> RuntimePatchableAttribute? {
        catalog.attributes.first { attribute in
            matches(identifier, pattern: attribute.attributePattern)
        }
    }

    private func matches(_ identifier: String, pattern: String) -> Bool {
        guard pattern.contains(Self.placeholder) else {
            return identifier == pattern
        }
        let components = pattern.components(separatedBy: Self.placeholder)
        guard components.count == 2,
              let prefix = components.first,
              let suffix = components.last,
              identifier.hasPrefix(prefix),
              identifier.hasSuffix(suffix) else {
            return false
        }
        return identifier.count > prefix.count + suffix.count
    }
}
