//
//  HierarchyProjectionBuilder.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/13.
//

import Foundation

struct HierarchyProjectionOptions {
    /// Maximum number of nodes returned in the hierarchy; nil disables count-based truncation.
    let nodeLimit: Int?

    /// Maximum hierarchy depth, where the root is depth 0; nil disables depth-based truncation.
    let maxDepth: Int?
}

struct HierarchyProjectionBuilder {
    private let extractor: HierarchyNodeExtractor

    init(extractor: HierarchyNodeExtractor = HierarchyNodeExtractor()) {
        self.extractor = extractor
    }

    func buildProjection(
        from hierarchy: [String: Any],
        options: HierarchyProjectionOptions
    ) -> [String: Any] {
        let nodeCount = extractor.collectNodeRecords(in: hierarchy).count
        var returnedNodeCount = 0
        var result = hierarchy
        result["displayItems"] = projectNodes(
            hierarchy["displayItems"],
            depth: 0,
            options: options,
            returnedNodeCount: &returnedNodeCount
        )
        result["nodeCount"] = nodeCount
        result["returnedNodeCount"] = returnedNodeCount
        result["omittedNodeCount"] = max(0, nodeCount - returnedNodeCount)
        result["truncated"] = returnedNodeCount < nodeCount
        if let nodeLimit = options.nodeLimit {
            result["nodeLimit"] = nodeLimit
        }
        if let maxDepth = options.maxDepth {
            result["maxDepth"] = maxDepth
        }
        return result
    }

    private func projectNodes(
        _ value: Any?,
        depth: Int,
        options: HierarchyProjectionOptions,
        returnedNodeCount: inout Int
    ) -> [[String: Any]] {
        guard let nodes = value as? [[String: Any]],
              options.maxDepth.map({ depth <= $0 }) ?? true else {
            return []
        }

        var projectedNodes = [[String: Any]]()
        for node in nodes {
            if let nodeLimit = options.nodeLimit,
               returnedNodeCount >= nodeLimit {
                break
            }

            var projectedNode = node
            returnedNodeCount += 1
            let children = projectNodes(
                node["subitems"],
                depth: depth + 1,
                options: options,
                returnedNodeCount: &returnedNodeCount
            )
            if children.isEmpty {
                projectedNode.removeValue(forKey: "subitems")
            } else {
                projectedNode["subitems"] = children
            }
            projectedNodes.append(projectedNode)
        }
        return projectedNodes
    }
}
