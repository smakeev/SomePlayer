// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SomePlayer",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SomePlayer",
            targets: ["SomePlayer"]
        )
    ],
    targets: [
        .target(
            name: "SomePlayer",
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "SomePlayerTests",
            dependencies: ["SomePlayer"],
            path: "Tests/SomePlayerTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
