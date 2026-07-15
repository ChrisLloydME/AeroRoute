// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AeroRouteCore",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "AeroRouteCore", targets: ["AeroRouteCore"]),
    ],
    targets: [
        .target(
            name: "AeroRouteCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "AeroRouteCoreTests",
            dependencies: ["AeroRouteCore"]
        ),
    ]
)
