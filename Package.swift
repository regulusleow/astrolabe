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
            name: "AstrolabeIOSDeviceSupport",
            dependencies: ["AstrolabeCoreObjC"],
            path: "Sources/AstrolabeIOSDeviceSupport"
        ),
        .target(
            name: "AstrolabeIOSScreenshot",
            dependencies: ["AstrolabeCLI", "AstrolabeIOSDeviceSupport"],
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
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ],
            path: "Sources/AstrolabeIOSHost"
        ),
        .executableTarget(
            name: "AstrolabeExecutable",
            dependencies: ["AstrolabeCLI", "AstrolabeIOSHost"],
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
            name: "AstrolabeIOSHostTests",
            dependencies: [
                "AstrolabeCLI",
                "AstrolabeIOSDeviceSupport",
                "AstrolabeIOSHost",
                "AstrolabeIOSInspection",
                "AstrolabeIOSScreenshot",
                .product(
                    name: "AstrolabeProtocol",
                    package: "astrolabe-protocol"
                )
            ],
            path: "Tests/AstrolabeIOSHostTests"
        )
    ]
)
