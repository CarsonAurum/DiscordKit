// swift-tools-version: 6.4
import PackageDescription

let settings: [SwiftSetting] = [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)]
let package = Package(name: "ActivityHost", platforms: [.macOS(.v13)], products: [
    .library(name: "ActivityHostSupport", targets: ["ActivityHostSupport"]),
    .library(name: "ActivityBackend", targets: ["ActivityBackend"]),
], dependencies: [.package(name: "DiscordKit", path: "../..")], targets: [
    .target(name: "ActivityHostSupport", dependencies: [
        .product(name: "DiscordActivities", package: "DiscordKit"), .product(name: "DiscordCore", package: "DiscordKit"),
    ], swiftSettings: settings),
    .executableTarget(name: "ActivityHost", dependencies: ["ActivityHostSupport"], swiftSettings: settings),
    .target(name: "ActivityBackend", dependencies: [
        .product(name: "DiscordOAuth", package: "DiscordKit"), .product(name: "DiscordCommerce", package: "DiscordKit"),
        .product(name: "DiscordHTTP", package: "DiscordKit"), .product(name: "DiscordModels", package: "DiscordKit"),
        .product(name: "DiscordCore", package: "DiscordKit"),
    ], swiftSettings: settings),
    .testTarget(name: "ActivityHostTests", dependencies: ["ActivityHostSupport", "ActivityBackend"], swiftSettings: settings),
])
