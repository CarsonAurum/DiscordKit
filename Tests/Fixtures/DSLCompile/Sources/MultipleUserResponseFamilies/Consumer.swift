// File: Tests/Fixtures/DSLCompile/Sources/MultipleUserResponseFamilies/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSLMacros

/// Two acknowledgement owners cannot be selected by one user context-menu author.
@UserCommand("Inspect User")
struct AmbiguousUser: UserCommandHandler, DeferredUserCommandHandler {}
