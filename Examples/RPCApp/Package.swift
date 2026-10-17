// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "RPCApp",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "DiscordKit", path: "../..")],
    targets: [.executableTarget(name: "RPCApp", dependencies: [
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordTransport", package: "DiscordKit"),
        .product(name: "DiscordRPC", package: "DiscordKit"),
        .product(name: "DiscordCertifiedDevices", package: "DiscordKit"),
    ], swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)])]
)
