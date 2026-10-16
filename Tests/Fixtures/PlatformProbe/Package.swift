// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "DiscordKitPlatformProbe",
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", exact: "2.104.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", exact: "2.37.5"),
    ],
    targets: [
        .testTarget(
            name: "PlatformProbeTests",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ],
            resources: [.copy("Resources")],
            swiftSettings: [
                .defaultIsolation(nil),
                .enableUpcomingFeature("ApproachableConcurrency"),
            ]
        ),
    ]
)
