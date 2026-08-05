//
//  NodeDetailSummaryBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct NodeDetailSummaryBuilder {
    private let valueFormatter = NodeDetailValueFormatter()
    private let semanticMapper: any NodeDetailAttributeSemanticMapping

    init(
        semanticMapper: any NodeDetailAttributeSemanticMapping =
            PlatformNeutralNodeDetailAttributeSemanticMapper()
    ) {
        self.semanticMapper = semanticMapper
    }

    func buildSummary(
        from detail: [String: Any],
        appId: String,
        filter: String? = nil
    ) -> [String: Any] {
        let attributes = flattenedAttributes(from: detail, appId: appId)
        let filteredAttributes = attributes.filter { attribute in
            matches(attribute: attribute, filter: filter)
        }

        var summary: [String: Any] = [
            "appId": appId,
            "requestedOid": detail["requestedOid"] ?? 0,
            "resolvedOid": detail["resolvedOid"] ?? detail["requestedOid"] ?? 0,
            "attributeCount": filteredAttributes.count,
            "attributes": filteredAttributes
        ]
        let semanticAttributes = semanticAttributes(from: filteredAttributes)
        if !semanticAttributes.isEmpty {
            summary["semanticAttributes"] = semanticAttributes
        }
        return summary
    }

    private func flattenedAttributes(
        from detail: [String: Any],
        appId: String
    ) -> [[String: Any]] {
        guard let groups = detail["attributeGroups"] as? [[String: Any]] else {
            return []
        }

        var result: [[String: Any]] = []
        for group in groups {
            let groupIdentifier = group["identifier"] as? String ?? ""
            let groupTitle = group["userCustomTitle"] as? String ?? ""
            let sections = group["sections"] as? [[String: Any]] ?? []
            for section in sections {
                let sectionIdentifier = section["identifier"] as? String ?? ""
                let attributes = section["attributes"] as? [[String: Any]] ?? []
                for attribute in attributes {
                    result.append(summaryAttribute(
                        attribute,
                        appId: appId,
                        groupIdentifier: groupIdentifier,
                        groupTitle: groupTitle,
                        sectionIdentifier: sectionIdentifier
                    ))
                }
            }
        }
        return result
    }

    private func summaryAttribute(
        _ attribute: [String: Any],
        appId: String,
        groupIdentifier: String,
        groupTitle: String,
        sectionIdentifier: String
    ) -> [String: Any] {
        let identifier = attribute["identifier"] as? String ?? ""
        let path = [groupIdentifier, sectionIdentifier, identifier]
            .filter { !$0.isEmpty }
            .joined(separator: ".")
        let value = attribute["value"] ?? NSNull()
        let attrTypeName = attribute["attrTypeName"] as? String ?? ""

        var result: [String: Any] = [
            "path": path,
            "groupIdentifier": groupIdentifier,
            "sectionIdentifier": sectionIdentifier,
            "identifier": identifier,
            "displayTitle": attribute["displayTitle"] as? String ?? "",
            "attrTypeName": attrTypeName,
            "value": value,
            "valuePreview": valueFormatter.previewString(from: value)
        ]
        if let colorHex = valueFormatter.colorHex(from: value, attrTypeName: attrTypeName) {
            result["colorHex"] = colorHex
        }
        if let colorRGBA = valueFormatter.colorRGBA(from: value, attrTypeName: attrTypeName) {
            result["colorRGBA"] = colorRGBA
        }
        if let semanticPath = attribute["semanticPath"] as? String,
           !semanticPath.isEmpty {
            result["semanticPath"] = semanticPath
        }
        if let semantics = semanticMapper.semantics(
            forIdentifier: identifier,
            appId: appId
        ) {
            result["semanticName"] = semantics.name
            result["semanticPath"] = semantics.path
        }
        if !groupTitle.isEmpty {
            result["groupTitle"] = groupTitle
        }
        if let extraValue = attribute["extraValue"] {
            result["extraValue"] = extraValue
            result["extraValuePreview"] = valueFormatter.previewString(from: extraValue)
        }
        return result
    }

    private func matches(attribute: [String: Any], filter: String?) -> Bool {
        guard let filter, !filter.isEmpty else {
            return true
        }
        let needle = filter.lowercased()
        let haystack = [
            attribute["path"],
            attribute["displayTitle"],
            attribute["attrTypeName"],
            attribute["semanticName"],
            attribute["semanticPath"],
            attribute["valuePreview"],
            attribute["extraValuePreview"]
        ]
            .compactMap { $0 as? String }
            .joined(separator: " ")
            .lowercased()
        return haystack.contains(needle)
    }

    private func semanticAttributes(from attributes: [[String: Any]]) -> [String: [String: Any]] {
        attributes.reduce(into: [String: [String: Any]]()) { result, attribute in
            guard let semanticName = attribute["semanticName"] as? String,
                  result[semanticName] == nil else {
                return
            }
            result[semanticName] = attribute
        }
    }
}
