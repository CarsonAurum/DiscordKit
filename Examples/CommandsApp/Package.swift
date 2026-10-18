// swift-tools-version: 6.4
import PackageDescription

let concurrency: [SwiftSetting] = [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)]

let package = Package(name: "CommandsApp", platforms: [.macOS(.v13)], dependencies: [
    .package(name: "DiscordKit", path: "../.."),
], targets: [
    .executableTarget(name: "CommandsApp", dependencies: [
        .product(name: "DiscordCommands", package: "DiscordKit"),
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordModels", package: "DiscordKit"),
    ], swiftSettings: concurrency),
    .testTarget(name: "CommandsAppTests", dependencies: ["CommandsApp"], swiftSettings: concurrency),
])
