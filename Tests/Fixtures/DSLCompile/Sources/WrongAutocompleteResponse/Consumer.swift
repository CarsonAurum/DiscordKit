// File: Tests/Fixtures/DSLCompile/Sources/WrongAutocompleteResponse/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL

/// Autocomplete cannot respond with a channel message through its suggestions-only protocol.
struct InvalidAutocompleteResponse: AutocompleteCommandHandler {
    typealias Value = String

    /// Keeps the correct focused input type while deliberately returning the wrong response contract.
    /// - Parameters:
    ///   - context: Correct immutable invocation snapshot, unused by this compile-only fixture.
    ///   - input: Correct admitted partial autocomplete input.
    ///   - value: Correct focused string; no complete argument decoding is attempted.
    /// - Returns: A message incompatible with the required AutocompleteResponse<String>.
    /// - Throws: Existing local message validation errors; compilation invokes no user work.
    func execute(_ context: CommandContext, input: AutocompleteInput, value: String) async throws -> MessageResponse {
        try MessageResponse { Text("invalid") }
    }
}
