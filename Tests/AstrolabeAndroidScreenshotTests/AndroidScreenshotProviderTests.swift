//
//  AndroidScreenshotProviderTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

@testable import AstrolabeAndroidDeviceSupport
@testable import AstrolabeAndroidHost
@testable import AstrolabeAndroidScreenshot
@testable import AstrolabeCLI
@testable import AstrolabeScreenshotSupport
import Foundation
import XCTest

final class AndroidScreenshotProviderTests: XCTestCase {
    func testProviderCapturesCurrentDevicePNGForBoundApp() throws {
        let pngData = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        ))
        let runner = ScreenshotADBCommandRunner(results: [
            commandOutput("topResumedActivity=ActivityRecord{42 u0 com.example.demo/.MainActivity t1}\n"),
            commandOutput("isStatusBarKeyguard=false\n"),
            ADBCommandResult(
                standardOutput: pngData,
                standardError: Data(),
                exitCode: 0
            )
        ])
        let provider = AndroidSystemScreenshotProvider(
            adbClient: ADBClient(commandRunner: runner),
            imageContentInspector: NonBlackScreenshotInspector()
        )
        let appID = AndroidRuntimeAppID(
            deviceSerial: "emulator-5554",
            processIdentifier: 321,
            applicationIdentifier: "com.example.demo",
            runtimeInstanceIdentifier: "runtime-42"
        ).rawValue

        let payload = try provider.capture(
            appId: appID,
            options: .automatic,
            screenMetadata: { self.screenMetadata() }
        )

        let screenshot = try XCTUnwrap(payload["screenshot"] as? [String: Any])
        XCTAssertEqual(screenshot["source"] as? String, "adb")
        XCTAssertEqual(screenshot["deviceSerial"] as? String, "emulator-5554")
        XCTAssertEqual(screenshot["connectionKind"] as? String, "emulator")
        XCTAssertEqual(screenshot["pixelWidth"] as? Int, 1)
        XCTAssertEqual(screenshot["pixelHeight"] as? Int, 1)
        XCTAssertEqual(screenshot["pointWidth"] as? Double, 0.4)
        XCTAssertEqual(screenshot["pointHeight"] as? Double, 0.4)
        XCTAssertEqual(runner.invocations, [
            ["-s", "emulator-5554", "shell", "dumpsys", "activity", "activities"],
            ["-s", "emulator-5554", "shell", "dumpsys", "window", "policy"],
            ["-s", "emulator-5554", "exec-out", "screencap", "-p"]
        ])
    }

    func testProviderRejectsTargetIdentifierFromAnotherDevice() throws {
        let provider = AndroidSystemScreenshotProvider(
            adbClient: ADBClient(commandRunner: ScreenshotADBCommandRunner(results: []))
        )
        let appID = AndroidRuntimeAppID(
            deviceSerial: "emulator-5554",
            processIdentifier: 321,
            applicationIdentifier: "com.example.demo",
            runtimeInstanceIdentifier: "runtime-42"
        ).rawValue

        XCTAssertThrowsError(try provider.capture(
            appId: appID,
            options: ScreenshotCaptureOptions(
                target: .virtualDevice,
                targetIdentifier: "emulator-5556"
            ),
            screenMetadata: screenMetadata
        )) { error in
            XCTAssertEqual(
                CLIError.code(for: error),
                "invalid_argument"
            )
        }
    }

    func testProviderReportsLockedDeviceBeforeCapture() throws {
        let runner = ScreenshotADBCommandRunner(results: [
            commandOutput("topResumedActivity=ActivityRecord{42 u0 com.example.demo/.MainActivity t1}\n"),
            commandOutput("isStatusBarKeyguard=true\n")
        ])
        let provider = AndroidSystemScreenshotProvider(
            adbClient: ADBClient(commandRunner: runner)
        )
        let appID = AndroidRuntimeAppID(
            deviceSerial: "568ced7b",
            processIdentifier: 321,
            applicationIdentifier: "com.example.demo",
            runtimeInstanceIdentifier: "runtime-42"
        ).rawValue

        var didReadScreenMetadata = false
        XCTAssertThrowsError(try provider.capture(
            appId: appID,
            options: ScreenshotCaptureOptions(
                target: .physicalDevice,
                targetIdentifier: "568ced7b"
            ),
            screenMetadata: {
                didReadScreenMetadata = true
                return self.screenMetadata()
            }
        )) { error in
            XCTAssertEqual(CLIError.code(for: error), "android_device_locked")
        }
        XCTAssertFalse(didReadScreenMetadata)
        XCTAssertFalse(runner.invocations.contains {
            $0.suffix(3) == ["exec-out", "screencap", "-p"]
        })
    }

    func testProviderReportsWhenTargetAppIsNotForeground() throws {
        let runner = ScreenshotADBCommandRunner(results: [
            commandOutput("topResumedActivity=ActivityRecord{42 u0 com.other.app/.MainActivity t1}\n"),
            commandOutput("isStatusBarKeyguard=false\n")
        ])
        let provider = AndroidSystemScreenshotProvider(
            adbClient: ADBClient(commandRunner: runner)
        )
        let appID = AndroidRuntimeAppID(
            deviceSerial: "emulator-5554",
            processIdentifier: 321,
            applicationIdentifier: "com.example.demo",
            runtimeInstanceIdentifier: "runtime-42"
        ).rawValue

        var didReadScreenMetadata = false
        XCTAssertThrowsError(try provider.capture(
            appId: appID,
            options: .automatic,
            screenMetadata: {
                didReadScreenMetadata = true
                return self.screenMetadata()
            }
        )) { error in
            XCTAssertEqual(CLIError.code(for: error), "android_target_not_foreground")
        }
        XCTAssertFalse(didReadScreenMetadata)
    }

    func testProviderRejectsCaptureWhenFocusedAppCannotBeResolved() throws {
        let runner = ScreenshotADBCommandRunner(results: [
            commandOutput("topResumedActivity=null\n"),
            commandOutput("isStatusBarKeyguard=false\n")
        ])
        let provider = AndroidSystemScreenshotProvider(
            adbClient: ADBClient(commandRunner: runner)
        )
        let appID = AndroidRuntimeAppID(
            deviceSerial: "568ced7b",
            processIdentifier: 321,
            applicationIdentifier: "com.example.demo",
            runtimeInstanceIdentifier: "runtime-42"
        ).rawValue

        XCTAssertThrowsError(try provider.capture(
            appId: appID,
            options: .automatic,
            screenMetadata: screenMetadata
        )) { error in
            XCTAssertEqual(
                CLIError.code(for: error),
                "android_foreground_app_unavailable"
            )
        }
    }

    private func screenMetadata() -> [String: Any] {
        [
            "serverVersion": "1.0.0",
            "app": [
                "bundleIdentifier": "com.example.demo",
                "screen": [
                    "width": 440.0,
                    "height": 956.0,
                    "scale": 2.5
                ]
            ]
        ]
    }

    private func commandOutput(_ value: String) -> ADBCommandResult {
        ADBCommandResult(
            standardOutput: Data(value.utf8),
            standardError: Data(),
            exitCode: 0
        )
    }
}

private final class ScreenshotADBCommandRunner: ADBCommandRunning {
    private var results: [ADBCommandResult]
    private(set) var invocations = [[String]]()

    init(results: [ADBCommandResult]) {
        self.results = results
    }

    func run(arguments: [String]) throws -> ADBCommandResult {
        invocations.append(arguments)
        return results.removeFirst()
    }
}

private struct NonBlackScreenshotInspector: ScreenshotImageContentInspecting {
    func isCompletelyBlack(_ data: Data) throws -> Bool {
        false
    }
}
