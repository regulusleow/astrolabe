// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "astrolabe",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "astrolabe", targets: ["AstrolabeExecutable"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/regulusleow/astrolabe-protocol.git",
            exact: "1.0.0"
        )
    ],
    targets: [
        .target(
            name: "AstrolabeCoreObjC",
            path: "Sources/AstrolabeCoreObjC",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("USBMux")
            ],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .target(
            name: "AstrolabeCLI",
            dependencies: [
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ],
            path: "Sources/AstrolabeCLI"
        ),
        .target(
            name: "AstrolabeIOSInspection",
            dependencies: ["AstrolabeCLI"],
            path: "Sources/AstrolabeIOSInspection"
        ),
        .target(
            name: "AstrolabeAndroidInspection",
            dependencies: ["AstrolabeCLI"],
            path: "Sources/AstrolabeAndroidInspection"
        ),
        .target(
            name: "AstrolabeAndroidDeviceSupport",
            path: "Sources/AstrolabeAndroidDeviceSupport"
        ),
        .target(
            name: "AstrolabeRuntimeHostCore",
            dependencies: [
                "AstrolabeCLI",
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ],
            path: "Sources/AstrolabeRuntimeHostCore"
        ),
        .target(
            name: "AstrolabeScreenshotSupport",
            dependencies: ["AstrolabeCLI"],
            path: "Sources/AstrolabeScreenshotSupport"
        ),
        .target(
            name: "AstrolabeAndroidHost",
            dependencies: [
                "AstrolabeAndroidDeviceSupport",
                "AstrolabeCLI",
                "AstrolabeRuntimeHostCore",
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ],
            path: "Sources/AstrolabeAndroidHost"
        ),
        .target(
            name: "AstrolabeAndroidScreenshot",
            dependencies: [
                "AstrolabeAndroidDeviceSupport",
                "AstrolabeAndroidHost",
                "AstrolabeCLI",
                "AstrolabeScreenshotSupport"
            ],
            path: "Sources/AstrolabeAndroidScreenshot"
        ),
        .target(
            name: "AstrolabeAndroidPlatform",
            dependencies: [
                "AstrolabeAndroidHost",
                "AstrolabeAndroidInspection",
                "AstrolabeAndroidScreenshot",
                "AstrolabeCLI"
            ],
            path: "Sources/AstrolabeAndroidPlatform"
        ),
        .target(
            name: "AstrolabeIOSDeviceSupport",
            dependencies: ["AstrolabeCoreObjC"],
            path: "Sources/AstrolabeIOSDeviceSupport"
        ),
        .target(
            name: "AstrolabeIOSScreenshot",
            dependencies: [
                "AstrolabeCLI",
                "AstrolabeIOSDeviceSupport",
                "AstrolabeScreenshotSupport"
            ],
            path: "Sources/AstrolabeIOSScreenshot"
        ),
        .target(
            name: "AstrolabeIOSHost",
            dependencies: [
                "AstrolabeCLI",
                "AstrolabeCoreObjC",
                "AstrolabeIOSDeviceSupport",
                "AstrolabeIOSInspection",
                "AstrolabeIOSScreenshot",
                "AstrolabeRuntimeHostCore",
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ],
            path: "Sources/AstrolabeIOSHost"
        ),
        .executableTarget(
            name: "AstrolabeExecutable",
            dependencies: [
                "AstrolabeAndroidPlatform",
                "AstrolabeCLI",
                "AstrolabeIOSHost"
            ],
            path: "Sources/AstrolabeExecutable"
        ),
        .testTarget(
            name: "AstrolabeCLITests",
            dependencies: ["AstrolabeCLI"],
            path: "Tests/AstrolabeCLITests"
        ),
        .testTarget(
            name: "AstrolabeAndroidInspectionTests",
            dependencies: [
                "AstrolabeAndroidInspection",
                "AstrolabeCLI",
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ],
            path: "Tests/AstrolabeAndroidInspectionTests"
        ),
        .testTarget(
            name: "AstrolabeAndroidDeviceSupportTests",
            dependencies: ["AstrolabeAndroidDeviceSupport"],
            path: "Tests/AstrolabeAndroidDeviceSupportTests"
        ),
        .testTarget(
            name: "AstrolabeAndroidHostTests",
            dependencies: [
                "AstrolabeAndroidDeviceSupport",
                "AstrolabeAndroidHost",
                "AstrolabeCLI",
                "AstrolabeRuntimeHostCore",
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ],
            path: "Tests/AstrolabeAndroidHostTests"
        ),
        .testTarget(
            name: "AstrolabeAndroidScreenshotTests",
            dependencies: [
                "AstrolabeAndroidDeviceSupport",
                "AstrolabeAndroidHost",
                "AstrolabeAndroidScreenshot",
                "AstrolabeCLI",
                "AstrolabeScreenshotSupport"
            ],
            path: "Tests/AstrolabeAndroidScreenshotTests"
        ),
        .testTarget(
            name: "AstrolabeAndroidPlatformTests",
            dependencies: ["AstrolabeAndroidPlatform"],
            path: "Tests/AstrolabeAndroidPlatformTests"
        ),
        .testTarget(
            name: "AstrolabeIOSHostTests",
            dependencies: [
                "AstrolabeCLI",
                "AstrolabeIOSDeviceSupport",
                "AstrolabeIOSHost",
                "AstrolabeIOSInspection",
                "AstrolabeIOSScreenshot",
                "AstrolabeRuntimeHostCore",
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ],
            path: "Tests/AstrolabeIOSHostTests"
        )
    ]
)
