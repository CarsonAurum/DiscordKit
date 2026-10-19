// swift-tools-version: 6.4
import PackageDescription

let settings: [SwiftSetting] = [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)]
let package = Package(
    name: "DiscordDSLBenchmarks",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "DiscordKit", path: "../..")],
    targets: [
        .executableTarget(name: "DiscordDSLBenchmarks", dependencies: [
            .product(name: "DiscordDSL", package: "DiscordKit"),
            .product(name: "DiscordCommandDSL", package: "DiscordKit"),
            .product(name: "DiscordCommands", package: "DiscordKit"),
            .product(name: "DiscordCore", package: "DiscordKit"),
            .product(name: "DiscordModels", package: "DiscordKit"),
            .product(name: "DiscordInteractions", package: "DiscordKit"),
        ], swiftSettings: settings),
        .testTarget(name: "DiscordDSLBenchmarksTests", dependencies: [
            "DiscordDSLBenchmarks",
            .product(name: "DiscordCommandDSL", package: "DiscordKit"),
            .product(name: "DiscordCore", package: "DiscordKit"),
            .product(name: "DiscordInteractions", package: "DiscordKit"),
        ], swiftSettings: settings),
    ]
)
