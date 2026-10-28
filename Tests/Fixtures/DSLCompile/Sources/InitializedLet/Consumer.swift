// File: Tests/Fixtures/DSLCompile/Sources/InitializedLet/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Swift cannot overwrite initialized let storage while decoding an invocation.
@CommandArguments
struct ConstantDefaultArguments {
    @Option(description: "Default") let count: Int = 2
}
