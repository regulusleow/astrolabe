//
//  AstrolabeIOSHostFactory.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

import AstrolabeCLI
import AstrolabeIOSInspection
import AstrolabeIOSScreenshot

package enum AstrolabeIOSHostFactory {
    package static func makeCommandRunner() throws -> CLICommandRunner {
        try CLICommandRunner(platformModules: [makePlatformModule()])
    }

    package static func makePlatformModule() throws -> HostPlatformModule {
        let provider = AstrolabeIOSRuntimeProvider()
        return try HostPlatformModuleBuilder(provider: provider)
            .applicationDiscovery(provider)
            .appDiscoveryDiagnostics(provider)
            .hierarchyCapture(provider)
            .nodeDetail(provider)
            .patchCatalog(provider)
            .attributePatching(provider)
            .screenshotOptionsBuilder(IOSSystemScreenshotCaptureOptionsBuilder())
            .screenshotProvider(IOSSystemScreenshotProvider())
            .screenInspectionBuilder(ScreenInspectionBuilder(
                qualityPolicy: UIKitScreenInspectionTargetQualityPolicy()
            ))
            .semanticRoleClassifier(UIKitNodeSemanticRoleClassifier())
            .nodeDetailSemanticMapper(UIKitNodeDetailAttributeSemanticMapper())
            .nodeDetailIssueInterpreter(UIKitNodeDetailSemanticIssueInterpreter())
            .visualDiffIssueInterpreter(UIKitVisualDiffIssueInterpreter())
            .namedMaskResolver(IOSSystemScreenshotNamedMaskResolver())
            .build()
    }
}
