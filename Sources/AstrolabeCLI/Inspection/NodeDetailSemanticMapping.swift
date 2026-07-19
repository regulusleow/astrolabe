//
//  NodeDetailSemanticMapping.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

package struct NodeDetailAttributeSemantics {
    /// Short semantic name suitable for AI and CLI input.
    package let name: String

    /// Full semantic path with control or hierarchy context.
    package let path: String

    package init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

package protocol NodeDetailAttributeSemanticMapping {
    func semantics(
        forIdentifier identifier: String,
        appId: String
    ) -> NodeDetailAttributeSemantics?
}

package protocol NodeDetailSemanticIssueInterpreting {
    func issueName(for semanticName: String, appId: String) -> String
}

struct PlatformNeutralNodeDetailAttributeSemanticMapper:
    NodeDetailAttributeSemanticMapping {
    func semantics(
        forIdentifier identifier: String,
        appId: String
    ) -> NodeDetailAttributeSemantics? {
        nil
    }
}

struct PlatformNeutralNodeDetailSemanticIssueInterpreter:
    NodeDetailSemanticIssueInterpreting {
    func issueName(for semanticName: String, appId: String) -> String {
        "\(semanticName)Changed"
    }
}
