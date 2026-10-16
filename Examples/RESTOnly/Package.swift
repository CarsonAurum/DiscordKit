// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "RESTOnly",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "DiscordKit", path: "../..")],
    targets: [.executableTarget(name: "RESTOnly", dependencies: [
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordHTTP", package: "DiscordKit"),
        .product(name: "DiscordFoundationTransport", package: "DiscordKit"),
    ], swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)])]
)
