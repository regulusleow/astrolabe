//
//  ADBDeviceSupportTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import Foundation
import XCTest
@testable import AstrolabeAndroidDeviceSupport

final class ADBDeviceSupportTests: XCTestCase {
    func testDeviceParserSeparatesReadyEmulatorUSBAndUnavailableDevices() throws {
        let output = """
        List of devices attached
        emulator-5554 device product:sdk_gphone64_arm64 model:sdk_gphone64_arm64 device:emu64a transport_id:1
        568ced7b device usb:1310720X product:OnePlus9_CH model:LE2110 device:OnePlus9 transport_id:2
        192.0.2.1:5555 unauthorized transport_id:3
        stale-device offline transport_id:4

        """

        let snapshot = ADBDeviceListParser().parse(output)

        XCTAssertEqual(snapshot.readyDevices.map(\.serial), ["emulator-5554", "568ced7b"])
        XCTAssertEqual(snapshot.readyDevices.map(\.connectionKind), [.emulator, .usb])
        XCTAssertEqual(snapshot.readyDevices.map(\.model), ["sdk_gphone64_arm64", "LE2110"])
        XCTAssertEqual(snapshot.unavailableDevices.map(\.serial), ["192.0.2.1:5555", "stale-device"])
        XCTAssertEqual(snapshot.unavailableDevices.map(\.state), [.unauthorized, .offline])
    }

    func testConnectionKindClassifiesSerialsWithoutADBMetadata() {
        XCTAssertEqual(
            ADBDeviceConnectionKind.classify(serial: "emulator-5554"),
            .emulator
        )
        XCTAssertEqual(
            ADBDeviceConnectionKind.classify(serial: "568ced7b"),
            .usb
        )
        XCTAssertEqual(
            ADBDeviceConnectionKind.classify(serial: "192.0.2.1:5555"),
            .wireless
        )
        XCTAssertEqual(
            ADBDeviceConnectionKind.classify(
                serial: "adb-serial._adb-tls-connect._tcp"
            ),
            .wireless
        )
    }

    func testClientTargetsEveryDeviceScopedCommandBySerial() throws {
        let runner = RecordingADBCommandRunner(results: [
            ADBCommandResult(
                standardOutput: Data("""
                Num RefCount Protocol Flags Type St Inode Path
                0: 2 0 10000 1 01 1993981 @astrolabe_123
                0: 2 0 10000 1 01 1993982 @other_socket
                0: 2 0 10000 1 01 1993983 @astrolabe_456

                """.utf8),
                standardError: Data(),
                exitCode: 0
            ),
            ADBCommandResult(standardOutput: Data("47231\n".utf8), standardError: Data(), exitCode: 0),
            ADBCommandResult(standardOutput: Data(), standardError: Data(), exitCode: 0)
        ])
        let client = ADBClient(commandRunner: runner)

        XCTAssertEqual(
            try client.abstractSocketNames(deviceSerial: "emulator-5554"),
            ["astrolabe_123", "other_socket", "astrolabe_456"]
        )
        XCTAssertEqual(
            try client.forward(
                deviceSerial: "emulator-5554",
                socketName: "astrolabe_123"
            ),
            47_231
        )
        try client.removeForward(deviceSerial: "emulator-5554", localPort: 47_231)

        XCTAssertEqual(runner.invocations, [
            ["-s", "emulator-5554", "shell", "cat", "/proc/net/unix"],
            ["-s", "emulator-5554", "forward", "tcp:0", "localabstract:astrolabe_123"],
            ["-s", "emulator-5554", "forward", "--remove", "tcp:47231"]
        ])
    }

    func testUnixSocketParserReturnsOnlyNamedAbstractSockets() {
        let output = """
        Num RefCount Protocol Flags Type St Inode Path
        0000: 00000002 00000000 00010000 0001 01 1993981 @astrolabe_4742
        0000: 00000002 00000000 00010000 0001 01 21762 /dev/socket/zygote
        0000: 00000003 00000000 00000000 0001 03 1993989
        0000: 00000002 00000000 00010000 0001 01 1993990 @astrolabe_4742
        """

        XCTAssertEqual(
            ADBUnixSocketListParser().abstractSocketNames(from: output),
            ["astrolabe_4742"]
        )
    }

    func testForwardLeaseRemovesItsBindingOnlyOnce() throws {
        let runner = RecordingADBCommandRunner(results: [
            ADBCommandResult(standardOutput: Data("47231\n".utf8), standardError: Data(), exitCode: 0),
            ADBCommandResult(standardOutput: Data(), standardError: Data(), exitCode: 0)
        ])
        let client = ADBClient(commandRunner: runner)
        let lease = try ADBForwardLease.open(
            client: client,
            deviceSerial: "emulator-5554",
            socketName: "astrolabe_123"
        )

        XCTAssertEqual(lease.localPort, 47_231)
        lease.close()
        lease.close()

        XCTAssertEqual(runner.invocations.last, [
            "-s", "emulator-5554", "forward", "--remove", "tcp:47231"
        ])
        XCTAssertEqual(runner.invocations.count, 2)
    }
}

private final class RecordingADBCommandRunner: ADBCommandRunning {
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
