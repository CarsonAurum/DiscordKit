// File: Sources/DiscordCache/EventReducer.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels

extension EntityCache {
    /// Projects selected API v10 dispatch payloads without importing the Gateway runtime.
    ///
    /// Guild/channel/thread/message/member/role/user lifecycle dispatches are sparse
    /// observations, not complete typed parity. Guild-create child arrays are omitted;
    /// child-resource completion remains an explicit service operation. Duplicate/order
    /// checks last only while the corresponding bounded projection/tombstone is retained.
    /// There is no global ordering promise for user observations from different shards.
    ///
    /// READY projects its bot user and at most 256 initial unavailable guilds without
    /// retaining session identifiers or resume URLs. It invalidates older observations
    /// from that shard and unassigned REST data, preserving other shards' state.
    /// Guild unavailability in CREATE/DELETE purges children and retains an unavailable
    /// guild tombstone; actual removal retains a deleted tombstone. Content restrictions redact empty or
    /// omitted protected fields when MESSAGE_CONTENT is absent; explicitly supplied
    /// nonempty exception data is usable. Null is accepted only for listed nullable
    /// top-level fields. Unknown dispatches perform no mutation and return `ignoredEvent`.
    /// Explicit role permissions/deletion, member roles/removal, channel overwrites/deletion,
    /// guild loss/unavailability or ownership updates invalidate every cached partition of the observing identity
    /// before retaining the new observation; older visibility is not reused silently.
    /// Sparse message/channel events recover an omitted guild context only from a
    /// unique same-scope retained snowflake; eviction leaves that context unknown.
    /// Obfuscated channels invalidate prior visibility and retain only reliable
    /// routing fields plus the obfuscation flag; omitted private fields stay redacted.
    ///
    /// Sources: https://docs.discord.com/developers/events/gateway-events and
    /// https://docs.discord.com/developers/events/gateway#message-content-intent.
    /// Cached projections never establish current permission or visibility.
    /// - Parameters:
    ///   - name: Documented uppercase dispatch name.
    ///   - data: Already bounded, decoded dispatch data; no network or parsing occurs.
    ///   - scope: Opaque credential/intent/visibility partition that observed this event.
    ///   - shard: Nonnegative source shard index.
    ///   - generation: Caller-owned monotonically increasing session/topology generation.
    ///   - sequence: Nonnegative dispatch sequence, or nil for unordered local fixtures.
    /// - Returns: Observable retention/order outcome for the projected resource.
    /// - Throws: Malformed required identifiers, invalid null/order/scope, closed
    ///   ownership or JSON serialization failure. Bulk removals are validated before
    ///   mutation and bounded to 256 IDs; larger arrays conservatively invalidate scope.
    @discardableResult
    public func observeGateway(name: String, data: JSONValue, scope: CacheScope,
                               shard: Int, generation: UInt64, sequence: Int64?) throws -> CacheWriteResult {
        guard shard >= 0, sequence.map({ $0 >= 0 }) ?? true else { throw EntityCacheFailure.invalidOrder }
        let recognized: Set<String> = [
            "READY", "GUILD_CREATE", "GUILD_UPDATE", "GUILD_DELETE", "CHANNEL_CREATE", "CHANNEL_UPDATE", "CHANNEL_DELETE",
            "THREAD_CREATE", "THREAD_UPDATE", "THREAD_DELETE", "MESSAGE_CREATE", "MESSAGE_UPDATE", "MESSAGE_DELETE",
            "MESSAGE_DELETE_BULK", "GUILD_MEMBER_ADD", "GUILD_MEMBER_UPDATE", "GUILD_MEMBER_REMOVE",
            "GUILD_ROLE_CREATE", "GUILD_ROLE_UPDATE", "GUILD_ROLE_DELETE", "USER_UPDATE", "INTERACTION_CREATE",
        ]
        guard recognized.contains(name) else { return .ignoredEvent }
        guard case .object(var fields) = data else { throw EntityCacheFailure.malformedEvent }
        let order = sequence.map { CacheObservationOrder(shard: shard, generation: generation, sequence: $0) }
        try validateObservation(EntitySnapshot(fields: [:], order: order), scope: scope)
        if name == "READY" { return try observeReady(fields, scope: scope, shard: shard, order: order) }
        if name == "INTERACTION_CREATE" {
            return try observeInteraction(fields, scope: scope, order: order)
        }
        if name == "MESSAGE_DELETE_BULK" {
            guard case .array(let rawIDs) = fields["ids"], rawIDs.allSatisfy({ cacheIdentifier($0) != nil }) else {
                throw EntityCacheFailure.malformedEvent
            }
            guard rawIDs.count <= 256 else { invalidate(scope: scope); return .notRetained }
            var result = CacheWriteResult.ignoredEvent
            for rawID in rawIDs {
                var deletion = fields
                deletion.removeValue(forKey: "ids")
                deletion["id"] = rawID
                result = try observeGateway(name: "MESSAGE_DELETE", data: .object(deletion), scope: scope,
                                            shard: shard, generation: generation, sequence: sequence)
            }
            return result
        }
        let guildID: GuildID?
        if let value = fields["guild_id"] {
            guard let id = cacheIdentifier(value) else { throw EntityCacheFailure.malformedEvent }
            guildID = GuildID(rawValue: id)
        } else { guildID = nil }
        let kind: EntityKind
        if name.hasPrefix("GUILD_ROLE_") {
            kind = .role
            guard let guildID else { throw EntityCacheFailure.malformedEvent }
            if name == "GUILD_ROLE_DELETE" {
                fields = ["id": fields["role_id"] ?? .null, "guild_id": .string(guildID.description)]
            } else {
                guard case .object(var role) = fields["role"] else { throw EntityCacheFailure.malformedEvent }
                role["guild_id"] = .string(guildID.description)
                fields = role
            }
        } else if name.hasPrefix("GUILD_MEMBER_") {
            kind = .member
            guard guildID != nil, case .object(let user) = fields["user"], let userID = user["id"] else {
                throw EntityCacheFailure.malformedEvent
            }
            fields["id"] = userID
        } else if name.hasPrefix("MESSAGE_") { kind = .message }
        else if name.hasPrefix("CHANNEL_") || name.hasPrefix("THREAD_") { kind = .channel }
        else if name == "USER_UPDATE" { kind = .user }
        else { kind = .guild }
        guard let id = cacheIdentifier(fields["id"]) else { throw EntityCacheFailure.malformedEvent }
        if kind == .guild, let availability = fields["unavailable"] {
            guard case .bool = availability else { throw EntityCacheFailure.malformedEvent }
        }
        let key = projectionKey(kind: kind, id: id, guildID: kind == .guild ? nil : guildID, scope: scope)
        let deleted = name.hasSuffix("_DELETE") || name == "GUILD_MEMBER_REMOVE"
        let unavailable = kind == .guild && fields["unavailable"] == .bool(true)
        let availability: CacheAvailability = unavailable ? .unavailable : deleted ? .deleted : .available
        if kind == .guild {
            // Child lists have separate completeness/eviction lifecycles; a guild
            // dispatch does not make every child known or all membership complete.
            for field in ["members", "channels", "threads", "roles", "presences", "voice_states", "emojis", "stickers",
                          "guild_scheduled_events", "stage_instances"] { fields.removeValue(forKey: field) }
        }
        fields["id"] = .string(String(id))
        if let guildID, fields["guild_id"] != nil { fields["guild_id"] = .string(guildID.description) }
        if let channel = cacheIdentifier(fields["channel_id"]) { fields["channel_id"] = .string(String(channel)) }
        var redacted = kind == .message && availability == .available ? contentRedaction(fields, scope: scope) : []
        var snapshot = EntitySnapshot(fields: fields, redactedFields: redacted,
                                      nullableFields: nullableCacheFields(kind), availability: availability,
                                      provenance: .gateway, order: order)
        try validateObservation(snapshot, scope: scope)
        let previous = value(for: key, scope: scope)
        if isStale(order, comparedTo: previous?.order) { return .ignoredStale }
        var obfuscated = false
        if kind == .channel && availability == .available,
           let flags = fields["flags"] ?? previous?.fields["flags"] {
            guard case .number(let number) = flags, let bits = UInt64(number.rawValue) else {
                throw EntityCacheFailure.malformedEvent
            }
            obfuscated = bits & (UInt64(1) << 17) != 0
            if obfuscated {
                let reliable: Set<String> = ["id", "type", "position", "parent_id", "guild_id", "flags"]
                redacted.formUnion(["name", "topic", "permission_overwrites", "last_message_id", "icon",
                                    "owner_id", "application_id", "last_pin_timestamp", "rtc_region",
                                    "default_reaction_emoji", "default_sort_order", "thread_metadata",
                                    "member", "recipients", "available_tags", "applied_tags"])
                redacted.formUnion(fields.keys.filter { !reliable.contains($0) })
                redacted.formUnion((previous?.fields.keys.map { $0 } ?? []).filter { !reliable.contains($0) })
                fields = fields.filter { reliable.contains($0.key) }
                fields["flags"] = flags
                snapshot = EntitySnapshot(fields: fields, redactedFields: redacted,
                                          nullableFields: nullableCacheFields(kind), provenance: .gateway, order: order)
            }
        }
        // Permissions can alter which previously retained fields are visible in
        // every intent partition of this credential. Until explicit revalidation,
        // retain only the new observation under a conservative identity-wide purge.
        if obfuscated || (kind == .role && (fields["permissions"] != nil || deleted))
            || (kind == .member && (fields["roles"] != nil || deleted))
            || (kind == .channel && (fields["permission_overwrites"] != nil || deleted))
            || (kind == .guild && (deleted || unavailable))
            || (name == "GUILD_UPDATE" && fields["owner_id"] != nil) {
            invalidateVisibility(identity: scope.identity)
        }
        if kind == .guild {
            if deleted || unavailable { invalidateGuild(GuildID(rawValue: id), scope: scope) }
        } else if kind == .channel && deleted { invalidateChannelChildren(id, scope: scope) }
        return try apply(snapshot, for: key, scope: scope)
    }

