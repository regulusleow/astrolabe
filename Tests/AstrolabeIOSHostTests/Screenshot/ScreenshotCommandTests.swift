//
//  ScreenshotCommandTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeProtocol
import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import AstrolabeCLI
@testable import AstrolabeIOSDeviceSupport
@testable import AstrolabeIOSHost
@testable import AstrolabeIOSScreenshot

private typealias Fixtures = CLICommandTestFixtures

final class ScreenshotCommandTests: XCTestCase {
    func testProcessCommandRunnerReturnsStdout() throws {
        let data = try ProcessCommandRunner().run("/bin/echo", arguments: ["hello"])

        XCTAssertEqual(String(data: data, encoding: .utf8), "hello\n")
    }

    func testProcessCommandRunnerReportsCommandFailure() {
        XCTAssertThrowsError(
            try ProcessCommandRunner().run(
                "/bin/sh",
                arguments: ["-c", "echo command-failed >&2; exit 7"]
            )
        ) { error in
            XCTAssertEqual((error as? CLIError)?.code, "command_failed")
            XCTAssertTrue(String(describing: error).contains("Command failed"))
        }
    }

    func testDevicectlDeviceLockStateReaderParsesState() throws {
        let reader = DevicectlDeviceLockStateReader(
            commandRunner: Fixtures.FakeCommandRunner(jsonObject: [
                "result": [
                    "passcodeRequired": true,
                    "unlockedSinceBoot": true
                ]
            ])
        )

        let state = try reader.lockState(deviceIdentifier: "DEVICE-UDID")

        XCTAssertTrue(state.passcodeRequired)
    }

    func testScreenshotImageContentInspectorDetectsBlackFrame() throws {
        let inspector = ScreenshotImageContentInspector()
        let black = try Fixtures.makePNGData(
            width: 2,
            height: 2,
            pixels: Array(repeating: [0, 0, 0, 255], count: 4)
        )
        let visible = try Fixtures.makePNGData(
            width: 2,
            height: 2,
            pixels: [
                [0, 0, 0, 255],
                [0, 0, 0, 255],
                [0, 0, 0, 255],
                [1, 1, 1, 255]
            ]
        )

        XCTAssertTrue(try inspector.isCompletelyBlack(black))
        XCTAssertFalse(try inspector.isCompletelyBlack(visible))
    }

    func testCaptureScreenshotRequiresAppId() {
        XCTAssertThrowsError(try Fixtures.makeRunner(service: Fixtures.FakeInspectorService()).run(arguments: ["capture-screenshot"])) { error in
            XCTAssertEqual(String(describing: error), "Missing argument: appId")
        }
    }

