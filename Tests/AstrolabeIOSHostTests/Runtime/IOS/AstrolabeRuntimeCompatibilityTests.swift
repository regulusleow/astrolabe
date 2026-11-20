//
//  AstrolabeRuntimeCompatibilityTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/11/20.
//

@testable import AstrolabeCLI
import AstrolabeProtocol
import AstrolabeRuntimeHostCore
import XCTest

final class AstrolabeRuntimeCompatibilityTests: XCTestCase {
    func testReadOnlyProviderRequiresOnlyItsDeclaredWireCapabilities() throws {
        let policy = AstrolabeRuntimeCompatibilityPolicy(
            descriptor: RuntimeUIProviderDescriptor(
                identifier: "astrolabe-macos-runtime",
                platform: .macos,
                capabilities: [.appDiscovery, .hierarchy, .nodeDetail]
            ),
            runtimePackageName: "astrolabe-runtime-ios"
        )
        let runtime = try RuntimeDescriptor(
            identifier: RuntimeNamespacedIdentifier(rawValue: "astrolabe.runtime-macos"),
            version: "2.3.0",
            instanceID: RuntimeOpaqueIdentifier(rawValue: "macos-test")
        )
        let capabilities: [RuntimeCapability] = [.applicationInfo, .hierarchySnapshot, .nodeDetail]
        func evaluate(platform: String, capabilities: [RuntimeCapability]) -> AstrolabeRuntimeCompatibility {
            policy.evaluate(handshake: RuntimeHandshakePayload(
                runtime: runtime,
                platform: platform,
                negotiatedProtocolVersion: RuntimeProtocolVersion(major: 2, minor: 0),
                capabilities: capabilities,
                extensions: nil
            ))
        }

        let readOnly = evaluate(platform: "macos", capabilities: capabilities)
        XCTAssertEqual(readOnly.record.status, .compatible)
        XCTAssertEqual(readOnly.supportedProviderCapabilities, [.appDiscovery, .hierarchy, .nodeDetail])
        XCTAssertEqual(evaluate(platform: "macos", capabilities: [.applicationInfo, .hierarchySnapshot]).record.status,
                       .updateRequired)
        XCTAssertEqual(evaluate(platform: "ios", capabilities: capabilities).record.status, .incompatible)
    }
}