    /// Applies bounded initial session state while retaining no session/resume credentials.
    /// - Parameters:
    ///   - fields: READY data; missing optional projections remain unknown rather than fabricated.
    ///   - scope: Exact observed visibility partition.
    ///   - shard: Source shard whose old observations are no longer fresh.
    ///   - order: READY session generation/sequence, if supplied.
    /// - Returns: Last projection result, ignored stale when every known projection is
    ///   duplicate/older, or not retained if the input has more than 256 initial guilds.
    /// - Throws: Invalid supplied user/guild objects or ordinary cache validation failures.
    /// All supplied identifiers/null rules are checked before destructive invalidation.
    private func observeReady(_ fields: [String: JSONValue], scope: CacheScope, shard: Int,
                              order: CacheObservationOrder?) throws -> CacheWriteResult {
        var projections: [(EntityKey, EntitySnapshot)] = []
        if let raw = fields["user"] {
            guard case .object(let user) = raw, let id = cacheIdentifier(user["id"]) else {
                throw EntityCacheFailure.malformedEvent
            }
            projections.append((EntityKey(kind: .user, id: id),
                                EntitySnapshot(fields: user, nullableFields: nullableCacheFields(.user), order: order)))
        }
        let guilds: [JSONValue]
        if let raw = fields["guilds"] {
            guard case .array(let values) = raw else { throw EntityCacheFailure.malformedEvent }
            guilds = values
        } else { guilds = [] }
        for guild in guilds {
            guard case .object(let value) = guild, cacheIdentifier(value["id"]) != nil else {
                throw EntityCacheFailure.malformedEvent
            }
            if let availability = value["unavailable"] {
                guard case .bool = availability else { throw EntityCacheFailure.malformedEvent }
            }
        }
        for guild in guilds.prefix(256) {
            guard case .object(let value) = guild, let id = cacheIdentifier(value["id"]) else { continue }
            projections.append((EntityKey(kind: .guild, id: id), EntitySnapshot(
                fields: ["id": .string(String(id)), "unavailable": .bool(true)], availability: .unavailable, order: order)))
        }
        for (_, snapshot) in projections { try validateObservation(snapshot, scope: scope) }
        if !projections.isEmpty,
           projections.allSatisfy({ isStale(order, comparedTo: value(for: $0.0, scope: scope)?.order) }) { return .ignoredStale }
        invalidateShardObservations(shard, scope: scope, before: order)
        var result = CacheWriteResult.ignoredEvent
        for (key, snapshot) in projections {
            if key.kind == .guild {
                if isStale(order, comparedTo: value(for: key, scope: scope)?.order) { continue }
                invalidateGuild(GuildID(rawValue: key.id), scope: scope)
            }
            result = try apply(snapshot, for: key, scope: scope)
        }
        return guilds.count > 256 ? .notRetained : result
    }

