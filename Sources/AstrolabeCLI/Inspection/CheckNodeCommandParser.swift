//
//  CheckNodeCommandParser.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

struct CheckNodeCommandParser {
    func parse(arguments: [String]) throws -> CheckNodeCommand {
        var oid: String?
        var className: String?
        var text: String?
        var visibleOnly = false
        var expectedClassName: String?
        var expectedText: String?
        var expectedVisible: Bool?
        var expectedFrame: FrameExpectation?
        var tolerance = 0.0
        var index = 0

        while index < arguments.count {
            switch arguments[index] {
            case "--oid":
                guard index + 1 < arguments.count, !arguments[index + 1].isEmpty else {
                    throw CLIError.missingArgument("valid oid")
                }
                oid = arguments[index + 1]
                index += 2
            case "--class":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("className")
                }
                className = arguments[index + 1]
                index += 2
            case "--text":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("text")
                }
                text = arguments[index + 1]
                index += 2
            case "--visible-only":
                visibleOnly = true
                index += 1
            case "--expect-class":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("expectedClassName")
                }
                expectedClassName = arguments[index + 1]
                index += 2
            case "--expect-text":
                guard index + 1 < arguments.count else {
                    throw CLIError.missingArgument("expectedText")
                }
                expectedText = arguments[index + 1]
                index += 2
            case "--expect-visible":
                guard index + 1 < arguments.count, let value = parseBool(arguments[index + 1]) else {
                    throw CLIError.missingArgument("valid expectedVisible")
                }
                expectedVisible = value
                index += 2
            case "--expect-frame":
                guard index + 4 < arguments.count,
                      let x = Double(arguments[index + 1]),
                      let y = Double(arguments[index + 2]),
                      let width = Double(arguments[index + 3]),
                      let height = Double(arguments[index + 4]) else {
                    throw CLIError.missingArgument("valid expectedFrame")
                }
                expectedFrame = FrameExpectation(x: x, y: y, width: width, height: height)
                index += 5
            case "--tolerance":
                guard index + 1 < arguments.count, let value = Double(arguments[index + 1]), value >= 0 else {
                    throw CLIError.missingArgument("valid tolerance")
                }
                tolerance = value
                index += 2
            case "--json":
                index += 1
            default:
                throw CLIError.unsupportedCommand(arguments[index])
            }
        }

        let expectation = NodeExpectation(
            className: expectedClassName,
            text: expectedText,
            visible: expectedVisible,
            frame: expectedFrame,
            tolerance: tolerance
        )
        guard expectation.hasAnyExpectation else {
            throw CLIError.missingArgument("at least one expectation")
        }
        return CheckNodeCommand(
            query: HierarchyNodeQuery(oid: oid, className: className, text: text, visibleOnly: visibleOnly, limit: nil),
            expectation: expectation
        )
    }

    private func parseBool(_ value: String) -> Bool? {
        switch value.lowercased() {
        case "true", "1", "yes":
            return true
        case "false", "0", "no":
            return false
        default:
            return nil
        }
    }
}
