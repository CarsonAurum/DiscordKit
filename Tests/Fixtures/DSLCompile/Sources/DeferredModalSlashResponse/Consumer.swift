// File: Tests/Fixtures/DSLCompile/Sources/DeferredModalSlashResponse/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSLMacros

/// A typed modal slash handler must return its modal before acknowledgement, without a deferred edit.
@SlashCommand("modal", description: "Illegal deferred modal")
struct InvalidDeferredModal: ModalSlashCommandHandler {
    typealias Arguments = EmptyArguments

    /// Deliberately returns a valid edit through an incompatible immediate-modal handler contract.
    /// - Parameters:
    ///   - context: Correct immutable immediate context; there is no raw responder access.
    ///   - arguments: Correct empty typed schema, proving the failure is the response type.
    /// - Returns: A deferred edit incompatible with the required ModalResponse return type.
    /// - Throws: Existing local edit validation errors; no code runs in the compiler fixture.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> DeferredMessageResponse {
        try DeferredMessageResponse { Text("invalid") }
    }
}

/// An admitted empty schema isolates the command's intentionally incompatible response signature.
@CommandArguments
struct EmptyArguments {}
