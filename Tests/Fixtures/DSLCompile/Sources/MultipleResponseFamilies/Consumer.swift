// File: Tests/Fixtures/DSLCompile/Sources/MultipleResponseFamilies/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSL
import DiscordDSLMacros

/// One macro declaration cannot claim both immediate and deferred response ownership.
@SlashCommand("invalid", description: "Multiple response families")
struct Invalid: SlashCommandHandler, DeferredSlashCommandHandler {
    typealias Arguments = Input
}

/// The valid argument schema makes the exclusive-family macro diagnostic independently observable.
@CommandArguments
struct Input {}
