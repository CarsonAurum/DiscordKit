// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "HTTPApp",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "DiscordKit", path: "../..")],
    targets: [.executableTarget(name: "HTTPApp", dependencies: [
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordModels", package: "DiscordKit"),
        .product(name: "DiscordTransport", package: "DiscordKit"),
        .product(name: "DiscordInteractions", package: "DiscordKit"),
        .product(name: "DiscordCommands", package: "DiscordKit"),
        .product(name: "DiscordNIOTransport", package: "DiscordKit"),
    ], swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)])]
)
