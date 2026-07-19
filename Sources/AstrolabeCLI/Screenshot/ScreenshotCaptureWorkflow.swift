//
//  ScreenshotCaptureWorkflow.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct ScreenshotCaptureWorkflow {
    private let service: any RuntimeUIHierarchyCapturing
    private let screenshotProvider: ScreenshotProviding

    init(
        service: any RuntimeUIHierarchyCapturing,
        screenshotProvider: ScreenshotProviding
    ) {
        self.service = service
        self.screenshotProvider = screenshotProvider
    }

    func capture(appId: String, options: ScreenshotCaptureOptions) throws -> [String: Any] {
        try screenshotProvider.capture(
            appId: appId,
            options: options,
            screenMetadata: {
                try service.fetchHierarchy(appId: appId)
            }
        )
    }
}
