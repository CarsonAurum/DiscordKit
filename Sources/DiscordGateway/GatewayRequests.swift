// File: Sources/DiscordGateway/GatewayRequests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Completed request observations in chunk-index order for member requests, or
/// requested-guild order for soundboard requests. Raw events also remain in ingestion.
public struct GatewayRequestResult: Sendable, CustomStringConvertible, CustomReflectable {
    public let events: [GatewayEvent]
    /// Conceals member data, nonce and voice/session secrets from diagnostics.
    public var description: String { "GatewayRequestResult(redacted)" }
    /// Prevents reflective diagnostics from traversing received payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Closed request termination reasons. Requests are never automatically replayed.
public enum GatewayRequestFailureReason: Sendable, Equatable {
    case timedOut, disconnected, responseCapacityExceeded, invalidResponse, rateLimited
}

/// A request failure retaining bounded partial observations for explicit recovery.
/// Inspect partial events deliberately; generic error formatting always redacts them.
public struct GatewayRequestFailure: Error, Sendable, CustomStringConvertible, CustomReflectable {
    public let reason: GatewayRequestFailureReason
    public let partialEvents: [GatewayEvent]
    public let retryAfter: Duration?
    /// Exposes only the closed category; payloads and nonce never enter diagnostic text.
    public var description: String { "GatewayRequestFailure(\(reason))" }
    /// Hides partial event data from reflective diagnostics.
    public var customMirror: Mirror { Mirror(self, children: ["reason": reason]) }
}

/// Actor-owned finite request registry. No user callbacks, background tasks or
/// independent synchronization occur here; its sole owner is GatewayShard.
struct GatewayRequestRegistry {
    struct Pending {
        let command: GatewayCommand
        let continuation: AsyncThrowingStream<GatewayRequestResult, any Error>.Continuation
        var events: [Int: GatewayEvent] = [:]
        var expectedCount: Int?
        var bytes = 0
    }
    let maximumRequests: Int
    let maximumEvents: Int
    let maximumBytes: Int
    let maximumRetiredKeys: Int
    private(set) var pending: [UUID: Pending] = [:]
    private var retiredNonces: Set<String> = []
    private var poisonedScopes: Set<String> = []
    private var retainedBytes = 0

    /// Creates fixed aggregate response and metadata bounds, already validated by shard config.
    /// - Parameters:
    ///   - maximumRequests: Maximum concurrently registered requests.
    ///   - maximumEvents: Maximum distinct chunks/guild responses per request.
    ///   - maximumBytes: Maximum wire bytes retained across all pending requests.
    ///   - maximumRetiredKeys: Maximum generation-local nonce/ambiguous-scope tombstones.
    init(maximumRequests: Int, maximumEvents: Int, maximumBytes: Int, maximumRetiredKeys: Int) {
        self.maximumRequests = maximumRequests; self.maximumEvents = maximumEvents
        self.maximumBytes = maximumBytes; self.maximumRetiredKeys = maximumRetiredKeys
    }

