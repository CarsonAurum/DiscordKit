// File: Tests/Fixtures/DSLCompile/Sources/MultipleBindings/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// One marker cannot silently apply shared metadata to multiple stored arguments.
@CommandArguments
struct MultipleArguments {
    @Option(description: "Multiple") var one: Int, two: Int
}
