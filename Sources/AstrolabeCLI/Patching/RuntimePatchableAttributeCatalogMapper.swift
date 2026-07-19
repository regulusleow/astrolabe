//
//  RuntimePatchableAttributeCatalogMapper.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

import AstrolabeProtocol
import Foundation

struct RuntimePatchableAttributeCatalogMapper {
    private let valueMapper = RuntimeAttributeValueOutputMapper()

    func patchableAttributes(
        appID: String,
        catalog: RuntimePatchableAttributesPayload
    ) -> [String: Any] {
        [
            "appId": appID,
            "attributeCount": catalog.attributes.count,
            "attributes": catalog.attributes.map(attributeDictionary)
        ]
    }

    private func attributeDictionary(
        _ attribute: RuntimePatchableAttribute
    ) -> [String: Any] {
        var result: [String: Any] = [
            "attributePattern": attribute.attributePattern,
            "valueType": attribute.valueType.rawValue,
            "targetRoles": attribute.targetRoles
        ]
        if let constraints = attribute.valueConstraints {
            var valueConstraints = [String: Any]()
            valueConstraints["minimum"] = constraints.minimum
            valueConstraints["maximum"] = constraints.maximum
            if constraints.minimumExclusive {
                valueConstraints["minimumExclusive"] = true
            }
            if constraints.maximumExclusive {
                valueConstraints["maximumExclusive"] = true
            }
            if !constraints.acceptedFormats.isEmpty {
                valueConstraints["acceptedFormats"] = constraints.acceptedFormats
            }
            if !constraints.allowedValues.isEmpty {
                valueConstraints["allowedValues"] = constraints.allowedValues.map { value in
                    let mapped = valueMapper.map(value)
                    return ["type": mapped.typeName, "value": mapped.value]
                }
            }
            let compactConstraints = valueConstraints.compactMapValues { $0 }
            if !compactConstraints.isEmpty {
                result["valueConstraints"] = compactConstraints
            }
        }
        return result
    }
}