    /// Registers before the write so an immediate server response cannot outrun correlation.
    /// - Parameters:
    ///   - id: Owner-generated operation identity, never transmitted.
    ///   - command: Member request requires a nonempty unique nonce; nonce-less families
    ///     require exclusive guild/family ownership. Presence/voice commands are not requests.
    /// - Returns: One-result bounded stream; cancellation unblocks its iterator automatically.
    /// - Throws: Invalid request shape, conflicting scope or bounded metadata exhaustion.
    mutating func register(id: UUID, command: GatewayCommand) throws -> AsyncThrowingStream<GatewayRequestResult, any Error> {
        guard pending[id] == nil else { throw GatewayFailure.requestConflict }
        guard [.members, .soundboardSounds, .channelInfo].contains(command.kind) else { throw GatewayFailure.invalidConfiguration }
        let reservedKeys = pending.values.reduce(0) { $0 + ($1.command.kind == .members ? 1 : $1.command.guildIDs.count) }
        let neededKeys = command.kind == .members ? 1 : command.guildIDs.count
        guard pending.count < maximumRequests,
              neededKeys <= maximumRetiredKeys - retiredNonces.count - poisonedScopes.count - reservedKeys else {
            throw GatewayFailure.commandCapacityExceeded
        }
        if command.kind == .members {
            guard let nonce = command.nonce, !nonce.isEmpty else { throw GatewayFailure.invalidConfiguration }
            guard !retiredNonces.contains(nonce), !pending.values.contains(where: { $0.command.nonce == nonce }) else {
                throw GatewayFailure.requestConflict
            }
        } else {
            for guild in command.guildIDs {
                let scope = scopeKey(command.kind, guild: guild)
                guard !poisonedScopes.contains(scope), !pending.values.contains(where: {
                    $0.command.kind == command.kind && $0.command.guildIDs.contains(guild)
                }) else { throw GatewayFailure.requestConflict }
            }
        }
        let pair = AsyncThrowingStream<GatewayRequestResult, any Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
        pending[id] = Pending(command: command, continuation: pair.continuation)
        return pair.stream
    }

    /// Fences raw request sends against later correlated requests on the same socket.
    /// - Parameter command: A raw request command. Member sends without nonce cannot
    ///   match correlated nonempty nonces and need no metadata; all other scopes are retired.
    /// - Throws: Conflicting active/retired ownership or exhausted correlation metadata.
    mutating func fenceUncorrelated(_ command: GatewayCommand) throws {
        guard [.members, .soundboardSounds, .channelInfo].contains(command.kind) else { return }
        if command.kind == .members, command.nonce == nil || command.nonce == "" { return }
        let id = UUID()
        _ = try register(id: id, command: command)
        remove(id)
    }

    /// Correlates only exact event families, guilds and member nonces, retaining no unrelated events.
    /// Duplicate chunk indices are ignored; inconsistent counts terminate that request explicitly.
    /// - Parameter event: Validated bounded envelope already admitted to raw ingestion.
    mutating func ingest(_ event: GatewayEvent) {
        guard case .object(let data) = event.data,
              case .string(let rawGuild) = data["guild_id"], let guildID = GuildID(rawGuild) else { return }
        for id in Array(pending.keys) {
            guard var request = pending[id], request.command.guildIDs.contains(guildID) else { continue }
            let index: Int
            let count: Int
            switch (request.command.kind, event.name) {
            case (.members, "GUILD_MEMBERS_CHUNK"):
                guard data["nonce"] == request.command.nonce.map(JSONValue.string) else { continue }
                guard case .number(let rawIndex) = data["chunk_index"], let value = Int(rawIndex.rawValue),
                      case .number(let rawCount) = data["chunk_count"], let total = Int(rawCount.rawValue),
                      value >= 0, total > 0, value < total,
                      case .array = data["members"] else {
                    fail(id, reason: .invalidResponse); continue
                }
                index = value; count = total
            case (.soundboardSounds, "SOUNDBOARD_SOUNDS"):
                guard case .array = data["soundboard_sounds"] else { fail(id, reason: .invalidResponse); continue }
                index = request.command.guildIDs.firstIndex(of: guildID)!; count = request.command.guildIDs.count
            case (.channelInfo, "CHANNEL_INFO"):
                guard case .array = data["channels"] else { fail(id, reason: .invalidResponse); continue }
                index = 0; count = 1
            default: continue
            }
            guard count <= maximumEvents else { fail(id, reason: .responseCapacityExceeded); continue }
            guard request.expectedCount == nil || request.expectedCount == count else { fail(id, reason: .invalidResponse); continue }
            if request.events[index] != nil { continue }
            guard event.byteCount <= maximumBytes - retainedBytes else { fail(id, reason: .responseCapacityExceeded); continue }
            request.expectedCount = count; request.events[index] = event; request.bytes += event.byteCount
            retainedBytes += event.byteCount; pending[id] = request
            if request.events.count == count {
                let events = ordered(request)
                request.continuation.yield(GatewayRequestResult(events: events))
                remove(id, ambiguous: false)
            }
        }
    }

