// swift-tools-version: 6.4
// File: Tests/Fixtures/VoiceProbe/Package.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import PackageDescription

let package = Package(
    name: "DiscordVoicePrimitiveProbe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "5.0.1")
    ],
    targets: [
        .testTarget(
            name: "VoiceProbeTests",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "CryptoExtras", package: "swift-crypto")
            ],
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency"),
                .defaultIsolation(nil)
            ]
        )
    ]
)
