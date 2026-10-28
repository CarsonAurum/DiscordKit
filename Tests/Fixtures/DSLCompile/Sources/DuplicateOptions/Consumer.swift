// File: Tests/Fixtures/DSLCompile/Sources/DuplicateOptions/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Duplicate external names must be diagnosed even when Swift property names differ.
@CommandArguments
struct DuplicateArguments {
    @Option(name: "same", description: "First") let first: String
    @Option(name: "same", description: "Second") let second: String
}
