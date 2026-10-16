// swift-tools-version: 6.4

import PackageDescription

let concurrencySettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
    .defaultIsolation(nil),
]

let package = Package(
    name: "DiscordKit",
    platforms: [
        .macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1),
    ],
    products: [
        .library(
            name: "DiscordKit",
            targets: ["DiscordKit"]
        ),
        .library(name: "DiscordBits", targets: ["DiscordBits"]),
        .library(name: "DiscordCore", targets: ["DiscordCore"]),
        .library(name: "DiscordTransport", targets: ["DiscordTransport"]),
    ],
    targets: [
        .target(
            name: "DiscordKit",
            dependencies: ["DiscordCore"],
            swiftSettings: concurrencySettings,
        ),
        .target(name: "DiscordBits", swiftSettings: concurrencySettings),
        .target(name: "DiscordCore", dependencies: ["DiscordBits"], swiftSettings: concurrencySettings),
        .target(name: "DiscordTransport", dependencies: ["DiscordCore"], swiftSettings: concurrencySettings),
        .target(
            name: "DiscordTestSupport",
            dependencies: ["DiscordCore", "DiscordTransport"],
            path: "Tests/DiscordTestSupport",
            swiftSettings: concurrencySettings
        ),
        .testTarget(
            name: "DiscordKitTests",
            dependencies: ["DiscordKit"],
            swiftSettings: concurrencySettings,
        ),
        .testTarget(name: "DiscordBitsTests", dependencies: ["DiscordBits"], swiftSettings: concurrencySettings),
        .testTarget(name: "DiscordCoreTests", dependencies: ["DiscordCore"], swiftSettings: concurrencySettings),
        .testTarget(
            name: "DiscordTransportTests",
            dependencies: ["DiscordTransport", "DiscordTestSupport"],
            swiftSettings: concurrencySettings
        ),
        .testTarget(
            name: "DiscordTestSupportTests",
            dependencies: ["DiscordTestSupport", "DiscordTransport"],
            swiftSettings: concurrencySettings
        ),
    ]
)
