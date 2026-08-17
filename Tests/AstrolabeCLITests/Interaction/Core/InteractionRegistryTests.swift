//
//  InteractionRegistryTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/17.
//

import XCTest

@testable import AstrolabeCLI

final class InteractionRegistryTests: XCTestCase {
    func testTargetRejectsEachEmptyIdentifier() throws {
        let updates: [(inout TargetValues) -> Void] = [
            { target in target.appId = "" },
            { target in target.deviceIdentifier = "" },
            { target in target.processIdentifier = "" }
        ]
        for update in updates {
            var values = TargetValues()
            update(&values)
            assertInvalidInput { try makeTarget(values: values) }
        }
    }

    func testTargetRejectsEachEmptyStringLocator() {
        for locator in [
            InteractionLocator.stableIdentifier(""),
            .accessibilityLabel(""),
            .alias("")
        ] {
            assertInvalidInput { try self.makeTarget(locator: locator) }
        }
    }

    func testPointRejectsInvalidXAndYValuesIndependently() {
        let invalidValues: [Double] = [.nan, .infinity, -.infinity, -1]
        for value in invalidValues {
            assertInvalidInput { try InteractionPoint(x: value, y: 1) }
            assertInvalidInput { try InteractionPoint(x: 1, y: value) }
        }
    }

    func testViewportRejectsInvalidWidthAndHeightValuesIndependently() {
        let invalidValues: [Double] = [.nan, .infinity, -.infinity, 0, -1]
        for value in invalidValues {
            assertInvalidInput { try InteractionViewport(width: value, height: 1) }
            assertInvalidInput { try InteractionViewport(width: 1, height: value) }
        }
    }

    func testTargetRejectsInvalidObservationTimes() {
        let invalidValues: [TimeInterval] = [.nan, .infinity, -.infinity, -1]
        for value in invalidValues {
            assertInvalidInput { try self.makeTarget(observedAtUnixTime: value) }
        }
    }

    func testActionsRejectInvalidLongPressAndSwipeDurations() throws {
        let invalidValues: [TimeInterval] = [.nan, .infinity, -.infinity, 0, -1]
        let point = try InteractionPoint(x: 1, y: 1)
        for value in invalidValues {
            assertInvalidInput {
                try InteractionAction(validating: .longPress(duration: value))
            }
            assertInvalidInput {
                try InteractionAction(validating: .swipe(to: point, duration: value))
            }
        }
    }

    func testActionRejectsEmptyPlatformNeutralKey() {
        assertInvalidInput {
            try InteractionAction(validating: .pressKey(""))
        }
    }

    func testTargetRejectsLocatorPointOutsideEachViewportAxis() throws {
        let points = [
            try InteractionPoint(x: 101, y: 1),
            try InteractionPoint(x: 1, y: 201)
        ]
        for point in points {
            assertInvalidInput { try self.makeTarget(locator: .point(point)) }
        }
    }

    func testRequestRejectsSwipeDestinationOutsideEachViewportAxis() throws {
        let target = try makeTarget(locator: .point(try InteractionPoint(x: 1, y: 1)))
        let destinations = [
            try InteractionPoint(x: 101, y: 1),
            try InteractionPoint(x: 1, y: 201)
        ]
        for destination in destinations {
            let action = try InteractionAction(validating: .swipe(to: destination, duration: 1))
            assertInvalidInput { try InteractionRequest(action: action, target: target) }
        }
    }

    func testProviderDescriptorRejectsMissingIdentifierOrCapabilities() {
        assertInvalidInput {
            try InteractionProviderDescriptor(
                identifier: "",
                platform: .ios,
                supportedDeviceKinds: [.virtual],
                supportedActionKinds: [.tap]
            )
        }
        assertInvalidInput {
            try InteractionProviderDescriptor(
                identifier: "provider",
                platform: .ios,
                supportedDeviceKinds: [],
                supportedActionKinds: [.tap]
            )
        }
        assertInvalidInput {
            try InteractionProviderDescriptor(
                identifier: "provider",
                platform: .ios,
                supportedDeviceKinds: [.virtual],
                supportedActionKinds: []
            )
        }
    }

    func testRegistryUsesResolvedPlatformInsteadOfAppIDText() throws {
        let iosProvider = FakeProvider(
            identifier: "ios",
            platform: .ios,
            deviceKinds: [.virtual],
            actionKinds: [.tap]
        )
        let registry = try InteractionRegistry(
            platformResolver: FakePlatformResolver(platform: .ios),
            providers: [iosProvider]
        )

        _ = try registry.perform(try makeRequest(appId: "android-looking-id"))

        XCTAssertEqual(iosProvider.callCount, 1)
    }

