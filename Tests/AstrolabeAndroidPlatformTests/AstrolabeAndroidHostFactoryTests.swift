//
//  AstrolabeAndroidHostFactoryTests.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/22.
//

import AstrolabeAndroidPlatform
import XCTest

final class AstrolabeAndroidHostFactoryTests: XCTestCase {
    func testFactoryBuildsCompleteAndroidPlatformModule() throws {
        _ = try AstrolabeAndroidHostFactory.makePlatformModule()
    }
}
