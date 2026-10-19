// swift-tools-version: 6.4
import PackageDescription

let concurrency: [SwiftSetting] = [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)]

let package = Package(name: "DiscordDSLExtensions", platforms: [.macOS(.v13)], products: [
    .library(name: "DiscordCommandExtensions", targets: ["DiscordCommandExtensions"]),
    .library(name: "DiscordBotExtensions", targets: ["DiscordBotExtensions"]),
], dependencies: [.package(name: "DiscordKit", path: "../..")], targets: [
    .target(name: "DiscordCommandExtensions", dependencies: [
        .product(name: "DiscordCommandDSL", package: "DiscordKit"),
        .product(name: "DiscordCommands", package: "DiscordKit"),
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordDSL", package: "DiscordKit"),
        .product(name: "DiscordInteractions", package: "DiscordKit"),
        .product(name: "DiscordModels", package: "DiscordKit"),
    ], swiftSettings: concurrency),
    .target(name: "DiscordBotExtensions", dependencies: [
        .product(name: "DiscordBotDSL", package: "DiscordKit"),
        .product(name: "DiscordDSL", package: "DiscordKit"),
        .product(name: "DiscordGateway", package: "DiscordKit"),
        .product(name: "DiscordModels", package: "DiscordKit"),
    ], swiftSettings: concurrency),
    .testTarget(name: "DiscordCommandExtensionsTests", dependencies: ["DiscordCommandExtensions",
        .product(name: "DiscordCommandDSL", package: "DiscordKit"),
        .product(name: "DiscordDSL", package: "DiscordKit"),
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordModels", package: "DiscordKit"),
    ], path: "Tests/DiscordCommandExtensionsTests", swiftSettings: concurrency),
])