    func testRegistrySelectsDeviceKindSpecificProviderOnSamePlatform() throws {
        let virtualProvider = FakeProvider(
            identifier: "ios-simulator",
            platform: .ios,
            deviceKinds: [.virtual],
            actionKinds: [.tap]
        )
        let physicalProvider = FakeProvider(
            identifier: "ios-device",
            platform: .ios,
            deviceKinds: [.physical],
            actionKinds: [.tap]
        )
        let registry = try makeRegistry(providers: [virtualProvider, physicalProvider])

        _ = try registry.perform(try makeRequest(deviceKind: .physical))

        XCTAssertEqual(virtualProvider.callCount, 0)
        XCTAssertEqual(physicalProvider.callCount, 1)
    }

    func testRegistrySelectsProviderByActionCapability() throws {
        let tapProvider = FakeProvider(
            identifier: "tap",
            platform: .ios,
            deviceKinds: [.virtual],
            actionKinds: [.tap]
        )
        let inputProvider = FakeProvider(
            identifier: "input",
            platform: .ios,
            deviceKinds: [.virtual],
            actionKinds: [.inputText]
        )
        let registry = try makeRegistry(providers: [tapProvider, inputProvider])
        let request = try makeRequest(action: .inputText("Hello"))

        _ = try registry.perform(request)

        XCTAssertEqual(tapProvider.callCount, 0)
        XCTAssertEqual(inputProvider.callCount, 1)
    }

    func testRegistrySelectsOnlyProviderThatCanHandleTarget() throws {
        let rejectedProvider = FakeProvider(identifier: "rejected")
        rejectedProvider.handlesTarget = false
        let selectedProvider = FakeProvider(identifier: "selected")
        let registry = try makeRegistry(providers: [rejectedProvider, selectedProvider])

        _ = try registry.perform(try makeRequest())

        XCTAssertEqual(rejectedProvider.callCount, 0)
        XCTAssertEqual(selectedProvider.callCount, 1)
    }

    func testRegistryRejectsUnavailableProviderContext() throws {
        let registry = try makeRegistry(providers: [])

        XCTAssertThrowsError(try registry.perform(try makeRequest())) { error in
            XCTAssertEqual(
                error as? InteractionError,
                .providerUnavailable(platform: .ios, deviceKind: .virtual)
            )
        }
    }

    func testRegistryRejectsUnavailableProviderWhenAllCanHandleReturnFalse() throws {
        let first = FakeProvider(identifier: "first")
        let second = FakeProvider(identifier: "second")
        first.handlesTarget = false
        second.handlesTarget = false
        let registry = try makeRegistry(providers: [first, second])

        XCTAssertThrowsError(try registry.perform(try makeRequest())) { error in
            XCTAssertEqual(
                error as? InteractionError,
                .providerUnavailable(platform: .ios, deviceKind: .virtual)
            )
        }
        XCTAssertEqual(first.callCount, 0)
        XCTAssertEqual(second.callCount, 0)
    }

    func testRegistryRejectsUnsupportedAction() throws {
        let provider = FakeProvider(
            identifier: "tap",
            platform: .ios,
            deviceKinds: [.virtual],
            actionKinds: [.tap]
        )
        let registry = try makeRegistry(providers: [provider])

        XCTAssertThrowsError(
            try registry.perform(try makeRequest(action: .inputText("Hello")))
        ) { error in
            XCTAssertEqual(error as? InteractionError, .unsupportedAction(.inputText))
        }
    }

    func testRegistryRejectsDuplicateProviderIdentifiers() throws {
        let first = FakeProvider(identifier: "duplicate")
        let second = FakeProvider(identifier: "duplicate")

        XCTAssertThrowsError(
            try makeRegistry(providers: [first, second])
        ) { error in
            XCTAssertEqual(error as? InteractionError, .duplicateProviderIdentifier("duplicate"))
        }
    }

    func testRegistryRejectsAmbiguousCapableProviders() throws {
        let first = FakeProvider(identifier: "first")
        let second = FakeProvider(identifier: "second")
        let registry = try makeRegistry(providers: [first, second])

        XCTAssertThrowsError(try registry.perform(try makeRequest())) { error in
            XCTAssertEqual(
                error as? InteractionError,
                .ambiguousProviders(["first", "second"])
            )
        }
        XCTAssertEqual(first.callCount, 0)
        XCTAssertEqual(second.callCount, 0)
    }

