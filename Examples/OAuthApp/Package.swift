// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "OAuthApp",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "DiscordKit", path: "../..")],
    targets: [.executableTarget(name: "OAuthApp", dependencies: [
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordOAuth", package: "DiscordKit"),
    ], swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)])]
)
