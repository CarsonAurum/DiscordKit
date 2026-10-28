// swift-tools-version: 6.4
// File: Tests/Fixtures/DSLExtensionsCompile/Package.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import PackageDescription

let concurrency: [SwiftSetting] = [.enableUpcomingFeature("ApproachableConcurrency"), .defaultIsolation(nil)]
let dependencies: [Target.Dependency] = [
    .product(name: "DiscordCommandExtensions", package: "DiscordDSLExtensions"),
    .product(name: "DiscordBotExtensions", package: "DiscordDSLExtensions"),
    .product(name: "DiscordCommandDSL", package: "DiscordKit"),
    .product(name: "DiscordDSL", package: "DiscordKit"),
]

let package = Package(name: "DSLExtensionsCompile", platforms: [.macOS(.v13)], dependencies: [
    .package(name: "DiscordKit", path: "../../.."),
    .package(name: "DiscordDSLExtensions", path: "../../../Packages/DiscordDSLExtensions"),
], targets: ["PositiveDependencies", "MissingDependencies", "WrongDependencies"].map { name in
    .target(name: name, dependencies: dependencies, swiftSettings: concurrency)
})
