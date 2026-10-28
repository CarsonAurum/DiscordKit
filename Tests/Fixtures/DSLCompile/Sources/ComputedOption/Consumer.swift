// File: Tests/Fixtures/DSLCompile/Sources/ComputedOption/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Computed properties cannot become stored invocation-local arguments.
@CommandArguments
struct ComputedArguments {
    /// Deliberately computed rather than stored; the attached macro must diagnose this declaration.
    @Option(description: "Computed") var value: String { "value" }
}
