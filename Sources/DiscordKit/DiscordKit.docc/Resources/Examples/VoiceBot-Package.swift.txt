// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "VoiceBot",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "DiscordKit", path: "../..")],
    targets: [.executableTarget(name: "VoiceBot", dependencies: [
        .product(name: "DiscordMedia", package: "DiscordKit"),
        .product(name: "DiscordVoice", package: "DiscordKit"),
        .product(name: "DiscordVoiceCodecs", package: "DiscordKit"),
        .product(name: "DiscordVoiceCrypto", package: "DiscordKit"),
        .product(name: "DiscordMLS", package: "DiscordKit"),
        .product(name: "DiscordDAVE", package: "DiscordKit"),
        .product(name: "DiscordModels", package: "DiscordKit"),
    ], swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)])]
)
