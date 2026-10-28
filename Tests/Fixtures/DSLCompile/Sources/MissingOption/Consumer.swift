// File: Tests/Fixtures/DSLCompile/Sources/MissingOption/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSLMacros
import DiscordInteractions

/// Every instance field must explicitly declare its option metadata.
@CommandArguments
struct MissingMarkerArguments {
    let value: String
}
