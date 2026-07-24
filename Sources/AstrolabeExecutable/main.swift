//
//  main.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeAndroidPlatform
import AstrolabeCLI
import AstrolabeIOSHost
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let runner = try CLICommandRunner(platformModules: [
    AstrolabeIOSHostFactory.makePlatformModule(),
    AstrolabeAndroidHostFactory.makePlatformModule()
])
let exitCode = runner.runAndPrint(arguments: arguments)
runner.close()
if exitCode != 0 {
    exit(exitCode)
}
