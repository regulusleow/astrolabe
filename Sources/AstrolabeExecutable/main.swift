//
//  main.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeIOSHost
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let runner = try AstrolabeIOSHostFactory.makeCommandRunner()
let exitCode = runner.runAndPrint(arguments: arguments)
if exitCode != 0 {
    exit(exitCode)
}
