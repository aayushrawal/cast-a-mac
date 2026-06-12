// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CastAMac",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "CastCore", targets: ["CastCore"]),
        .library(name: "CastMedia", targets: ["CastMedia"]),
        .library(name: "CastTransport", targets: ["CastTransport"]),
        .library(name: "CastHostKit", targets: ["CastHostKit"]),
        .executable(name: "cast-host", targets: ["CastHost"]),
        .executable(name: "cast-host-app", targets: ["CastHostApp"])
    ],
    targets: [
        .target(name: "CastCore"),
        .target(
            name: "CastMedia",
            linkerSettings: [
                .linkedFramework("CoreMedia"),
                .linkedFramework("VideoToolbox")
            ]
        ),
        .target(
            name: "CastTransport",
            dependencies: ["CastCore", "CastMedia"],
            linkerSettings: [
                .linkedFramework("Network")
            ]
        ),
        .target(
            name: "CastHostKit",
            dependencies: ["CastCore", "CastMedia", "CastTransport"],
            linkerSettings: [
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("IOKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox")
            ]
        ),
        .executableTarget(
            name: "CastHost",
            dependencies: ["CastHostKit"]
        ),
        .executableTarget(
            name: "CastHostApp",
            dependencies: ["CastHostKit"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "CastCoreTests",
            dependencies: ["CastCore"]
        ),
        .testTarget(
            name: "CastMediaTests",
            dependencies: ["CastMedia"]
        )
    ]
)
