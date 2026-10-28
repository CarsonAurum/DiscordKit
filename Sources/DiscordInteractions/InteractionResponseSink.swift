// File: Sources/DiscordInteractions/InteractionResponseSink.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordHTTP
import DiscordModels
import Foundation

/// Injected response mechanics for one exact interaction. Initial HTTP delivery may publish an inline 200
/// response; Gateway delivery must call the HTTP callback endpoint. Continuations always use HTTP REST.
/// Closures receive remaining monotonic timeout, must cooperate with cancellation, and must not retry an
/// ambiguous initial submission. Construction starts no work and owns no shared transport/client lifetime.
public struct InteractionResponseSink: Sendable {
    let initial: @Sendable (InteractionResponse, Duration) async throws -> Void
    let edit: @Sendable (InteractionMessageEdit, Duration) async throws -> Message
    let followup: @Sendable (InteractionMessageCreate, Duration) async throws -> Message
    let delete: @Sendable (Duration) async throws -> Void

    /// Binds transport mechanics without starting tasks, opening connections or acknowledging input.
    /// - Parameters:
    ///   - initial: Dedicated initial callback path; successful return confirms adapter acceptance.
    ///     Throw `InteractionDeliveryError.notSubmitted` only with positive evidence that no bytes were submitted.
    ///   - editOriginal: Original-response PATCH; nil reports missing configuration before network I/O.
    ///   - followup: Follow-up POST; nil reports missing configuration before network I/O.
    ///   - deleteOriginal: Original-response DELETE; nil reports missing configuration before network I/O.
    ///     Timeout arguments are positive remaining durations, with a maximum fifteen-minute token lifetime.
    public init(initial: @escaping @Sendable (InteractionResponse, Duration) async throws -> Void,
        editOriginal: (@Sendable (InteractionMessageEdit, Duration) async throws -> Message)? = nil,
        followup: (@Sendable (InteractionMessageCreate, Duration) async throws -> Message)? = nil,
        deleteOriginal: (@Sendable (Duration) async throws -> Void)? = nil) {
        self.initial = initial
        self.edit = editOriginal ?? { _, _ in throw DiscordError.capabilityUnavailable(.missingConfiguration) }
        self.followup = followup ?? { _, _ in throw DiscordError.capabilityUnavailable(.missingConfiguration) }
        self.delete = deleteOriginal ?? { _ in throw DiscordError.capabilityUnavailable(.missingConfiguration) }
    }

    /// Creates HTTP callback/continuation mechanics with independent initial REST admission ownership.
    /// - Parameters:
    ///   - interaction: Exact interaction whose token must match both clients' interaction credential.
    ///   - initialClient: Dedicated callback client/coordinator; do not share its queue with ordinary REST work.
    ///     Its rate authority must still coordinate the same token/resource/server scopes across workers.
    ///   - continuationClient: Client for original edits/follow-ups with independently bounded ordinary admission.
    ///   - clock: Same monotonic domain as both REST clients; per-call remaining time becomes its local deadline.
    /// - Returns: JSON-only sink using API v10 typed endpoints without Gateway imports. Ambiguous initial submissions
    ///   are never retried; complete 429 rejections retain the initial client's finite explicit rejection-retry policy.
    /// - Note: Inline HTTP responses use `init(initial:editOriginal:followup:deleteOriginal:)` instead. Bounded uploads
    ///   remain available through the underlying typed endpoints and are not silently copied into these helpers.
    public static func rest<C: Clock>(interaction: Interaction, initialClient: RESTClient<C>,
        continuationClient: RESTClient<C>, clock: C) -> Self where C.Duration == Duration {
        Self(initial: { response, timeout in
            let endpoint = try InteractionEndpoints.createResponse(interactionID: interaction.id,
                token: interaction.token, response: response, interactionType: interaction.type.knownValue)
            _ = try await initialClient.execute(endpoint, deadline: clock.now.advanced(by: timeout))
        }, editOriginal: { request, timeout in
            try await continuationClient.execute(InteractionEndpoints.editOriginalResponse(
                applicationID: interaction.applicationID, token: interaction.token, request: request),
                deadline: clock.now.advanced(by: timeout))
        }, followup: { request, timeout in
            try await continuationClient.execute(InteractionEndpoints.createFollowup(
                applicationID: interaction.applicationID, token: interaction.token, request: request),
                deadline: clock.now.advanced(by: timeout))
        }, deleteOriginal: { timeout in
            _ = try await continuationClient.execute(InteractionEndpoints.deleteOriginalResponse(
                applicationID: interaction.applicationID, token: interaction.token),
                deadline: clock.now.advanced(by: timeout))
        })
    }
}
