// swift-tools-version: 6.4
// File: Examples/DSLEvents/Package.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import PackageDescription

let concurrency: [SwiftSetting] = [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)]

let package = Package(name: "DSLEvents", platforms: [.macOS(.v13)], dependencies: [
    .package(name: "DiscordKit", path: "../.."),
], targets: [
    .executableTarget(name: "DSLEvents", dependencies: [
        .product(name: "DiscordBotDSL", package: "DiscordKit"),
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordDSL", package: "DiscordKit"),
        .product(name: "DiscordGateway", package: "DiscordKit"),
        .product(name: "DiscordModels", package: "DiscordKit"),
        .product(name: "DiscordTransport", package: "DiscordKit"),
    ], swiftSettings: concurrency),
    .testTarget(name: "DSLEventsTests", dependencies: ["DSLEvents"], swiftSettings: concurrency),
])
