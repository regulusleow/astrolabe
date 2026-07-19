//
//  HostPlatformModuleTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/15.
//

import XCTest

@testable import AstrolabeCLI

final class HostPlatformModuleTests: XCTestCase {
    func testRegistryRejectsMissingPlatformModules() {
        XCTAssertThrowsError(try HostPlatformModuleRegistry(modules: [])) { error in
            XCTAssertEqual(
                error as? HostPlatformModuleValidationError,
                .missingPlatformModule
            )
        }
    }

    func testDiscoveryOnlyProviderDoesNotImplementUnrelatedCapabilities() throws {
        let provider = DiscoveryOnlyProvider()
        let module = try HostPlatformModuleBuilder(provider: provider)
            .applicationDiscovery(provider)
            .build()

        XCTAssertEqual(module.platform, .android)
        XCTAssertEqual(module.providerDescriptor.capabilities, [.appDiscovery])

        let registry = try HostPlatformModuleRegistry(modules: [module])
        XCTAssertEqual(try registry.fetchApps().map(\.appId), ["android:demo"])
        XCTAssertThrowsError(try registry.fetchHierarchy(appId: "android:demo")) { error in
            XCTAssertEqual(CLIError.code(for: error), "target_capability_unsupported")
        }
    }

    func testBuilderRejectsDeclaredCapabilityWithoutImplementation() {
        let provider = HierarchyDeclaringProvider()

        XCTAssertThrowsError(
            try HostPlatformModuleBuilder(provider: provider)
                .applicationDiscovery(provider)
                .build()
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformModuleValidationError,
                .capabilityImplementationMismatch(
                    providerIdentifier: "incomplete-provider",
                    declared: [.appDiscovery, .hierarchy],
                    registered: [.appDiscovery]
                )
            )
        }
    }

    func testBuilderRejectsIncompleteScreenshotRegistration() {
        let provider = DiscoveryOnlyProvider()

        XCTAssertThrowsError(
            try HostPlatformModuleBuilder(provider: provider)
                .applicationDiscovery(provider)
                .screenshotOptionsBuilder(FakeScreenshotOptionsBuilder())
                .build()
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformModuleValidationError,
                .incompleteScreenshotRegistration(platform: .android)
            )
        }
    }

    func testScreenshotRegistrationDoesNotRequireNamedMasks() throws {
        let provider = DiscoveryOnlyProvider()

        XCTAssertNoThrow(
            try HostPlatformModuleBuilder(provider: provider)
                .applicationDiscovery(provider)
                .screenshotOptionsBuilder(FakeScreenshotOptionsBuilder())
                .screenshotProvider(FakePlatformScreenshotProvider())
                .visualDiffIssueInterpreter(
                    PlatformNeutralVisualDiffIssueInterpreter()
                )
                .build()
        )
    }

    func testCommandRunnerStartsFromPlatformModules() throws {
        let provider = DiscoveryOnlyProvider()
        let module = try HostPlatformModuleBuilder(provider: provider)
            .applicationDiscovery(provider)
            .build()
        let runner = try CLICommandRunner(platformModules: [module])

        let output = try runner.run(arguments: ["list-apps"])

        guard case .appList(let result) = output else {
            return XCTFail("list-apps should return appList output")
        }
        XCTAssertEqual(result.data?.apps.map(\.appId), ["android:demo"])
    }

    func testCommandRunnerRoutesNodeDetailSemanticsUsingCommandAppID() throws {
        let provider = NodeDetailOnlyProvider()
        let module = try HostPlatformModuleBuilder(provider: provider)
            .nodeDetail(provider)
            .nodeDetailSemanticMapper(AppIDAwareSemanticMapper())
            .nodeDetailIssueInterpreter(
                PlatformNeutralNodeDetailSemanticIssueInterpreter()
            )
            .build()
        let runner = try CLICommandRunner(platformModules: [module])

        let output = try runner.run(arguments: [
            "summarize-node-detail",
            "android:demo",
            "42"
        ])

        guard case .jsonObject(let object) = output,
              let data = object["data"] as? [String: Any],
              let attributes = data["attributes"] as? [[String: Any]] else {
            return XCTFail("summarize-node-detail should return an attribute summary")
        }
        XCTAssertEqual(attributes.first?["semanticName"] as? String, "platformTitle")
    }

    func testBaselineIssueInterpreterReceivesCurrentCommandAppID() throws {
        let builder = BaselineNodeDetailComparisonBuilder(
            issueClassifier: AppIDAwareIssueInterpreter()
        )
        let baselineDetail = semanticDetail(value: "Before")
        let currentDetail = semanticDetail(value: "After")

        let changes = builder.compare(
            appId: "android:demo",
            baselineDetail: baselineDetail,
            currentDetail: currentDetail
        )

        XCTAssertEqual(changes.first?["issue"] as? String, "platformTitleChanged")
    }

    func testBuilderRejectsHierarchyWithoutPlatformInspectionServices() {
        let provider = CompleteHierarchyProvider()

        XCTAssertThrowsError(
            try HostPlatformModuleBuilder(provider: provider)
                .applicationDiscovery(provider)
                .hierarchyCapture(provider)
                .build()
        ) { error in
            XCTAssertEqual(
                error as? HostPlatformModuleValidationError,
                .incompleteHierarchyRegistration(platform: .android)
            )
        }
    }

    func testRegistryRejectsDuplicatePlatformModules() throws {
        let first = DiscoveryOnlyProvider(identifier: "first-provider")
        let second = DiscoveryOnlyProvider(identifier: "second-provider")
        let modules = try [first, second].map { provider in
            try HostPlatformModuleBuilder(provider: provider)
                .applicationDiscovery(provider)
                .build()
        }

        XCTAssertThrowsError(try HostPlatformModuleRegistry(modules: modules)) { error in
            XCTAssertEqual(
                error as? HostPlatformModuleValidationError,
                .duplicatePlatform(.android)
            )
        }
    }

    func testRegistryRejectsDuplicateProviderIdentifiers() throws {
        let first = DiscoveryOnlyProvider(
            identifier: "shared-provider",
            platform: .ios
        )
        let second = DiscoveryOnlyProvider(
            identifier: "shared-provider",
            platform: .android
        )
        let modules = try [first, second].map { provider in
            try HostPlatformModuleBuilder(provider: provider)
                .applicationDiscovery(provider)
                .build()
        }

        XCTAssertThrowsError(try HostPlatformModuleRegistry(modules: modules)) { error in
            XCTAssertEqual(
                error as? HostPlatformModuleValidationError,
                .duplicateProviderIdentifier("shared-provider")
            )
        }
    }

    private func semanticDetail(value: String) -> [String: Any] {
        [
            "semanticAttributes": [
                "platformTitle": [
                    "semanticPath": "text.platformTitle",
                    "value": value,
                    "valuePreview": value
                ]
            ]
        ]
    }
}

