// File: Tests/Fixtures/DSLCompile/Sources/InferredType/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Type inference is deliberately unavailable to syntax-only schema generation.
@CommandArguments
struct InferredArguments {
    @Option(description: "Inferred") var count = 2
}
