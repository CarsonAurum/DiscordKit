// swift-tools-version: 6.4
import CompilerPluginSupport
import PackageDescription

let concurrencySettings: [SwiftSetting] = [
    .enableUpcomingFeature("ApproachableConcurrency"),
    .defaultIsolation(nil),
]

let package = Package(
    name: "DiscordDSLMacros",
    platforms: [.macOS(.v13), .iOS(.v16), .tvOS(.v16), .watchOS(.v9), .visionOS(.v1)],
    products: [.library(name: "DiscordDSLMacros", targets: ["DiscordDSLMacros"])],
    dependencies: [
        .package(name: "DiscordKit", path: "../.."),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "604.0.0"),
    ],
    targets: [
        .macro(name: "DiscordDSLMacrosPlugin", dependencies: [
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
        ], swiftSettings: concurrencySettings),
        .target(name: "DiscordDSLMacros", dependencies: [
            "DiscordDSLMacrosPlugin",
            .product(name: "DiscordCommandDSL", package: "DiscordKit"),
        ], swiftSettings: concurrencySettings),
        .testTarget(name: "DiscordDSLMacrosTests", dependencies: [
            "DiscordDSLMacros", "DiscordDSLMacrosPlugin",
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacroExpansion", package: "swift-syntax"),
            .product(name: "DiscordCore", package: "DiscordKit"),
            .product(name: "DiscordModels", package: "DiscordKit"),
            .product(name: "DiscordDSL", package: "DiscordKit"),
            .product(name: "DiscordCommandDSL", package: "DiscordKit"),
            .product(name: "DiscordCommands", package: "DiscordKit"),
            .product(name: "DiscordInteractions", package: "DiscordKit"),
        ], path: "Tests", swiftSettings: concurrencySettings),
    ]
)
