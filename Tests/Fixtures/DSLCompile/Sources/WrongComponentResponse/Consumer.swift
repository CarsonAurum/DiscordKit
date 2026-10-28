// File: Tests/Fixtures/DSLCompile/Sources/WrongComponentResponse/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL
import DiscordModels

/// A component's immediate handler cannot return an edit intended to complete a deferred command.
struct InvalidComponentResponse: ComponentHandler {
    typealias Response = DeferredMessageResponse
    /// Correct finite component ID keeps the failure focused on the response contract.
    var customID: String { "invalid:button" }
    /// Correct known component kind removes unrelated admission errors from this fixture.
    var componentType: ComponentType { .button }

    /// Supplies a correct typed component signature with a deliberately incompatible response type.
    /// - Parameters:
    ///   - context: Correct immutable component invocation snapshot.
    ///   - input: Correct typed component payload; compiler fixtures execute no handler.
    /// - Returns: A deferred edit that does not conform to ComponentInitialResponse.
    /// - Throws: Existing local edit validation errors.
    func execute(_ context: CommandContext, input: ComponentInput) async throws -> DeferredMessageResponse {
        try DeferredMessageResponse { Text("invalid") }
    }
}
