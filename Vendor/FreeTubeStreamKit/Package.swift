// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FreeTubeStreamKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FreeTubeStreamKit",
            targets: ["FreeTubeStreamKit"]
        )
    ],
    targets: [
        .target(
            name: "FreeTubeStreamKit",
            resources: [.process("Resources")]
        )
    ]
)
