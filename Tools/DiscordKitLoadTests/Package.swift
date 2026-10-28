// swift-tools-version: 6.4
// File: Tools/DiscordKitLoadTests/Package.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

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
                .product(name: "DiscordLogging", package: "DiscordKit"),
                .product(name: "DiscordTransport", package: "DiscordKit"),
                .product(name: "DiscordNIOTransport", package: "DiscordKit"),
                .product(name: "DiscordHTTP", package: "DiscordKit"),
                .product(name: "DiscordGateway", package: "DiscordKit"),
                .product(name: "DiscordCache", package: "DiscordKit"),
                .product(name: "DiscordModels", package: "DiscordKit"),
                .product(name: "DiscordCore", package: "DiscordKit"),
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
