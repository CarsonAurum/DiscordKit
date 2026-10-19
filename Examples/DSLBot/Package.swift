// swift-tools-version: 6.4
import PackageDescription

let concurrency: [SwiftSetting] = [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)]

let package = Package(name: "DSLBot", platforms: [.macOS(.v13)], dependencies: [
    .package(name: "DiscordKit", path: "../.."),
], targets: [
    .executableTarget(name: "DSLBot", dependencies: [
        .product(name: "DiscordBotDSL", package: "DiscordKit"),
        .product(name: "DiscordClient", package: "DiscordKit"),
        .product(name: "DiscordCommandDSL", package: "DiscordKit"),
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordDSL", package: "DiscordKit"),
        .product(name: "DiscordGateway", package: "DiscordKit"),
        .product(name: "DiscordHTTP", package: "DiscordKit"),
        .product(name: "DiscordInteractions", package: "DiscordKit"),
        .product(name: "DiscordModels", package: "DiscordKit"),
        .product(name: "DiscordTransport", package: "DiscordKit"),
    ], swiftSettings: concurrency),
    .testTarget(name: "DSLBotTests", dependencies: ["DSLBot",
        .product(name: "DiscordBotDSL", package: "DiscordKit"),
    ], swiftSettings: concurrency),
])
