// swift-tools-version: 6.4
// File: Examples/RESTOnly/Package.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import PackageDescription

let package = Package(
    name: "RESTOnly",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "DiscordKit", path: "../..")],
    targets: [.executableTarget(name: "RESTOnly", dependencies: [
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordHTTP", package: "DiscordKit"),
        .product(name: "DiscordFoundationTransport", package: "DiscordKit", condition: .when(platforms: [.macOS])),
        .product(name: "DiscordNIOTransport", package: "DiscordKit", condition: .when(platforms: [.linux])),
    ], swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)])]
)
