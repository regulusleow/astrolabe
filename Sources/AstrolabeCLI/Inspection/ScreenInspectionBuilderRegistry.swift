//
//  ScreenInspectionBuilderRegistry.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

struct ScreenInspectionBuilderRegistry {
    private let builders: [RuntimeUIPlatform: ScreenInspectionBuilder]

    init(builders: [RuntimeUIPlatform: ScreenInspectionBuilder]) {
        self.builders = builders
    }

    func builder(for platform: RuntimeUIPlatform) throws -> ScreenInspectionBuilder {
        guard let builder = builders[platform] else {
            throw CLIError.commandFailed("No screen-inspection strategy is configured for platform \(platform.rawValue)")
        }
        return builder
    }
}
