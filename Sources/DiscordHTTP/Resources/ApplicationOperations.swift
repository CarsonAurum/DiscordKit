// File: Sources/DiscordHTTP/Resources/ApplicationOperations.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels

/// Explicit request reduction using caller-owned Application snapshots; no reads, freshness policy or lifecycle is hidden.
public enum ApplicationOperations {
    /// Skips empty edits or edits whose every selected field exactly matches a supplied current Application snapshot.
    /// - Parameters:
    ///   - current: Caller-selected snapshot of the authenticated application; the caller owns its age and identity checks.
    ///     A stale snapshot may cause an intended write to be skipped, so omit this helper when fresh mutation semantics matter.
    ///   - request: Validated partial settings; absent fields do not participate and null matches only an explicit server null.
    ///     Nonnull icon/cover uploads always produce a write because response hashes cannot establish uploaded-image equality.
    ///     Preview localized descriptions and team_id only match when their exact wire fields are present in rawFields.
    /// - Returns: Nil for an empty or exact selected-field match; otherwise one ordinary unsafe PATCH descriptor retaining
    ///   the catalog's authentication, coordinated rate policy and scoped cache invalidation. Unknown server values are retained.
    /// - Throws: Body/descriptor validation errors for a required change. Comparison is synchronous and finite in selected
    ///   payload size, acquires no resources, starts no request and never merges, batches or reorders separate mutations.
    public static func modifyIfChanged(current: Application, request: ApplicationModify) throws -> Endpoint<Application>? {
        guard case .object(let selected) = request.jsonValue() else { throw DiscordError.validation(.invalidValue) }
        if selected.allSatisfy({ field in
            if ["icon", "cover_image"].contains(field.key), field.value != .null { return false }
            return current.rawFields[field.key] == field.value
        }) { return nil }
        return try ApplicationEndpoints.modifyCurrent(request: request)
    }
}
