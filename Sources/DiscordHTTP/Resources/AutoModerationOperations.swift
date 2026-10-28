// File: Sources/DiscordHTTP/Resources/AutoModerationOperations.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels

/// Explicit request reduction over caller-owned rule snapshots. No read, mutation or hidden task starts here.
public enum AutoModerationOperations {
    /// Omits a PATCH when all explicitly supplied fields already equal the caller's rule snapshot.
    /// - Parameters:
    ///   - current: Rule snapshot including exact raw fields; no freshness or current authorization is inferred.
    ///   - request: Validated edits whose trigger context must match the snapshot's known trigger kind;
    ///     omitted fields do not participate and explicit null remains distinct.
    ///   - auditReason: Optional supported reason, validated only when a mutation is needed.
    /// - Returns: Nil for a no-op, otherwise one ordinary unsafe PATCH descriptor targeting the snapshot IDs.
    /// - Throws: Invalid-value for mismatched or unknown snapshot trigger context, a malformed request
    ///   root or ordinary descriptor/audit errors. Context is checked even for an empty or matching edit,
    ///   preventing request-only action/metadata validation from using a different rule's trigger kind.
    ///   Stale snapshots carry normal reconciliation races; no automatic fetch, retry or trigger change occurs.
    public static func modifyIfChanged(current: AutoModerationRule, request: AutoModerationModifyRequest,
                                       auditReason: String? = nil) throws -> Endpoint<AutoModerationRule>? {
        guard current.triggerType.knownValue == request.triggerType else { throw DiscordError.validation(.invalidValue) }
        guard case .object(let fields) = request.jsonValue() else { throw DiscordError.validation(.invalidValue) }
        guard fields.contains(where: { current.rawFields[$0.key] != $0.value }) else { return nil }
        return try AutoModerationEndpoints.modify(guildID: current.guildID, ruleID: current.id,
            request: request, auditReason: auditReason)
    }
}
