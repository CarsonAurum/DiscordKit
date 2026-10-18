// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "DiscordKitTools",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DiscordKitTools", targets: ["DiscordKitTools"])],
    dependencies: [
        // Development-only parser, aligned to the required Swift 6.4 toolchain.
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "DiscordKitTools",
            dependencies: [
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
                .defaultIsolation(nil),
            ]
        ),
        .testTarget(
            name: "DiscordKitToolsTests",
            dependencies: ["DiscordKitTools"],
            exclude: ["Fixtures"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
                .defaultIsolation(nil),
            ]
        ),
    ]
)
