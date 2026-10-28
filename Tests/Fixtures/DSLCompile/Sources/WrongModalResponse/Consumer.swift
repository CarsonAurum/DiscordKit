// File: Tests/Fixtures/DSLCompile/Sources/WrongModalResponse/Consumer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommandDSL

/// A modal submission cannot open another modal through the typed response contract.
struct InvalidModalResponse: ModalHandler {
    typealias Values = EmptyModalValues
    typealias Response = ModalResponse
    /// Correct exact modal ID, proving this fixture fails on its response-family constraint.
    var customID: String { "invalid:modal" }

    /// Supplies every execute witness except the deliberately incompatible response marker.
    /// - Parameters:
    ///   - context: Correct immutable context for an admitted modal submission.
    ///   - values: Correct typed empty schema, excluding aggregate mismatch as the failure cause.
    /// - Returns: A modal response intentionally unavailable to modal-submit handlers.
    /// - Throws: The fixture's local sentinel; no handler runs during compilation.
    func execute(_ context: CommandContext, values: Values) async throws -> ModalResponse {
        throw FixtureFailure.unreachable
    }
}

/// A valid empty modal schema isolates the deliberately illegal response family.
struct EmptyModalValues: ModalValues {
    /// Supplies a valid empty schema without constructing values or invoking handlers.
    /// - Throws: Existing local schema validation errors.
    static var schema: ModalSchema<Self> {
        /// Returns an admitted empty schema without invoking its retained aggregate constructor.
        /// - Throws: Existing local finite-schema validation errors.
        get throws { try ModalSchema(fields: []) { _ in Self() } }
    }
}

/// A local sentinel avoids introducing unrelated modal-definition validation into a compile fixture.
private enum FixtureFailure: Error { case unreachable }
