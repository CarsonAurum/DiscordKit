// swift-tools-version: 6.4
// File: Examples/LoggingApp/Package.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import PackageDescription

let settings: [SwiftSetting] = [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)]

let package = Package(
    name: "LoggingApp",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../..")],
    targets: [
        .executableTarget(name: "LoggingApp", dependencies: [
            .product(name: "DiscordLogging", package: "DiscordKit"),
            .product(name: "DiscordLogHandlers", package: "DiscordKit"),
            .product(name: "DiscordTransport", package: "DiscordKit"),
        ], swiftSettings: settings),
        .testTarget(name: "LoggingAppTests", dependencies: ["LoggingApp"], swiftSettings: settings),
    ]
)
