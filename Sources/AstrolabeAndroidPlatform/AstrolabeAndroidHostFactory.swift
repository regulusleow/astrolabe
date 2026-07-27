//
//  AstrolabeAndroidHostFactory.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeAndroidHost
import AstrolabeAndroidInspection
import AstrolabeAndroidScreenshot
import AstrolabeCLI

package enum AstrolabeAndroidHostFactory {
    package static func makePlatformModule() throws -> HostPlatformModule {
        let provider = AstrolabeAndroidRuntimeProvider()
        return try HostPlatformModuleBuilder(provider: provider)
            .applicationDiscovery(provider)
            .appDiscoveryDiagnostics(provider)
            .hierarchyCapture(provider)
            .nodeDetail(provider)
            .patchCatalog(provider)
            .attributePatching(provider)
            .screenshotOptionsBuilder(AndroidScreenshotCaptureOptionsBuilder())
            .screenshotProvider(AndroidSystemScreenshotProvider())
            .screenInspectionBuilder(ScreenInspectionBuilder(
                qualityPolicy: AndroidScreenInspectionTargetQualityPolicy()
            ))
            .semanticRoleClassifier(AndroidNodeSemanticRoleClassifier())
            .nodeDetailSemanticMapper(AndroidNodeDetailAttributeSemanticMapper())
            .nodeDetailIssueInterpreter(AndroidNodeDetailSemanticIssueInterpreter())
            .visualDiffIssueInterpreter(AndroidVisualDiffIssueInterpreter())
            .build()
    }
}