    /// Uses interaction-supplied user/message data without an unnecessary REST read.
    /// - Parameters:
    ///   - fields: Bounded interaction object; only its explicit top-level user/message is projected.
    ///   - scope: Exact observed visibility partition.
    ///   - order: Optional source dispatch ordering.
    /// - Returns: Last projected result, or ignored when neither optional resource exists.
    /// - Throws: Malformed supplied guild/resource identifiers or ordinary cache validation
    ///   errors. A present invalid guild ID never creates an unscoped projection.
    private func observeInteraction(_ fields: [String: JSONValue], scope: CacheScope,
                                    order: CacheObservationOrder?) throws -> CacheWriteResult {
        let guildID: GuildID?
        if let raw = fields["guild_id"] {
            guard let id = cacheIdentifier(raw) else { throw EntityCacheFailure.malformedEvent }
            guildID = GuildID(rawValue: id)
        } else { guildID = nil }
        var projections: [(EntityKey, EntitySnapshot)] = []
        for (field, kind) in [("user", EntityKind.user), ("message", EntityKind.message)] {
            guard let raw = fields[field] else { continue }
            guard case .object(let value) = raw, let id = cacheIdentifier(value["id"]) else {
                throw EntityCacheFailure.malformedEvent
            }
            projections.append((EntityKey(kind: kind, id: id, guildID: kind == .message ? guildID : nil),
                                EntitySnapshot(fields: value, nullableFields: nullableCacheFields(kind),
                                               provenance: .interaction, order: order)))
        }
        for (_, snapshot) in projections { try validateObservation(snapshot, scope: scope) }
        var result = CacheWriteResult.ignoredEvent
        for (key, snapshot) in projections { result = try apply(snapshot, for: key, scope: scope) }
        return result
    }
}

