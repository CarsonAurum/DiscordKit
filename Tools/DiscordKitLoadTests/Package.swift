// swift-tools-version: 6.4
import PackageDescription

let concurrencySettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
    .defaultIsolation(nil),
]

let package = Package(
    name: "DiscordKitLoadTests",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "DiscordKit", path: "../..")],
    targets: [
        .executableTarget(
            name: "DiscordKitLoadTests",
            dependencies: [
                .product(name: "DiscordTransport", package: "DiscordKit"),
                .product(name: "DiscordNIOTransport", package: "DiscordKit"),
            ],
            swiftSettings: concurrencySettings
        ),
        .testTarget(
            name: "DiscordKitLoadTestsTests",
            dependencies: ["DiscordKitLoadTests"],
            swiftSettings: concurrencySettings
        ),
    ]
)
