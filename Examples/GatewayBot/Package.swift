// swift-tools-version: 6.4
// File: Examples/GatewayBot/Package.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import PackageDescription

let package = Package(
    name: "GatewayBot",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "DiscordKit", path: "../..")],
    targets: [.executableTarget(name: "GatewayBot", dependencies: [
        .product(name: "DiscordClient", package: "DiscordKit"),
        .product(name: "DiscordCache", package: "DiscordKit"),
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordGateway", package: "DiscordKit"),
        .product(name: "DiscordHTTP", package: "DiscordKit"),
        .product(name: "DiscordTransport", package: "DiscordKit"),
        .product(name: "DiscordFoundationTransport", package: "DiscordKit"),
    ], swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)])]
)
