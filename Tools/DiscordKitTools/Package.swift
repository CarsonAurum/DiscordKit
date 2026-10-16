// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "DiscordKitTools",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DiscordKitTools", targets: ["DiscordKitTools"])],
    targets: [
        .executableTarget(
            name: "DiscordKitTools",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
                .defaultIsolation(nil),
            ]
        ),
        .testTarget(
            name: "DiscordKitToolsTests",
            dependencies: ["DiscordKitTools"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
                .defaultIsolation(nil),
            ]
        ),
    ]
)
