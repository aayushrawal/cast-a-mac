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
        .executable(name: "cast-host", targets: ["CastHost"])
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
            dependencies: ["CastMedia"],
            linkerSettings: [
                .linkedFramework("Network")
            ]
        ),
        .executableTarget(
            name: "CastHost",
            dependencies: ["CastMedia", "CastTransport"],
            linkerSettings: [
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("VideoToolbox")
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