    func testRegistryCallsSelectedProviderOnceAndReturnsUnchangedUncertainResult() throws {
        let provider = FakeProvider(identifier: "selected")
        let registry = try makeRegistry(providers: [provider])
        let request = try makeRequest()
        let expected = InteractionResult(request: request, status: .uncertain)
        provider.result = expected

        let result = try registry.perform(request)

        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(result, expected)
    }

    func testRegistryPropagatesProviderFailureWithoutRetryOrWrapping() throws {
        let provider = FakeProvider(identifier: "failing")
        provider.error = InteractionError.executionFailed("transport failed")
        let registry = try makeRegistry(providers: [provider])

        XCTAssertThrowsError(try registry.perform(try makeRequest())) { error in
            XCTAssertEqual(error as? InteractionError, .executionFailed("transport failed"))
        }
        XCTAssertEqual(provider.callCount, 1)
    }

    private func assertInvalidInput<Value>(
        _ expression: () throws -> Value,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try expression(), file: file, line: line) { error in
            guard case .invalidInput = error as? InteractionError else {
                return XCTFail("Expected invalid input, got \(error)", file: file, line: line)
            }
        }
    }

    private func makeRegistry(
        providers: [any PlatformInteractionPerforming]
    ) throws -> InteractionRegistry {
        try InteractionRegistry(
            platformResolver: FakePlatformResolver(platform: .ios),
            providers: providers
        )
    }

    private func makeRequest(
        appId: String = "app",
        deviceKind: InteractionDeviceKind = .virtual,
        action: InteractionAction = .tap
    ) throws -> InteractionRequest {
        try InteractionRequest(
            action: action,
            target: try makeTarget(appId: appId, deviceKind: deviceKind)
        )
    }

    private func makeTarget(
        appId: String = "app",
        deviceKind: InteractionDeviceKind = .virtual,
        observedAtUnixTime: TimeInterval = 1,
        locator: InteractionLocator = .stableIdentifier("button"),
        values: TargetValues? = nil
    ) throws -> InteractionTarget {
        let values = values ?? TargetValues(
            appId: appId,
            deviceKind: deviceKind,
            observedAtUnixTime: observedAtUnixTime,
            locator: locator
        )
        return try InteractionTarget(
            appId: values.appId,
            deviceIdentifier: values.deviceIdentifier,
            deviceKind: values.deviceKind,
            processIdentifier: values.processIdentifier,
            observedAtUnixTime: values.observedAtUnixTime,
            orientation: .portrait,
            viewport: try InteractionViewport(width: 100, height: 200),
            locator: values.locator
        )
    }
}

private struct TargetValues {
    /// App identifier used by the target fixture.
    var appId: String = "app"

    /// Device identifier used by the target fixture.
    var deviceIdentifier: String = "device"

    /// Device category used by the target fixture.
    var deviceKind: InteractionDeviceKind = .virtual

    /// Process identifier used by the target fixture.
    var processIdentifier: String = "process"

    /// Observation time used by the target fixture.
    var observedAtUnixTime: TimeInterval = 1

    /// Locator used by the target fixture.
    var locator: InteractionLocator = .stableIdentifier("button")
}

private final class FakePlatformResolver: RuntimeUIPlatformResolving {
    /// Platform returned for every app identifier.
    private let resolvedPlatform: RuntimeUIPlatform

    init(platform: RuntimeUIPlatform) {
        resolvedPlatform = platform
    }

    func platform(for appId: String) throws -> RuntimeUIPlatform {
        resolvedPlatform
    }
}

private final class FakeProvider: PlatformInteractionPerforming {
    /// Provider capability descriptor.
    let descriptor: InteractionProviderDescriptor

    /// Number of requests performed by this Provider.
    private(set) var callCount = 0

    /// Result returned after a successful request.
    var result: InteractionResult?

    /// Error returned instead of a successful request.
    var error: Error?

    /// Whether this Provider accepts the target context.
    var handlesTarget = true

    init(
        identifier: String,
        platform: RuntimeUIPlatform = .ios,
        deviceKinds: Set<InteractionDeviceKind> = [.virtual],
        actionKinds: Set<InteractionActionKind> = [.tap]
    ) {
        descriptor = try! InteractionProviderDescriptor(
            identifier: identifier,
            platform: platform,
            supportedDeviceKinds: deviceKinds,
            supportedActionKinds: actionKinds
        )
    }

    func canHandle(target: InteractionTarget) -> Bool {
        handlesTarget
    }

    func perform(_ request: InteractionRequest) throws -> InteractionResult {
        callCount += 1
        if let error {
            throw error
        }
        return result ?? InteractionResult(request: request, status: .sent)
    }
}
