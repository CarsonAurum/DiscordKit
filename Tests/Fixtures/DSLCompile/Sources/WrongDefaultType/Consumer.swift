// File: Tests/Fixtures/DSLCompile/Sources/WrongDefaultType/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Swift type checking remains authoritative for literal defaults accepted by syntax policy.
@CommandArguments
struct WrongDefaultArguments {
    @Option(description: "Default") var count: Int = "three"
}
