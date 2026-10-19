// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "VoiceSessionQualification",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "DiscordKit", path: "../..")],
    targets: [.executableTarget(name: "VoiceSessionQualification", dependencies: [
        .product(name: "DiscordLogging", package: "DiscordKit"),
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordModels", package: "DiscordKit"),
        .product(name: "DiscordTransport", package: "DiscordKit"),
        .product(name: "DiscordNIOTransport", package: "DiscordKit"),
        .product(name: "DiscordMedia", package: "DiscordKit"),
        .product(name: "DiscordVoiceCodecs", package: "DiscordKit"),
        .product(name: "DiscordVoiceCrypto", package: "DiscordKit"),
        .product(name: "DiscordVoice", package: "DiscordKit"),
        .product(name: "DiscordMLS", package: "DiscordKit"),
        .product(name: "DiscordDAVE", package: "DiscordKit"),
    ], swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)])]
)
