// swift-tools-version: 6.4
// File: Examples/SocialApp/Package.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import PackageDescription

let package = Package(name: "SocialApp", platforms: [.macOS(.v13)], dependencies: [
    .package(name: "DiscordKit", path: "../.."),
], targets: [
    .executableTarget(name: "SocialApp", dependencies: [
        .product(name: "DiscordSocial", package: "DiscordKit"),
        .product(name: "DiscordCore", package: "DiscordKit"),
        .product(name: "DiscordMedia", package: "DiscordKit"),
    ], swiftSettings: [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)]),
])
