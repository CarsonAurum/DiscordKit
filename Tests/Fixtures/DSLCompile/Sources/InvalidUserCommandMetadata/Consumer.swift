// File: Tests/Fixtures/DSLCompile/Sources/InvalidUserCommandMetadata/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordDSLMacros

/// Empty context-menu names are rejected by the authoring macro before runtime construction.
@UserCommand("")
struct InvalidUser {}
