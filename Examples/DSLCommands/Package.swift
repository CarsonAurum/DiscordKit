// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "DSLCommands",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(name: "DiscordKit", path: "../.."),
        .package(name: "DiscordDSLMacros", path: "../../Packages/DiscordDSLMacros"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "5.0.1"),
    ],
    targets: [.executableTarget(name: "DSLCommands", dependencies: [
        .product(name: "DiscordCommandDSL", package: "DiscordKit"),
        .product(name: "DiscordDSL", package: "DiscordKit"),
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordModels", package: "DiscordKit"),
        .product(name: "DiscordInteractions", package: "DiscordKit"),
        .product(name: "DiscordHTTP", package: "DiscordKit"),
        .product(name: "DiscordTransport", package: "DiscordKit"),
        .product(name: "DiscordNIOTransport", package: "DiscordKit"),
        .product(name: "DiscordDSLMacros", package: "DiscordDSLMacros"),
        .product(name: "Crypto", package: "swift-crypto"),
    ], swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)]),
    .testTarget(name: "DSLCommandsTests", dependencies: [
        "DSLCommands",
        .product(name: "DiscordCommandDSL", package: "DiscordKit"),
        .product(name: "DiscordDSL", package: "DiscordKit"),
    ], swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)])]
)