    func testCaptureScreenshotWritesPNGAndReturnsMetadata() throws {
        let service = Fixtures.FakeInspectorService()
        service.screenshot = [
            "appId": "app-1",
            "serverVersion": 7,
            "screenshot": [
                "format": "png",
                "base64": Data("fake-png".utf8).base64EncodedString(),
                "byteCount": 8,
                "width": 390,
                "height": 844,
                "scale": 3
            ]
        ]
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let output = try Fixtures.makeRunner(service: service).run(arguments: [
            "capture-screenshot",
            "app-1",
            "--output",
            outputURL.path
        ])

        guard case .jsonObject(let object) = output else {
            return XCTFail("capture-screenshot should return jsonObject output")
        }
        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let screenshot = try XCTUnwrap(data["screenshot"] as? [String: Any])
        XCTAssertEqual(object["success"] as? Bool, true)
        XCTAssertEqual(screenshot["format"] as? String, "png")
        XCTAssertEqual(screenshot["outputPath"] as? String, outputURL.path)
        XCTAssertEqual(screenshot["byteCount"] as? Int, 8)
        XCTAssertNil(screenshot["base64"])
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return XCTFail("capture-screenshot should write a PNG file")
        }
        XCTAssertEqual(try Data(contentsOf: outputURL), Data("fake-png".utf8))
        XCTAssertEqual(service.calls, [])
    }

    func testCaptureScreenshotPassesSourceOptionsToProvider() throws {
        let service = Fixtures.FakeInspectorService()
        let provider = Fixtures.FakeScreenshotProvider()
        provider.payload = [
            "screenshot": [
                "format": "png",
                "base64": Data("fake-png".utf8).base64EncodedString(),
                "byteCount": 8,
                "source": "simulator",
                "lowResolution": false
            ]
        ]
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        _ = try Fixtures.makeScreenshotRunner(
            service: service,
            screenshotProvider: provider
        ).run(arguments: [
            "capture-screenshot",
            "simulator:simulator:47164:app-1",
            "--output",
            outputURL.path,
            "--source",
            "virtual",
            "--target-id",
            "SIM-1"
        ])

        XCTAssertEqual(provider.requests.map(\.appId), ["simulator:simulator:47164:app-1"])
        XCTAssertEqual(provider.requests.first?.captureOptions.target, .virtualDevice)
        XCTAssertEqual(provider.requests.first?.captureOptions.targetIdentifier, "SIM-1")
    }

    func testCaptureScreenshotMapsDeviceSourceToPhysicalDevice() throws {
        let service = Fixtures.FakeInspectorService()
        let provider = Fixtures.FakeScreenshotProvider()
        provider.payload = [
            "screenshot": [
                "format": "png",
                "base64": Data("fake-png".utf8).base64EncodedString(),
                "byteCount": 8,
                "source": "device",
                "lowResolution": false
            ]
        ]
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        _ = try Fixtures.makeScreenshotRunner(
            service: service,
            screenshotProvider: provider
        ).run(arguments: [
            "capture-screenshot",
            "usb:2:47210:cnVudGltZS00Mg:astrolabe",
            "--output",
            outputURL.path,
            "--source",
            "physical",
            "--target-id",
            "DEVICE-1"
        ])

        XCTAssertEqual(provider.requests.first?.captureOptions.target, .physicalDevice)
        XCTAssertEqual(provider.requests.first?.captureOptions.targetIdentifier, "DEVICE-1")
    }

    func testCaptureScreenshotUsesOptionsBuilderRegisteredForProviderPlatform() throws {
        let service = Fixtures.FakeInspectorService()
        service.descriptor = RuntimeUIProviderDescriptor(
            identifier: "android-provider",
            platform: .android,
            capabilities: [.hierarchy]
        )
        let provider = Fixtures.FakeScreenshotProvider()
        provider.payload = [
            "screenshot": [
                "format": "png",
                "base64": Data("fake-png".utf8).base64EncodedString(),
                "byteCount": 8,
                "source": "emulator",
                "lowResolution": false
            ]
        ]
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let runner = Fixtures.makeScreenshotRunner(
            service: service,
            screenshotProvider: provider,
            screenshotCaptureOptionsBuilders: [
                .android: AndroidScreenshotCaptureOptionsBuilder()
            ]
        )

        _ = try runner.run(arguments: [
            "capture-screenshot",
            "android:app-1",
            "--output",
            outputURL.path,
            "--source",
            "virtual",
            "--target-id",
            "EMULATOR-1"
        ])

        XCTAssertEqual(provider.requests.first?.captureOptions.target, .virtualDevice)
        XCTAssertEqual(provider.requests.first?.captureOptions.targetIdentifier, "EMULATOR-1")
    }

    func testCaptureScreenshotAcceptsPlatformNeutralTargetIdentifier() throws {
        let service = Fixtures.FakeInspectorService()
        let provider = Fixtures.FakeScreenshotProvider()
        provider.payload = [
            "screenshot": [
                "format": "png",
                "base64": Data("fake-png".utf8).base64EncodedString(),
                "byteCount": 8,
                "source": "simulator",
                "lowResolution": false
            ]
        ]
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        _ = try Fixtures.makeScreenshotRunner(
            service: service,
            screenshotProvider: provider
        ).run(arguments: [
            "capture-screenshot",
            "simulator:simulator:47164:app-1",
            "--output",
            outputURL.path,
            "--source",
            "virtual",
            "--target-id",
            "SIM-1"
        ])

        XCTAssertEqual(provider.requests.first?.captureOptions.target, .virtualDevice)
        XCTAssertEqual(provider.requests.first?.captureOptions.targetIdentifier, "SIM-1")
    }

    func testIOSSystemScreenshotCaptureOptionsBuilderMapsSupportedSources() throws {
        let builder = IOSSystemScreenshotCaptureOptionsBuilder()

        let automatic = try builder.build(from: ScreenshotCaptureSourceArguments(
            source: .automatic,
            targetIdentifier: "SIM-1"
        ))
        let virtual = try builder.build(from: ScreenshotCaptureSourceArguments(
            source: .virtual,
            targetIdentifier: "SIM-1"
        ))
        let physical = try builder.build(from: ScreenshotCaptureSourceArguments(
            source: .physical,
            targetIdentifier: "DEVICE-1"
        ))

        XCTAssertEqual(automatic.target, .automatic)
        XCTAssertEqual(automatic.targetIdentifier, "SIM-1")
        XCTAssertEqual(virtual.target, .virtualDevice)
        XCTAssertEqual(virtual.targetIdentifier, "SIM-1")
        XCTAssertEqual(physical.target, .physicalDevice)
        XCTAssertEqual(physical.targetIdentifier, "DEVICE-1")
    }

    func testScreenshotCaptureSourceRejectsUnknownSource() {
        XCTAssertThrowsError(try ScreenshotCaptureSource.parse("emulator")) { error in
            XCTAssertEqual(
                String(describing: error),
                "Invalid argument: --source supports only auto, virtual, or physical"
            )
        }
    }

    func testCaptureScreenshotRejectsUnknownSource() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        XCTAssertThrowsError(try Fixtures.makeRunner(service: Fixtures.FakeInspectorService()).run(arguments: [
            "capture-screenshot",
            "app-1",
            "--output",
            outputURL.path,
            "--source",
            "emulator"
        ])) { error in
            XCTAssertEqual(
                String(describing: error),
                "Invalid argument: --source supports only auto, virtual, or physical"
            )
        }
    }

    func testPhysicalSourceRequiresTargetIdentifier() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        XCTAssertThrowsError(try Fixtures.makeRunner(service: Fixtures.FakeInspectorService()).run(arguments: [
            "capture-screenshot",
            "app-1",
            "--output",
            outputURL.path,
            "--source",
            "physical"
        ])) { error in
            XCTAssertEqual(String(describing: error), "Invalid argument: --source physical requires --target-id")
        }
    }

    func testDefaultScreenshotProviderAutoResolvesUSBDeviceIdentifier() throws {
        let iosProvider = IOSSystemScreenshotProvider(
            simctl: Fixtures.FakeSimulatorScreenshotCapturer(),
            devicectl: Fixtures.FakeDeviceScreenshotCapturer(pngData: Data("device-png".utf8)),
            deviceIdentifierResolver: Fixtures.FakeDeviceIdentifierResolver(deviceIdentifier: "DEVICE-UDID"),
            deviceLockStateReader: Fixtures.FakeDeviceLockStateReader(states: [Fixtures.unlockedDeviceState]),
            imageContentInspector: Fixtures.FakeScreenshotImageContentInspector(isBlack: false),
            payloadBuilder: ScreenshotPayloadBuilder(
                imageMetadataReader: Fixtures.FakeScreenshotImageMetadataReader(pixelWidth: 1170, pixelHeight: 2532)
            )
        )
        let platformResolver = Fixtures.FakeInspectorService()
        let provider = DefaultScreenshotProvider(
            platformResolver: platformResolver,
            platformProviders: [.ios: iosProvider]
        )

        let payload = try provider.capture(
            appId: "usb:2:47210:cnVudGltZS00Mg:astrolabe",
            options: .automatic,
            screenMetadata: {
                [
                    "serverVersion": 7,
                    "app": [
                        "screen": [
                            "width": 390,
                            "height": 844,
                            "scale": 3
                        ]
                    ]
                ]
            }
        )

        let screenshot = try XCTUnwrap(payload["screenshot"] as? [String: Any])
        XCTAssertEqual(screenshot["source"] as? String, "device")
        XCTAssertEqual(screenshot["lowResolution"] as? Bool, false)
        XCTAssertEqual(screenshot["deviceIdentifier"] as? String, "DEVICE-UDID")
        XCTAssertEqual(screenshot["pixelWidth"] as? Int, 1170)
        XCTAssertEqual(screenshot["pixelHeight"] as? Int, 2532)
    }

    func testDefaultScreenshotProviderReportsUnboundUSBDevice() throws {
        let iosProvider = IOSSystemScreenshotProvider(
            simctl: Fixtures.FakeSimulatorScreenshotCapturer(),
            devicectl: Fixtures.FakeDeviceScreenshotCapturer(pngData: Data()),
            deviceIdentifierResolver: Fixtures.FakeDeviceIdentifierResolver(deviceIdentifier: nil),
            deviceLockStateReader: Fixtures.FakeDeviceLockStateReader(states: []),
            imageContentInspector: Fixtures.FakeScreenshotImageContentInspector(isBlack: false),
            payloadBuilder: ScreenshotPayloadBuilder(imageMetadataReader: ScreenshotImageMetadataReader())
        )
        let platformResolver = Fixtures.FakeInspectorService()
        let provider = DefaultScreenshotProvider(
            platformResolver: platformResolver,
            platformProviders: [.ios: iosProvider]
        )

        XCTAssertThrowsError(try provider.capture(
            appId: "usb:2:47210:cnVudGltZS00Mg:astrolabe",
            options: .automatic,
            screenMetadata: {
                XCTFail("Hierarchy should not be read when USB device binding fails")
                return [:]
            }
        )) { error in
            XCTAssertEqual(CLIError.code(for: error), "invalid_screenshot")
        }
    }

    func testIOSSystemScreenshotProviderRejectsDeviceSourceForSimulatorApp() {
        let provider = Fixtures.makeIOSSystemScreenshotProvider()
        let options = ScreenshotCaptureOptions(
            target: .physicalDevice,
            targetIdentifier: "DEVICE-UDID"
        )

        XCTAssertThrowsError(try provider.capture(
            appId: "simulator:simulator:47200:cnVudGltZS00Mg:astrolabe",
            options: options,
            screenMetadata: { [:] }
        )) { error in
            XCTAssertEqual(CLIError.code(for: error), "invalid_argument")
            XCTAssertEqual(
                String(describing: error),
                "Invalid argument: The physical screenshot source does not match a simulator appId"
            )
        }
    }

    func testIOSSystemScreenshotProviderRejectsSimulatorSourceForUSBApp() {
        let provider = Fixtures.makeIOSSystemScreenshotProvider()
        let options = ScreenshotCaptureOptions(
            target: .virtualDevice,
            targetIdentifier: "SIM-UDID"
        )

        XCTAssertThrowsError(try provider.capture(
            appId: "usb:2:47210:cnVudGltZS00Mg:astrolabe",
            options: options,
            screenMetadata: { [:] }
        )) { error in
            XCTAssertEqual(CLIError.code(for: error), "invalid_argument")
            XCTAssertEqual(
                String(describing: error),
                "Invalid argument: The virtual screenshot source does not match a USB appId"
            )
        }
    }

    func testDeviceScreenshotReportsLockedDeviceBeforeCapture() {
        let provider = Fixtures.makeIOSSystemScreenshotProvider(
            lockStates: [Fixtures.lockedDeviceState],
            isBlack: false
        )

        XCTAssertThrowsError(try provider.capture(
            appId: "usb:2:47210:cnVudGltZS00Mg:astrolabe",
            options: ScreenshotCaptureOptions(
                target: .physicalDevice,
                targetIdentifier: "DEVICE-UDID"
            ),
            screenMetadata: {
                XCTFail("Hierarchy should not be read while the physical device is locked")
                return [:]
            }
        )) { error in
            XCTAssertEqual(CLIError.code(for: error), "device_locked")
            XCTAssertEqual(
                CLIError.recoverySuggestion(for: error),
                "Unlock the physical device, keep the screen awake, and try again"
            )
        }
    }

    func testDeviceScreenshotReportsLockWhenDeviceLocksDuringCapture() {
        let provider = Fixtures.makeIOSSystemScreenshotProvider(
            lockStates: [Fixtures.unlockedDeviceState, Fixtures.lockedDeviceState],
            isBlack: true
        )

        XCTAssertThrowsError(try provider.capture(
            appId: "usb:2:47210:cnVudGltZS00Mg:astrolabe",
            options: ScreenshotCaptureOptions(
                target: .physicalDevice,
                targetIdentifier: "DEVICE-UDID"
            ),
            screenMetadata: { [:] }
        )) { error in
            XCTAssertEqual(CLIError.code(for: error), "device_locked")
        }
    }

    func testDeviceScreenshotRejectsBlackFrameFromUnlockedDevice() {
        let provider = Fixtures.makeIOSSystemScreenshotProvider(
            lockStates: [Fixtures.unlockedDeviceState, Fixtures.unlockedDeviceState],
            isBlack: true
        )

        XCTAssertThrowsError(try provider.capture(
            appId: "usb:2:47210:cnVudGltZS00Mg:astrolabe",
            options: ScreenshotCaptureOptions(
                target: .physicalDevice,
                targetIdentifier: "DEVICE-UDID"
            ),
            screenMetadata: { [:] }
        )) { error in
            XCTAssertEqual(CLIError.code(for: error), "invalid_screenshot")
            XCTAssertEqual(
                String(describing: error),
                "Invalid screenshot data: The physical device returned an all-black image"
            )
        }
    }

    func testDefaultScreenshotProviderRoutesByResolvedPlatform() throws {
        let platformResolver = Fixtures.FakeInspectorService()
        platformResolver.descriptor = RuntimeUIProviderDescriptor(
            identifier: "android-provider",
            platform: .android,
            capabilities: [.hierarchy]
        )
        let iosProvider = Fixtures.FakePlatformScreenshotProvider()
        let androidProvider = Fixtures.FakePlatformScreenshotProvider(payload: ["provider": "android"])
        let provider = DefaultScreenshotProvider(
            platformResolver: platformResolver,
            platformProviders: [
                .ios: iosProvider,
                .android: androidProvider
            ]
        )

        let payload = try provider.capture(
            appId: "simulator:misleading-app-id",
            options: .automatic,
            screenMetadata: { [:] }
        )

        XCTAssertEqual(payload["provider"] as? String, "android")
        XCTAssertTrue(iosProvider.capturedAppIds.isEmpty)
        XCTAssertEqual(androidProvider.capturedAppIds, ["simulator:misleading-app-id"])
    }

    func testDeviceIdentifierResolverBindsUSBMuxDeviceToMatchingUDID() throws {
        let resolver = DevicectlDeviceIdentifierResolver(
            commandRunner: Fixtures.FakeCommandRunner(jsonObject: Fixtures.devicectlDevicesJSON([
            Fixtures.devicectlDevice(name: "Booted Simulator", udid: "SIM-1", platform: "iOS", reality: "simulated", transportType: "sameMachine"),
            Fixtures.devicectlDevice(name: "iPhone A", udid: "PHONE-A", platform: "iOS", reality: "physical", transportType: "wired"),
            Fixtures.devicectlDevice(name: "iPhone B", udid: "PHONE-B", platform: "iOS", reality: "physical", transportType: "wired")
            ])),
            usbMuxDeviceDiscovery: Fixtures.FakeScreenshotUSBMuxDeviceDiscovery(devices: [
                USBMuxDeviceIdentity(
                    deviceIdentifier: "2",
                    serialNumber: "PHONE-B"
                )
            ])
        )

        XCTAssertEqual(
            try resolver.resolvePhysicalIOSDeviceIdentifier(
                usbMuxDeviceIdentifier: "2",
                requestedIdentifier: nil
            ),
            "PHONE-B"
        )
    }

    func testDeviceIdentifierResolverBindsDeviceWhenListOmitsScreenshotCapability() throws {
        let resolver = DevicectlDeviceIdentifierResolver(
            commandRunner: Fixtures.FakeCommandRunner(jsonObject: Fixtures.devicectlDevicesJSON([
                Fixtures.devicectlDevice(
                    name: "iPhone",
                    udid: "PHONE-UDID",
                    platform: "iOS",
                    reality: "physical",
                    transportType: "wired",
                    includesScreenshotCapability: false
                )
            ])),
            usbMuxDeviceDiscovery: Fixtures.FakeScreenshotUSBMuxDeviceDiscovery(devices: [
                USBMuxDeviceIdentity(
                    deviceIdentifier: "2",
                    serialNumber: "PHONE-UDID"
                )
            ])
        )

        XCTAssertEqual(
            try resolver.resolvePhysicalIOSDeviceIdentifier(
                usbMuxDeviceIdentifier: "2",
                requestedIdentifier: nil
            ),
            "PHONE-UDID"
        )
    }

    func testDeviceIdentifierResolverRejectsDifferentRequestedDevice() throws {
        let resolver = DevicectlDeviceIdentifierResolver(
            commandRunner: Fixtures.FakeCommandRunner(jsonObject: Fixtures.devicectlDevicesJSON([
            Fixtures.devicectlDevice(name: "iPhone A", udid: "PHONE-A", platform: "iOS", reality: "physical", transportType: "wired"),
            Fixtures.devicectlDevice(name: "iPhone B", udid: "PHONE-B", platform: "iOS", reality: "physical", transportType: "wired")
            ])),
            usbMuxDeviceDiscovery: Fixtures.FakeScreenshotUSBMuxDeviceDiscovery(devices: [
                USBMuxDeviceIdentity(
                    deviceIdentifier: "2",
                    serialNumber: "PHONE-B"
                )
            ])
        )

        XCTAssertThrowsError(try resolver.resolvePhysicalIOSDeviceIdentifier(
            usbMuxDeviceIdentifier: "2",
            requestedIdentifier: "PHONE-A"
        )) { error in
            XCTAssertEqual(CLIError.code(for: error), "invalid_argument")
        }
    }

}

private struct AndroidScreenshotCaptureOptionsBuilder: ScreenshotCaptureOptionsBuilding {
    func build(from arguments: ScreenshotCaptureSourceArguments) throws -> ScreenshotCaptureOptions {
        guard arguments.source == .virtual else {
            throw CLIError.invalidArgument("Invalid Android screenshot source")
        }
        return ScreenshotCaptureOptions(
            target: .virtualDevice,
            targetIdentifier: arguments.targetIdentifier
        )
    }
}
