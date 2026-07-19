//
//  CLIInfrastructureTests.swift
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

final class CLIInfrastructureTests: XCTestCase {
    func testCLIErrorProvidesStableCodeAndRecoverySuggestion() {
        let error = CLIError.missingArgument("appId")

        XCTAssertEqual(error.code, "missing_argument")
        XCTAssertEqual(error.recoverySuggestion, "Provide the missing argument and try again")

        let commandError = CLIError.commandFailed("xcrun exit code 1")

        XCTAssertEqual(commandError.code, "command_failed")
        XCTAssertEqual(commandError.recoverySuggestion, "Verify local command-line tools, device connectivity, and execution permissions, then try again")
    }

    func testCLIErrorMapsCocoaFileErrorsToStableCode() {
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadNoSuchFileError,
            userInfo: [NSLocalizedDescriptionKey: "File not found"]
        )

        XCTAssertEqual(CLIError.code(for: error), "file_io_failed")
        XCTAssertEqual(CLIError.recoverySuggestion(for: error), "Check that input and output paths exist and have the required permissions")
    }

}
