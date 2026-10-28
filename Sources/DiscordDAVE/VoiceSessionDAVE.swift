// File: Sources/DiscordDAVE/VoiceSessionDAVE.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordMLS
import DiscordVoice
import Foundation

/// Bounded, payload-free diagnostics for the supervised DAVE adapter.
public struct DAVEVoiceSessionSnapshot: Sendable, Equatable {
    public let sourceCount: Int
    public let pendingOperationCount: Int
    public let operationIsActive: Bool
    public let isClosed: Bool
}

/// Adapts owned DAVE v1 signaling and complete Opus frames to a supervised Voice session.
///
/// The caller supplies the trusted external sender and a signing identity shared with
/// related sessions. SSRC bindings come only from the authenticated Voice socket;
/// packets cannot create bindings. Media and control operations share one bounded
/// admission queue because `DAVEProtocolSession` rejects overlapping operations.
/// Controls precede queued media, and one queue position is reserved for controls.
/// Construction starts no tasks, sockets, devices, clocks, or persistence.
public actor DAVEVoiceSession: VoiceSessionE2EE,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let session: DAVEProtocolSession
    private let localUserID: UInt64
    private let maximumParticipants: Int
    private let now: @Sendable () -> TimeInterval
    private var sources: [UInt32: UInt64] = [:]
    private var userSources: [UInt64: UInt32] = [:]
    private var admission: DAVEOperationAdmissionPolicy
    private var pendingWaiters: [UInt64: CheckedContinuation<Void, any Error>] = [:]
    private var closing = false
    private var idleWaiter: CheckedContinuation<Void, Never>?
    private var cleanup: Task<Void, Never>?

    /// Creates an inert DAVE owner and its bounded supervised-session adapter.
    /// - Parameters:
    ///   - identity: Exact authenticated account/guild/channel/session/generation scope.
    ///   - groupID: Authenticated call/stream identifier, 1...255 bytes, ordinarily an
    ///     eight-byte big-endian snowflake. Untrusted packets never select this value.
    ///   - signaturePrivateKey: P-256 private scalar shared across related sessions;
    ///     retained by the owned protocol actor until closure.
    ///   - externalSender: Exact trusted MLS external basic credential and signing key.
    ///   - maximumParticipants: Maximum member and SSRC-binding count, 1...1024;
    ///     each participant has at most one audio source in this Opus-only adapter.
    ///   - maximumPendingOperations: Bounded suspended operations, 2...1024, default
    ///     64. Media can occupy all but one position; controls use the full budget.
    ///   - cipherConfiguration: DAVE frame/ratchet/replay/verification bounds.
    ///   - verificationStore: Optional account-scoped ephemeral verification owner.
    ///   - verificationSessionID: Nonzero caller-unique verification-store identifier.
    ///   - now: Finite, nonnegative monotonic seconds in the same time domain as
    ///     `receive(_:now:)`. Consulted only for received media, never during construction.
    /// - Throws: `invalidConfiguration` for invalid adapter/protocol bounds, or
    ///   cryptographic key/configuration errors. No network authority is inferred.
    public init(identity: VoiceConnectionIdentity, groupID: Data, signaturePrivateKey: Data,
                externalSender: MLSExternalSender, maximumParticipants: Int = 256,
                maximumPendingOperations: Int = 64,
                cipherConfiguration: DAVEFrameCipher.Configuration = .standard,
                verificationStore: DAVEVerificationStore? = nil, verificationSessionID: UInt64 = 1,
                now: @escaping @Sendable () -> TimeInterval) throws {
        guard (1...1024).contains(maximumParticipants), (2...1024).contains(maximumPendingOperations) else {
            throw DAVESessionError.invalidConfiguration
        }
        session = try DAVEProtocolSession(identity: identity, groupID: groupID,
            signaturePrivateKey: signaturePrivateKey, externalSender: externalSender,
            maximumMembers: maximumParticipants, cipherConfiguration: cipherConfiguration,
            verificationStore: verificationStore, verificationSessionID: verificationSessionID)
        localUserID = identity.userID.rawValue
        self.maximumParticipants = maximumParticipants
        admission = try DAVEOperationAdmissionPolicy(maximumPendingOperations: maximumPendingOperations)
        self.now = now
    }

    /// Starts negotiated DAVE once, ahead of queued media operations.
    /// - Parameter protocolVersion: Authenticated Session Description DAVE version;
    ///   only version one is supported and downgrade fails closed.
    /// - Returns: Ordered KeyPackage commands to send once on the exact Voice socket.
    /// - Throws: Cancellation, closure, admission-capacity, version, or DAVE failures.
    public func start(protocolVersion: UInt16) async throws -> [VoiceGatewayFrame] {
        try await acquire(control: true)
        defer { release() }
        try validateAdmission()
        return try await session.start(protocolVersion: protocolVersion)
    }

    /// Serializes an authenticated DAVE/member control ahead of waiting media.
    /// - Parameters:
    ///   - frame: One server DAVE or client-connect/disconnect frame from this socket;
    ///     the supervised owner handles Speaking and supplies `bindSSRC` separately.
    ///   - now: Finite nondecreasing monotonic seconds shared with the injected clock.
    /// - Returns: Bounded ordered commands; the adapter performs no socket writes.
    /// - Throws: Cancellation, closure, capacity, signaling, clock, or MLS failures.
    public func receive(_ frame: VoiceGatewayFrame, now: TimeInterval) async throws -> [VoiceGatewayFrame] {
        try await acquire(control: true)
        defer { release() }
        try validateAdmission()
        return try await session.receive(frame, now: now)
    }

    /// Reauthorizes the exact reducer only against the current owned DAVE epoch.
    /// - Parameter state: Reducer suspended awaiting DAVE for this exact identity.
    /// - Returns: A ready reducer after live membership/version/epoch validation.
    /// - Throws: Cancellation, closure, queue capacity, unavailable epoch, or identity mismatch.
    public func authorizeGateway(_ state: VoiceGatewaySessionState) async throws -> VoiceGatewaySessionState {
        try await acquire(control: true)
        defer { release() }
        try validateAdmission()
        return try await session.authorizeGateway(state)
    }

    /// Binds an authenticated audio source to one account without trusting RTP bytes.
    ///
    /// Repeating a binding is idempotent. A participant may replace its own source;
    /// reassigning an occupied source to a different participant is rejected until
    /// the previous authenticated participant is removed. SSRC zero is a valid RTP value.
    /// - Parameters:
    ///   - ssrc: Complete unsigned audio SSRC from Ready or authenticated Speaking.
    ///   - userID: Nonzero account associated by the authenticated Voice connection.
    /// - Throws: Cancellation, closure, queue/source capacity, or `invalidMessage`
    ///   for a zero account or conflicting binding. A rejected update changes nothing.
    public func bindSSRC(_ ssrc: UInt32, userID: UserID) async throws {
        try await acquire(control: true)
        defer { release() }
        try validateAdmission()
        guard userID.rawValue > 0, sources[ssrc] == nil || sources[ssrc] == userID.rawValue else {
            throw DAVESessionError.invalidMessage
        }
        guard userSources[userID.rawValue] != nil || sources.count < maximumParticipants else {
            throw DAVESessionError.capacityExceeded
        }
        if let previous = userSources[userID.rawValue], previous != ssrc { sources.removeValue(forKey: previous) }
        sources[ssrc] = userID.rawValue
        userSources[userID.rawValue] = ssrc
    }

    /// Immediately forgets an authenticated departed participant's audio binding.
    /// - Parameter userID: Departed account; unknown/repeated removal is harmless.
    /// This does not synthesize MLS membership changes: the authenticated disconnect
    /// control must also be delivered through `receive(_:now:)`. A frame admitted
    /// before this removal may finish; subsequent lookups fail closed.
    public func removeParticipant(_ userID: UserID) async {
        if let source = userSources.removeValue(forKey: userID.rawValue) { sources.removeValue(forKey: source) }
    }

    /// Protects one complete encoded Opus packet before RTP packetization.
    /// - Parameters:
    ///   - opus: Complete encoded Opus bytes within the configured cipher bound.
    ///   - ssrc: Authenticated local audio source; another account's source is rejected.
    /// - Returns: DAVE ciphertext; no plaintext or transport-only fallback exists.
    /// - Throws: Cancellation, closure, capacity, unknown/local-identity mismatch,
    ///   unavailable epoch, or codec/cipher failures. Nonces remain actor-owned.
    public func seal(_ opus: Data, ssrc: UInt32) async throws -> Data {
        try await acquire(control: false)
        defer { release() }
        try validateAdmission()
        guard sources[ssrc] == localUserID else { throw DAVESessionError.mediaUnavailable }
        return try await session.seal(opus, codec: .opus)
    }

    /// Authenticates a depacketized DAVE frame under its authenticated source owner.
    /// - Parameters:
    ///   - frame: Complete DAVE audio frame after RTP transport authentication.
    ///   - ssrc: Transport-authenticated RTP source with a prior Voice-control binding.
    /// - Returns: Authenticated encoded Opus bytes. Exceptional plaintext silence is
    ///   disabled; ordinary encoded Opus silence must be DAVE protected.
    /// - Throws: Cancellation, closure, capacity, unknown source, clock, membership,
    ///   replay, verification-attempt, epoch, or frame-authentication failures.
    public func open(_ frame: Data, ssrc: UInt32) async throws -> Data {
        try await acquire(control: false)
        defer { release() }
        try validateAdmission()
        guard let senderID = sources[ssrc] else { throw DAVESessionError.mediaUnavailable }
        return try await session.open(frame, senderID: senderID, mediaType: .audio, now: now())
    }

    /// Reports bounded admission/resource counts without identities, keys, or payloads.
    /// - Returns: Current binding/queue counts, admitted-operation and closure flags.
    public func snapshot() -> DAVEVoiceSessionSnapshot {
        .init(sourceCount: sources.count, pendingOperationCount: admission.pendingCount,
              operationIsActive: admission.active != nil, isClosed: closing)
    }

    /// Prevents further admission, rejects queued work, and awaits complete key cleanup.
    ///
    /// One shared cleanup task waits for the already admitted bounded cryptographic
    /// operation. No task cancellation can skip secret-owner closure. Repeated and
    /// concurrent calls await the same completion and introduce no additional waiters.
    public func close() async {
        if let cleanup { await cleanup.value; return }
        closing = true
        sources.removeAll(); userSources.removeAll()
        for ticket in admission.close() {
            pendingWaiters.removeValue(forKey: ticket.id)?.resume(throwing: DAVESessionError.closed)
        }
        pendingWaiters.removeAll(keepingCapacity: false)
        let task = Task { await self.dispose() }
        cleanup = task
        await task.value
    }

    /// Hides all source bindings, scope, signing identities and cryptographic state.
    public nonisolated var description: String { "DAVEVoiceSession([REDACTED])" }
    /// Uses the same fixed redaction when callers request debug formatting.
    public nonisolated var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing keys, closures or source identities.
    public nonisolated var customMirror: Mirror { Mirror(self, children: ["state": "[REDACTED]"]) }

    /// Reserves exclusive access or suspends in the bounded, control-prioritized queue.
    /// - Parameter control: Whether this operation can use the reserved control slot.
    /// - Throws: Cancellation, closure, or capacity exhaustion. Cancelled queued work
    ///   is removed without invoking DAVE or consuming a media nonce.
    private func acquire(control: Bool) async throws {
        let reservation = try admission.reserve(control: control)
        guard !reservation.admitted else { return }
        let id = reservation.ticket.id
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    _ = admission.cancel(id)
                    continuation.resume(throwing: CancellationError())
                    return
                }
                pendingWaiters[id] = continuation
            }
        } onCancel: {
            Task { await self.cancelAdmission(id) }
        }
        if Task.isCancelled { release(); throw CancellationError() }
    }

    /// Removes one cancelled queued operation; an admitted operation cleans up itself.
    /// - Parameter id: Unique admission identifier, never reused during this lifetime.
    private func cancelAdmission(_ id: UInt64) {
        guard admission.cancel(id) else { return }
        pendingWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    /// Fences a resumed admission against closure before consulting maps or crossing actors.
    /// A queued continuation can be granted just before another actor turn reserves close;
    /// terminal failure must remain `closed` rather than exposing cleared-map side effects.
    /// - Throws: Cancellation or `closed`; the caller's defer releases the reservation.
    private func validateAdmission() throws {
        try Task.checkCancellation()
        guard !closing else { throw DAVESessionError.closed }
    }

    /// Transfers exclusive ownership to the next control/media waiter or signals cleanup.
    /// Must run exactly once after successful admission, including every throwing exit.
    private func release() {
        if let next = admission.release() {
            pendingWaiters.removeValue(forKey: next.id)?.resume()
        } else {
            let waiter = idleWaiter; idleWaiter = nil
            waiter?.resume()
        }
    }

    /// Waits for the one admitted operation, then closes the privately owned protocol.
    /// No external caller can access the inner actor, so its overlap guard is clear
    /// when closure begins. This task is shared and intentionally never cancelled.
    private func dispose() async {
        if admission.active != nil { await withCheckedContinuation { idleWaiter = $0 } }
        try? await session.close()
    }
}