    /// Ends matching member or opcode-wide requests on a server rate event.
    /// - Parameters:
    ///   - opcode: Exact server-reported numeric opcode.
    ///   - guild: Optional resource scope; nil matches every request for that opcode.
    ///   - nonce: Optional member nonce; when supplied it must match exactly.
    ///   - retryAfter: Validated server wait delay retained for caller recovery.
    mutating func rateLimited(opcode: Int, guild: GuildID?, nonce: String?, retryAfter: Duration) {
        for id in Array(pending.keys) {
            guard let request = pending[id], request.command.opcode.rawValue == opcode,
                  guild == nil || request.command.guildIDs.contains(guild!),
                  nonce == nil || request.command.nonce == nonce,
                  opcode != 8 || nonce != nil || request.command.requestsAllGuildMembers else { continue }
            fail(id, reason: .rateLimited, retryAfter: retryAfter)
        }
    }

    /// Returns bounded observed progress before timeout, without removing registration.
    /// - Parameter id: Operation identity generated by the shard.
    /// - Returns: Observations in completion order, or empty when already completed/removed.
    func partial(_ id: UUID) -> [GatewayEvent] { pending[id].map(ordered) ?? [] }

    /// Removes one operation after cancellation, timeout, write failure or completion.
    /// - Parameters:
    ///   - id: Registration to dispose, if still active.
    ///   - ambiguous: Whether a nonce-less reply could still arrive. Such scopes cannot
    ///     be correlated again until socket replacement. Member nonces are always retired.
    mutating func remove(_ id: UUID, ambiguous: Bool = true) {
        guard let request = pending.removeValue(forKey: id) else { return }
        retainedBytes -= request.bytes
        if let nonce = request.command.nonce { retiredNonces.insert(nonce) }
        else if ambiguous {
            for guild in request.command.guildIDs { poisonedScopes.insert(scopeKey(request.command.kind, guild: guild)) }
        }
        request.continuation.finish()
    }

    /// Fails all waiters before replacing a socket, clearing generation-local tombstones.
    /// Partial observations accompany disconnection errors; no request is replayed.
    mutating func reset() {
        for id in Array(pending.keys) { fail(id, reason: .disconnected) }
        retiredNonces.removeAll(); poisonedScopes.removeAll(); retainedBytes = 0
    }

    /// Terminates a request with bounded redacted recovery evidence and releases its accounting.
    /// - Parameters:
    ///   - id: Active registration; missing identifiers are harmless.
    ///   - reason: Closed termination category.
    ///   - retryAfter: Optional server rate-limit delay, absent by default.
    private mutating func fail(_ id: UUID, reason: GatewayRequestFailureReason, retryAfter: Duration? = nil) {
        guard let request = pending[id] else { return }
        let error = GatewayRequestFailure(reason: reason, partialEvents: ordered(request), retryAfter: retryAfter)
        // Finish with the error before remove's harmless second finish.
        request.continuation.finish(throwing: error)
        remove(id)
    }

    /// Sorts the finite chunk map into protocol chunk/requested-guild order.
    /// - Parameter request: Active bounded response state.
    /// - Returns: Every unique observation in ascending index order.
    private func ordered(_ request: Pending) -> [GatewayEvent] { request.events.sorted { $0.key < $1.key }.map(\.value) }

    /// Forms a credential-free internal key for nonce-less ambiguity fencing.
    /// - Parameters:
    ///   - kind: Soundboard or channel-info request family.
    ///   - guild: Exact resource ID; never used as a metric label.
    /// - Returns: Stable generation-local scope key.
    private func scopeKey(_ kind: GatewayCommandKind, guild: GuildID) -> String { "\(kind):\(guild.rawValue)" }
}
