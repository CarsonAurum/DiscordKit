// File: Tests/Fixtures/DSLCompile/Sources/DynamicDefault/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Defaults may not execute an arbitrary expression during generated schema construction.
@CommandArguments
struct DynamicDefaultArguments {
    @Option(description: "Default") var count: Int = defaultCount()
}
/// Supplies an otherwise valid typed default so rejection comes from the finite-expression policy.
/// - Returns: A constant without tasks or I/O; its call syntax must still be rejected by the macro.
func defaultCount() -> Int { 2 }
