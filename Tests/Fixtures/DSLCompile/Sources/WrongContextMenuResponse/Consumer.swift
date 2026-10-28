// File: Tests/Fixtures/DSLCompile/Sources/WrongContextMenuResponse/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordDSLMacros
import DiscordModels

/// Updating a source message is not a legal context-menu command response.
@UserCommand("Inspect User")
struct InvalidUserResponse: UserCommandHandler {
    typealias Response = UpdateMessageResponse

    /// Supplies every execute witness shape except the deliberately illegal response-family constraint.
    /// - Parameters:
    ///   - context: Immutable normalized command snapshot, unused by this compile-only fixture.
    ///   - target: Correct typed user target, proving the failure is not target incompatibility.
    /// - Returns: A validated source update, intentionally not a legal CommandInitialResponse.
    /// - Throws: Existing local update validation errors; the compiler fixture never executes this method.
    func execute(_ context: CommandContext, target: UserReference) async throws -> UpdateMessageResponse {
        try UpdateMessageResponse(InteractionMessageEdit())
    }
}
