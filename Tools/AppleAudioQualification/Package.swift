// swift-tools-version: 6.4
import Foundation
import PackageDescription

let concurrencySettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil),
]
let information = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Support/Info.plist").path

let package = Package(
    name: "AppleAudioQualification",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "DiscordKit", path: "../..")],
    targets: [
        .target(name: "QualificationSupport", dependencies: [
            .product(name: "DiscordApplePlatform", package: "DiscordKit"),
            .product(name: "DiscordMedia", package: "DiscordKit"),
        ], swiftSettings: concurrencySettings),
        .executableTarget(name: "AppleAudioQualification", dependencies: [
            "QualificationSupport",
            .product(name: "DiscordLogging", package: "DiscordKit"),
            .product(name: "DiscordApplePlatform", package: "DiscordKit"),
            .product(name: "DiscordMedia", package: "DiscordKit"),
            .product(name: "DiscordVoiceCodecs", package: "DiscordKit"),
        ], swiftSettings: concurrencySettings, linkerSettings: [
            .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                          "-Xlinker", "__info_plist", "-Xlinker", information]),
        ]),
        .testTarget(name: "QualificationSupportTests", dependencies: ["QualificationSupport"],
                    swiftSettings: concurrencySettings),
    ]
)