/// Reads a string snowflake without accepting rounded JSON numbers or malformed digits.
/// - Parameter value: Optional payload member; only nonempty unsigned decimal strings qualify.
/// - Returns: Exact 64-bit identifier, or nil on absence, null, wrong kind or overflow.
private func cacheIdentifier(_ value: JSONValue?) -> UInt64? {
    guard case .string(let text) = value, !text.isEmpty,
          text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
    return UInt64(text)
}

/// Lists reviewed top-level nullable fields for the projected family; nested JSON stays opaque.
/// - Parameter kind: Resource family whose dispatch schema supplies the values.
/// - Returns: Explicit null allowlist; unknown nullable fields require a reviewed adapter update.
private func nullableCacheFields(_ kind: EntityKind) -> Set<String> {
    switch kind {
    case .guild:
        return ["icon", "icon_hash", "splash", "discovery_splash", "region", "afk_channel_id", "widget_channel_id",
                "application_id", "system_channel_id", "rules_channel_id", "vanity_url_code", "description",
                "banner", "public_updates_channel_id", "max_presences", "safety_alerts_channel_id", "incidents_data",
                "home_header", "premium_progress_bar_enabled_user_updated_at"]
    case .channel:
        return ["name", "topic", "last_message_id", "icon", "application_id", "parent_id",
                "last_pin_timestamp", "rtc_region", "default_reaction_emoji", "default_sort_order"]
    case .user:
        return ["global_name", "avatar", "banner", "accent_color", "email", "avatar_decoration_data",
                "collectibles", "primary_guild"]
    case .member:
        return ["nick", "avatar", "banner", "joined_at", "premium_since", "communication_disabled_until",
                "avatar_decoration_data", "collectibles"]
    case .role: return ["icon", "unicode_emoji"]
    case .message: return ["edited_timestamp", "referenced_message"]
    }
}

/// Conservatively identifies protected message fields suppressed by missing content intent.
/// - Parameters:
///   - fields: Explicit dispatch fields; nonempty exception values remain usable.
///   - scope: Observing intent partition.
/// - Returns: Redacted protected keys; absent intent never imports older private contents.
private func contentRedaction(_ fields: [String: JSONValue], scope: CacheScope) -> Set<String> {
    guard scope.intents & (UInt64(1) << 15) == 0 else { return [] }
    let protected: Set<String> = ["content", "embeds", "attachments", "components", "poll"]
    return protected.filter { key in
        guard let value = fields[key] else { return true }
        switch value {
        case .string(let value): return value.isEmpty
        case .array(let value): return value.isEmpty
        case .null: return true
        default: return false
        }
    }
}
