//
//  AttributePatchCommandGroup.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/13.
//

import Foundation

struct AttributePatchCommandGroup: CLICommandHandling {
    let supportedCommands = [
        "list-patchable-attributes",
        "apply-attribute-patch",
        "list-attribute-patches",
        "revert-attribute-patch",
        "clear-attribute-patches"
    ]

    private let service: any RuntimeUIPatchCatalogProviding & RuntimeUIAttributePatching
    private let parser: AttributePatchCommandParser
    private let catalogMatcher: RuntimePatchableAttributeCatalogMatcher
    private let mapper: RuntimePatchableAttributeCatalogMapper

    init(
        service: any RuntimeUIPatchCatalogProviding & RuntimeUIAttributePatching,
        parser: AttributePatchCommandParser = AttributePatchCommandParser(),
        catalogMatcher: RuntimePatchableAttributeCatalogMatcher =
            RuntimePatchableAttributeCatalogMatcher(),
        mapper: RuntimePatchableAttributeCatalogMapper = RuntimePatchableAttributeCatalogMapper()
    ) {
        self.service = service
        self.parser = parser
        self.catalogMatcher = catalogMatcher
        self.mapper = mapper
    }

    func run(command: String, arguments: [String]) throws -> CLICommandOutput {
        switch command {
        case "list-patchable-attributes":
            return try listPatchable(arguments: arguments)
        case "apply-attribute-patch":
            return try apply(arguments: arguments)
        case "list-attribute-patches":
            return try list(arguments: arguments)
        case "revert-attribute-patch":
            return try revert(arguments: arguments)
        case "clear-attribute-patches":
            return try clear(arguments: arguments)
        default:
            throw CLIError.unsupportedCommand(command)
        }
    }

    private func apply(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let command = try parser.parseApply(
            arguments: Array(arguments.dropFirst(2))
        )
        let catalog = try service.fetchPatchableAttributeCatalog(
            appId: arguments[1]
        )
        guard let attribute = catalogMatcher.attribute(
            identifiedBy: command.attributeIdentifier,
            in: catalog
        ) else {
            throw CLIError.invalidArgument(
                "The Runtime does not support temporary mutation of attribute: \(command.attributeIdentifier)"
            )
        }
        let result = try service.applyAttributePatch(
            appId: arguments[1],
            oid: command.oid,
            attributeIdentifier: command.attributeIdentifier,
            value: try RuntimeAttributePatchValueParser().parse(
                command.rawValue,
                for: attribute
            )
        )
        return CLICommandResponse.success(
            command: "apply-attribute-patch",
            data: result
        )
    }

    private func listPatchable(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let appId = arguments[1]
        let catalog = try service.fetchPatchableAttributeCatalog(appId: appId)
        return CLICommandResponse.success(
            command: "list-patchable-attributes",
            data: mapper.patchableAttributes(
                appID: appId,
                catalog: catalog
            )
        )
    }

    private func list(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        return CLICommandResponse.success(
            command: "list-attribute-patches",
            data: try service.fetchAttributePatches(appId: arguments[1])
        )
    }

    private func revert(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        let patchID = try parser.parsePatchID(arguments.count > 2 ? arguments[2] : nil)
        return CLICommandResponse.success(
            command: "revert-attribute-patch",
            data: try service.revertAttributePatch(
                appId: arguments[1],
                patchID: patchID
            )
        )
    }

    private func clear(arguments: [String]) throws -> CLICommandOutput {
        guard arguments.count >= 2 else {
            throw CLIError.missingArgument("appId")
        }
        return CLICommandResponse.success(
            command: "clear-attribute-patches",
            data: try service.clearAttributePatches(appId: arguments[1])
        )
    }
}
