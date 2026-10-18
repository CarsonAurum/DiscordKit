// swift-tools-version: 6.4
import PackageDescription

let package = Package(name: "SocialApp", platforms: [.macOS(.v13)], dependencies: [
    .package(name: "DiscordKit", path: "../.."),
], targets: [
    .executableTarget(name: "SocialApp", dependencies: [
        .product(name: "DiscordSocial", package: "DiscordKit"),
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordMedia", package: "DiscordKit"),
    ], swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)]),
])
