// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "DiscordKit",
    products: [
        .library(
            name: "DiscordKit",
            targets: ["DiscordKit"]
        ),
    ],
    targets: [
        .target(
            name: "DiscordKit",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
        .testTarget(
            name: "DiscordKitTests",
            dependencies: ["DiscordKit"],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
            ],
        ),
    ]
)
