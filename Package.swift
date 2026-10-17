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
        .library(name: "DiscordFoundationTransport", targets: ["DiscordFoundationTransport"]),
        .library(name: "DiscordNIOTransport", targets: ["DiscordNIOTransport"]),
        .library(name: "DiscordUnixPlatform", targets: ["DiscordUnixPlatform"]),
        .library(name: "DiscordApplePlatform", targets: ["DiscordApplePlatform"]),
        .library(name: "DiscordModels", targets: ["DiscordModels"]),
        .library(name: "DiscordHTTP", targets: ["DiscordHTTP"]),
        .library(name: "DiscordGateway", targets: ["DiscordGateway"]),
        .library(name: "DiscordCache", targets: ["DiscordCache"]),
        .library(name: "DiscordClient", targets: ["DiscordClient"]),
        .library(name: "DiscordInteractions", targets: ["DiscordInteractions"]),
        .library(name: "DiscordCommands", targets: ["DiscordCommands"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.104.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.37.5"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.1"),
    ],
    targets: [
        .target(
            name: "DiscordKit",
            dependencies: ["DiscordCore", "DiscordClient", "DiscordGateway", "DiscordTransport", "DiscordCommands", "DiscordInteractions"],
            swiftSettings: concurrencySettings,
        ),
        .target(name: "DiscordBits", swiftSettings: concurrencySettings),
        .target(name: "DiscordCore", dependencies: ["DiscordBits"], swiftSettings: concurrencySettings),
        .target(name: "DiscordTransport", dependencies: ["DiscordCore"], swiftSettings: concurrencySettings),
        .target(name: "DiscordModels", dependencies: ["DiscordCore"], swiftSettings: concurrencySettings),
        .target(name: "DiscordHTTP", dependencies: ["DiscordModels", "DiscordTransport"], swiftSettings: concurrencySettings),
        .target(name: "DiscordGateway", dependencies: ["DiscordCore", "DiscordModels", "DiscordTransport", "DiscordHTTP"], swiftSettings: concurrencySettings),
        .target(name: "DiscordCache", dependencies: ["DiscordBits", "DiscordCore", "DiscordModels"], swiftSettings: concurrencySettings),
        .target(name: "DiscordClient", dependencies: ["DiscordCore", "DiscordModels", "DiscordHTTP", "DiscordGateway", "DiscordCache", "DiscordTransport"], swiftSettings: concurrencySettings),
        .target(name: "DiscordInteractions", dependencies: ["DiscordCore", "DiscordModels", "DiscordHTTP", "DiscordTransport", .product(name: "Crypto", package: "swift-crypto")], swiftSettings: concurrencySettings),
        .target(name: "DiscordCommands", dependencies: ["DiscordInteractions", "DiscordHTTP", "DiscordModels", "DiscordCore"], swiftSettings: concurrencySettings),
        .target(name: "DiscordFoundationTransport", dependencies: ["DiscordTransport"], swiftSettings: concurrencySettings),
        .target(
            name: "DiscordNIOTransport",
            dependencies: [
                "DiscordTransport",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ],
            swiftSettings: concurrencySettings
        ),
        .target(
            name: "DiscordUnixPlatform",
            dependencies: [
                "DiscordTransport",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
            ],
            swiftSettings: concurrencySettings
        ),
        .target(name: "DiscordApplePlatform", dependencies: ["DiscordCore", "DiscordTransport"], swiftSettings: concurrencySettings),
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
        .testTarget(name: "DiscordModelsTests", dependencies: ["DiscordModels", "DiscordCore"], exclude: ["Fixtures"], swiftSettings: concurrencySettings),
        .testTarget(name: "DiscordHTTPTests", dependencies: ["DiscordHTTP", "DiscordModels", "DiscordCore", "DiscordTransport", "DiscordTestSupport"], swiftSettings: concurrencySettings),
        .testTarget(name: "DiscordGatewayTests", dependencies: ["DiscordGateway", "DiscordHTTP", "DiscordCore", "DiscordTransport", "DiscordTestSupport"], swiftSettings: concurrencySettings),
        .testTarget(name: "DiscordCacheTests", dependencies: ["DiscordCache", "DiscordModels", "DiscordBits", "DiscordCore", "DiscordTestSupport"], swiftSettings: concurrencySettings),
        .testTarget(name: "DiscordClientTests", dependencies: ["DiscordClient", "DiscordCache", "DiscordGateway", "DiscordHTTP", "DiscordCore", "DiscordTransport", "DiscordTestSupport"], swiftSettings: concurrencySettings),
        .testTarget(name: "DiscordInteractionsTests", dependencies: ["DiscordInteractions", "DiscordHTTP", "DiscordModels", "DiscordCore", "DiscordTransport", "DiscordTestSupport", .product(name: "Crypto", package: "swift-crypto")], swiftSettings: concurrencySettings),
        .testTarget(name: "DiscordCommandsTests", dependencies: ["DiscordCommands", "DiscordInteractions", "DiscordHTTP", "DiscordModels", "DiscordCore", "DiscordTransport", "DiscordTestSupport"], swiftSettings: concurrencySettings),
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
        .testTarget(name: "DiscordFoundationTransportTests", dependencies: ["DiscordFoundationTransport", "DiscordTransport", "DiscordTestSupport"], swiftSettings: concurrencySettings),
        .testTarget(
            name: "DiscordNIOTransportTests",
            dependencies: [
                "DiscordNIOTransport", "DiscordFoundationTransport", "DiscordTransport", "DiscordTestSupport",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
                .product(name: "NIOWebSocket", package: "swift-nio"),
                .product(name: "NIOEmbedded", package: "swift-nio"),
                .product(name: "NIOConcurrencyHelpers", package: "swift-nio"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ],
            resources: [.copy("Resources")],
            swiftSettings: concurrencySettings
        ),
        .testTarget(
            name: "DiscordUnixPlatformTests",
            dependencies: ["DiscordUnixPlatform", "DiscordTransport", "DiscordTestSupport",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio")],
            swiftSettings: concurrencySettings
        ),
        .testTarget(name: "DiscordApplePlatformTests", dependencies: ["DiscordApplePlatform", "DiscordCore", "DiscordTransport", "DiscordTestSupport"], swiftSettings: concurrencySettings),
    ]
)
