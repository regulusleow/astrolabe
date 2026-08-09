//
//  RuntimeUIGraphCommandParserTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/4.
//

import XCTest
@testable import AstrolabeCLI

final class RuntimeUIGraphCommandParserTests: XCTestCase {
    func testParserBuildsTypedQueryWithDefaults() throws {
        let command = try RuntimeUIGraphCommandParser().parse(arguments: [
            "--root-oid", "view-1",
            "--relation", "ios.view.backingLayer",
            "--relation", "tree.layerChild",
            "--json"
        ])

        XCTAssertEqual(command.rootNodeID.rawValue, "view-1")
        XCTAssertEqual(
            command.relationTypes.map(\.rawValue).sorted(),
            ["ios.view.backingLayer", "tree.layerChild"]
        )
        XCTAssertEqual(command.direction, .outgoing)
        XCTAssertEqual(command.maximumDepth, 2)
        XCTAssertEqual(command.nodeLimit, 20)
        XCTAssertEqual(command.relationLimit, 30)
        XCTAssertEqual(command.byteLimit, 32_768)
    }

    func testParserAcceptsUpperBoundsAndIncomingDirection() throws {
        let command = try RuntimeUIGraphCommandParser().parse(arguments: [
            "--root-oid", "layer-1",
            "--relation", "vendor.customRelation",
            "--direction", "incoming",
            "--max-depth", "4",
            "--node-limit", "100",
            "--relation-limit", "200",
            "--byte-limit", "262144"
        ])

        XCTAssertEqual(command.direction, .incoming)
        XCTAssertEqual(command.maximumDepth, 4)
        XCTAssertEqual(command.nodeLimit, 100)
        XCTAssertEqual(command.relationLimit, 200)
        XCTAssertEqual(command.byteLimit, 262_144)
    }

    func testParserRejectsMissingAndMalformedIdentifiers() {
        let invalidArguments = [
            ["--relation", "tree.layerChild"],
            ["--root-oid", "view-1"],
            ["--root-oid", "", "--relation", "tree.layerChild"],
            ["--root-oid", "view-1", "--relation", "layerChild"]
        ]

        for arguments in invalidArguments {
            XCTAssertThrowsError(
                try RuntimeUIGraphCommandParser().parse(arguments: arguments)
            ) { error in
                XCTAssertEqual(CLIError.code(for: error), "missing_argument")
            }
        }
    }

    func testParserRejectsInvalidDirectionAndEveryNumericBoundary() {
        let invalidOptions = [
            ["--direction", "sideways"],
            ["--max-depth", "0"],
            ["--max-depth", "5"],
            ["--node-limit", "0"],
            ["--node-limit", "101"],
            ["--relation-limit", "0"],
            ["--relation-limit", "201"],
            ["--byte-limit", "1023"],
            ["--byte-limit", "262145"]
        ]

        for option in invalidOptions {
            let arguments = [
                "--root-oid", "view-1",
                "--relation", "tree.viewChild"
            ] + option
            XCTAssertThrowsError(
                try RuntimeUIGraphCommandParser().parse(arguments: arguments)
            ) { error in
                XCTAssertEqual(CLIError.code(for: error), "missing_argument")
            }
        }
    }

    func testParserRejectsUnknownArguments() {
        XCTAssertThrowsError(try RuntimeUIGraphCommandParser().parse(arguments: [
            "--root-oid", "view-1",
            "--relation", "tree.viewChild",
            "--unknown"
        ])) { error in
            XCTAssertEqual(CLIError.code(for: error), "unsupported_command")
        }
    }
}
