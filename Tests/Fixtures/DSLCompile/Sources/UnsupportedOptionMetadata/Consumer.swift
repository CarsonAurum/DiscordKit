// File: Tests/Fixtures/DSLCompile/Sources/UnsupportedOptionMetadata/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Autocomplete remains outside the finite manual command macro surface.
@CommandArguments
struct AutocompleteArguments {
    @Option(description: "Query", autocomplete: true) let query: String
}
