//
//  MacOSDiscoveryTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/11/20.
//

@testable import AstrolabeCLI
@testable import AstrolabeMacOSHost
import AstrolabeRuntimeHostCore
import XCTest

final class MacOSDiscoveryTests: XCTestCase {
    func testDecodeFailureIsReportedAndLaterPortsAreStillScanned() throws {
        let clientFactory = FailingDiscoveryClientFactory()
        let provider = AstrolabeMacOSRuntimeProvider(discoveryClient: clientFactory)

        XCTAssertTrue(try provider.fetchApps().isEmpty)
        XCTAssertEqual(clientFactory.attemptedPorts, Array(47_230...47_239))
        let diagnostics = provider.appDiscoveryDiagnostics()
        XCTAssertEqual(diagnostics.map(\.endpointPort), [47_230])
        XCTAssertEqual(diagnostics.map(\.errorCode), ["astrolabe_runtime_invalid_response"])
    }
}

private final class FailingDiscoveryClientFactory: AstrolabeRuntimeClientCreating {
    /// Ports visited during this discovery pass, in scan order.
    private(set) var attemptedPorts = [UInt16]()

    func makeClient(endpoint: AstrolabeRuntimeEndpoint) throws -> any AstrolabeRuntimeClient {
        attemptedPorts.append(endpoint.port)
        if attemptedPorts.count == 1 {
            throw DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: "Missing runtime identifier"))
        }
        throw AstrolabeRuntimeClientError.connectionClosed
    }
}