private final class DiscoveryOnlyProvider:
    RuntimeUIProviderTargeting,
    RuntimeApplicationDiscovering {
    /// Capability descriptor for the fake Provider.
    let descriptor: RuntimeUIProviderDescriptor

    init(
        identifier: String = "discovery-provider",
        platform: RuntimeUIPlatform = .android
    ) {
        descriptor = RuntimeUIProviderDescriptor(
            identifier: identifier,
            platform: platform,
            capabilities: [.appDiscovery]
        )
    }

    func canHandle(appId: String) -> Bool {
        appId == "android:demo"
    }

    func fetchApps() throws -> [InspectableAppRecord] {
        [InspectableAppRecord(
            appId: "android:demo",
            platform: descriptor.platform,
            providerIdentifier: descriptor.identifier,
            capabilities: [.appDiscovery],
            displayName: "Demo",
            applicationIdentifier: "com.example.demo",
            deviceName: "Pixel",
            providerVersion: "1",
            connectionKind: "adb",
            deviceId: "emulator",
            endpointPort: 0,
            processIdentifier: "process"
        )]
    }
}

private final class CompleteHierarchyProvider:
    RuntimeUIProviderTargeting,
    RuntimeApplicationDiscovering,
    RuntimeUIHierarchyCapturing {
    /// Capability descriptor for the fake Provider.
    let descriptor = RuntimeUIProviderDescriptor(
        identifier: "hierarchy-provider",
        platform: .android,
        capabilities: [.appDiscovery, .hierarchy]
    )

    func canHandle(appId: String) -> Bool {
        false
    }

    func fetchApps() throws -> [InspectableAppRecord] {
        []
    }

    func fetchHierarchy(appId: String) throws -> [String: Any] {
        [:]
    }
}

private final class NodeDetailOnlyProvider:
    RuntimeUIProviderTargeting,
    RuntimeUINodeDetailProviding {
    /// Capability descriptor for the fake Provider.
    let descriptor = RuntimeUIProviderDescriptor(
        identifier: "node-detail-provider",
        platform: .android,
        capabilities: [.nodeDetail]
    )

    func canHandle(appId: String) -> Bool {
        appId == "android:demo"
    }

    func fetchNodeDetail(appId: String, oid: String) throws -> [String: Any] {
        [
            "requestedOid": oid,
            "attributeGroups": [[
                "identifier": "Text",
                "sections": [[
                    "identifier": "Content",
                    "attributes": [[
                        "identifier": "platform_title",
                        "displayTitle": "Title",
                        "attrTypeName": "string",
                        "value": "Demo"
                    ]]
                ]]
            ]]
        ]
    }
}

private struct AppIDAwareSemanticMapper: NodeDetailAttributeSemanticMapping {
    func semantics(
        forIdentifier identifier: String,
        appId: String
    ) -> NodeDetailAttributeSemantics? {
        guard identifier == "platform_title", appId == "android:demo" else {
            return nil
        }
        return NodeDetailAttributeSemantics(
            name: "platformTitle",
            path: "text.platformTitle"
        )
    }
}

private struct AppIDAwareIssueInterpreter: NodeDetailSemanticIssueInterpreting {
    func issueName(for semanticName: String, appId: String) -> String {
        guard semanticName == "platformTitle", appId == "android:demo" else {
            return "unexpectedContext"
        }
        return "platformTitleChanged"
    }
}

private final class HierarchyDeclaringProvider:
    RuntimeUIProviderTargeting,
    RuntimeApplicationDiscovering {
    let descriptor = RuntimeUIProviderDescriptor(
        identifier: "incomplete-provider",
        platform: .android,
        capabilities: [.appDiscovery, .hierarchy]
    )

    func canHandle(appId: String) -> Bool {
        false
    }

    func fetchApps() throws -> [InspectableAppRecord] {
        []
    }
}

private struct FakeScreenshotOptionsBuilder: ScreenshotCaptureOptionsBuilding {
    func build(from arguments: ScreenshotCaptureSourceArguments) throws -> ScreenshotCaptureOptions {
        .automatic
    }
}

private struct FakePlatformScreenshotProvider: PlatformScreenshotProviding {
    func capture(
        appId: String,
        options: ScreenshotCaptureOptions,
        screenMetadata: () throws -> [String: Any]
    ) throws -> [String: Any] {
        [:]
    }
}
