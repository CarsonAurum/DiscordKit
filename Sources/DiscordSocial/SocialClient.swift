// File: Sources/DiscordSocial/SocialClient.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordLogging
import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation

/// Features coordinated by the common Social actor; extended typed APIs live on providers.
public enum SocialCapability: Sendable, CaseIterable { case profile, presence, relationshipState }

/// Consent/host admission result, separate from remote permissions or live qualification.
public enum SocialAvailability: Sendable, Equatable {
    case available, unauthorized, missingProvider, unavailableHost, missingScope, closed
}

/// Payload-free connection/authentication diagnostics; no credentials are stored here.
public struct SocialClientSnapshot: Sendable, Equatable {
    public let authorized: Bool
    public let closed: Bool
    public let inFlightOperations: Int
    public let changingAuthorization: Bool
}

/// Inert, bounded composition over independently owned public-protocol providers.
///
/// The application obtains/verifies OAuth grants, binds each injected client to the
/// same application/account, and explicitly activates the resulting scope. This actor
/// never derives user authority from a bot token. There are no tasks, sockets, token
/// persistence, provider discovery, automatic connections or mutation retries.
/// Operations execute in their callers' structured tasks. Disconnect fences results
/// and clears local observations; callers still cancel/await their in-flight work and
/// close shared provider clients. A remote mutation may finish during revocation.
public actor SocialClient<C: Clock> where C.Duration == Duration {
    private let clock: C
    private let profile: (any SocialProfileProvider<C>)?
    private let presence: (any SocialPresenceProvider<C>)?
    private let relationships: SocialRelationshipStore
    private let maximumOperations: Int
    private var scope: SocialScope?
    private var scopes: Set<String> = []
    private var hosts: Set<SocialHost> = []
    private var revision = UUID()
    private var changing = false
    private var closed = false
    private var inFlight = 0
    private var writingPresence = false

    /// Stores narrow providers and creates a bounded private relationship reducer without I/O.
    /// - Parameters:
    ///   - clock: Monotonic clock shared with all provider clients.
    ///   - profile: Optional consented-user reader. Nil makes profile capability unavailable.
    ///   - presence: Optional explicitly selected RPC or Activity writer; no automatic fallback.
    ///   - stateLimits: Positive validated limits for the private relationship store.
    ///   - maximumOperations: Fail-fast aggregate concurrent provider-call cap, `1...4096`;
    ///     defaults to 32. Counts remain reserved until each caller returns, even after revoke.
    /// - Throws: `SocialFailure.invalidConfiguration` for an invalid operation cap.
    public init(clock: C, profile: (any SocialProfileProvider<C>)? = nil,
                presence: (any SocialPresenceProvider<C>)? = nil,
                stateLimits: SocialStateLimits, maximumOperations: Int = 32) throws {
        guard (1...4096).contains(maximumOperations) else { throw SocialFailure.invalidConfiguration }
        self.clock = clock; self.profile = profile; self.presence = presence
        self.relationships = SocialRelationshipStore(limits: stateLimits)
        self.maximumOperations = maximumOperations
    }

    /// Activates application-verified user consent and erases the previous observation domain.
    /// - Parameters:
    ///   - scope: Nonzero application/account IDs and a fresh consent generation. This is
    ///     an application assertion, not a token exchange or independently verified grant.
    ///   - grantedScopes: Exact approved scopes, at most 128 strings of 128 UTF-8 bytes each.
    ///   - availableHosts: Hosts the embedding application actually qualified and authorized.
    ///     Defaults to empty; public HTTP needs no host assertion.
    /// - Throws: Invalid IDs/scopes, closed client, or concurrent authorization transition.
    ///   Existing provider calls retain admission and return stale-session errors after replacement.
    public func activate(scope: SocialScope, grantedScopes: Set<String>,
                         availableHosts: Set<SocialHost> = []) async throws {
        guard !closed else { throw SocialFailure.closed }
        guard !changing else { throw SocialFailure.mutationInProgress }
        guard scope.applicationID.rawValue != 0, scope.accountID.rawValue != 0,
              grantedScopes.count <= 128,
              grantedScopes.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 128 }) else {
            throw SocialFailure.invalidConfiguration
        }
        DiscordLog.makeLogger("social.client").trace("Social authorization replacement admitted", metadata: ["dk.event": "social.authorization.admitted",
            "dk.active_operations": .stringConvertible(inFlight)])
        changing = true; self.scope = nil; scopes = []; hosts = []
        revision = UUID(); let expected = revision
        defer { changing = false }
        try await relationships.activate(scope: scope)
        DiscordLog.makeLogger("social.client").trace("Social relationship scope activated", metadata: ["dk.event": "social.authorization.relationships.activated"])
        guard !closed, revision == expected else {
            await relationships.clear()
            throw SocialFailure.staleSession
        }
        self.scope = scope; scopes = grantedScopes; hosts = availableHosts
        DiscordLog.makeLogger("social.client").info("Social authorization activated", metadata: ["dk.event": "social.authorization.activated"])
    }

    /// Revokes local consent, fences pending results and releases all local relationship data.
    /// Shared transports and durable credentials remain application-owned. This method
    /// does not wait for provider calls or establish whether a submitted mutation executed.
    /// It is idempotent, including on a closed client; no new calls are admitted afterward
    /// until explicit activation succeeds.
    public func disconnect() async {
        DiscordLog.makeLogger("social.client").notice("Social authorization cleared", metadata: ["dk.event": "social.authorization.cleared",
            "dk.active_operations": .stringConvertible(inFlight)])
        revision = UUID(); scope = nil; scopes = []; hosts = []
        await relationships.clear()
    }

    /// Permanently disables admission and clears local data without closing shared providers.
    /// Repeated calls are harmless. Callers cancel/await outstanding calls before disposing
    /// their provider resources; closing this composition does not replay or undo mutations.
    public func close() async {
        if !closed {
            DiscordLog.makeLogger("social.client").info("Social client closing", metadata: ["dk.event": "social.client.closed"])
        }
        closed = true
        await disconnect()
    }

    /// Reports exact local prerequisites without probing hosts or issuing network requests.
    /// - Parameter capability: Common feature to inspect.
    /// - Returns: Availability at this actor turn; remote grants/host state can change later.
    public func availability(for capability: SocialCapability) -> SocialAvailability {
        if closed { return .closed }
        guard scope != nil, !changing else { return .unauthorized }
        let requirements: SocialProviderRequirements
        switch capability {
        case .relationshipState: return .available
        case .profile:
            guard let profile else { return .missingProvider }
            requirements = profile.profileRequirements
        case .presence:
            guard let presence else { return .missingProvider }
            requirements = presence.presenceRequirements
        }
        guard requirements.host == .none || hosts.contains(requirements.host) else { return .unavailableHost }
        guard requirements.scopes.isSubset(of: scopes) else { return .missingScope }
        return .available
    }

    /// Reads and validates the current profile against the explicitly activated account.
    /// - Parameter deadline: Inclusive absolute deadline in the injected clock; nil means none.
    /// - Returns: User projection only if consent remains current and its account ID matches.
    /// - Throws: Local prerequisite/budget/stale/account mismatch failures, cancellation,
    ///   deadline or safe `DiscordError`; unrecognized dependency errors become providerFailure.
    public func currentProfile(deadline: C.Instant? = nil) async throws -> User {
        let context = TransportContext(clock: clock, deadline: deadline)
        try context.check(); try require(.profile)
        guard inFlight < maximumOperations else { throw SocialFailure.overloaded }
        let expected = revision; let account = scope!.accountID; let provider = profile!
        inFlight += 1; defer { inFlight -= 1 }
        let logger = DiscordLog.makeLogger("social.client")
        logger.trace("Social profile read started", metadata: ["dk.event": "social.profile.started"])
        do {
            logger.trace("Social profile provider admitted", metadata: ["dk.event": "social.profile.provider.admitted",
                "dk.active_operations": .stringConvertible(inFlight)])
            let user = try await context.run { try await provider.currentProfile(context: context) }
            logger.trace("Social profile provider returned", metadata: ["dk.event": "social.profile.provider.completed"])
            try context.check(); try requireRevision(expected)
            guard user.id == account else { throw SocialFailure.accountMismatch }
            logger.trace("Social profile authorization remains current", metadata: ["dk.event": "social.profile.authorization.validated"])
            logger.debug("Social profile read completed", metadata: ["dk.event": "social.profile.completed"])
            return user
        } catch {
            if error is CancellationError || Task.isCancelled {
                logger.trace("Social profile read cancelled", metadata: ["dk.event": "social.profile.cancelled"])
            } else {
                logger.debug("Social profile read failed", metadata: ["dk.event": "social.profile.failed"])
            }
            throw safe(error)
        }
    }

    /// Serializes common presence mutations across authorization changes with fail-fast admission.
    /// - Parameters:
    ///   - value: Validated display fields; Activity name equality remains provider-enforced.
    ///   - deadline: Inclusive absolute deadline; nil means no additional deadline.
    /// - Throws: Prerequisite/budget/concurrent-mutation/stale failures, cancellation, deadline,
    ///   safe `DiscordError` or sanitized providerFailure. Cancellation, timeout and stale-session
    ///   errors do not prove the mutation was unapplied; reconcile before an explicit retry.
    public func updatePresence(_ value: SocialPresence, deadline: C.Instant? = nil) async throws {
        let context = TransportContext(clock: clock, deadline: deadline)
        try context.check(); try require(.presence)
        guard !writingPresence else { throw SocialFailure.mutationInProgress }
        guard inFlight < maximumOperations else { throw SocialFailure.overloaded }
        let expected = revision; let provider = presence!
        let logger = DiscordLog.makeLogger("social.client")
        logger.trace("Social presence write started", metadata: ["dk.event": "social.presence.started"])
        writingPresence = true; inFlight += 1
        defer { writingPresence = false; inFlight -= 1 }
        do {
            logger.trace("Social presence mutation ownership admitted", metadata: ["dk.event": "social.presence.provider.admitted",
                "dk.active_operations": .stringConvertible(inFlight)])
            try await context.run { try await provider.updatePresence(value, context: context) }
            logger.trace("Social presence provider returned", metadata: ["dk.event": "social.presence.provider.completed"])
            try context.check(); try requireRevision(expected)
            logger.debug("Social presence write completed", metadata: ["dk.event": "social.presence.completed"])
        } catch {
            if error is CancellationError || Task.isCancelled {
                logger.trace("Social presence write cancelled", metadata: ["dk.event": "social.presence.cancelled"])
            } else {
                logger.debug("Social presence write failed", metadata: ["dk.event": "social.presence.failed"])
            }
            throw safe(error)
        }
    }

    /// Replaces local observations from an application-normalized authorized provider snapshot.
    /// - Parameter snapshot: Complete exact-scope baseline; never an unverified SDK wire payload.
    /// - Returns: Reducer application result, including explicit stale-ignore behavior.
    /// - Throws: Local authorization/scope/stale-session or the reducer's validation/budget error.
    public func synchronize(_ snapshot: SocialStateSnapshot) async throws -> SocialApplyOutcome {
        try require(.relationshipState)
        guard snapshot.scope == scope else { throw SocialFailure.accountMismatch }
        let expected = revision
        let result = try await relationships.apply(snapshot: snapshot)
        try requireRevision(expected)
        DiscordLog.makeLogger("social.client").trace("Social relationship observation validated", metadata: ["dk.event": "social.relationships.observation.completed"])
        return result
    }

    /// Applies one trusted contiguous local-provider event without synthesizing remote mutations.
    /// - Parameter event: Exact-scope/generation/sequence observation.
    /// - Returns: Applied/stale/resync result; gaps and overflow never retain false freshness.
    /// - Throws: Authorization, account mismatch, stale session or reducer validation errors.
    public func apply(_ event: SocialStateEvent) async throws -> SocialApplyOutcome {
        try require(.relationshipState)
        guard event.scope == scope else { throw SocialFailure.accountMismatch }
        let expected = revision
        DiscordLog.makeLogger("social.client").trace("Social relationship event admitted", metadata: ["dk.event": "social.relationships.apply.admitted"])
        let result = try await relationships.apply(event: event)
        try requireRevision(expected)
        DiscordLog.makeLogger("social.client").trace("Social relationship observation validated", metadata: ["dk.event": "social.relationships.observation.completed"])
        return result
    }

    /// Reads a bounded sorted local view without implying current remote relationship authority.
    /// - Returns: Current exact-scope observations, or an inactive empty view after disconnect.
    /// - Throws: `SocialFailure.staleSession` if authorization changes across the actor hop.
    public func relationshipView() async throws -> SocialStateView {
        let expected = revision
        let result = await relationships.view()
        try requireRevision(expected)
        DiscordLog.makeLogger("social.client").trace("Social relationship observation validated", metadata: ["dk.event": "social.relationships.observation.completed"])
        return result
    }

    /// Returns payload-free auth/admission counters without waiting on providers or local state.
    /// - Returns: Authorization/closed flags and exact active caller count.
    public func snapshot() -> SocialClientSnapshot {
        SocialClientSnapshot(authorized: scope != nil, closed: closed,
            inFlightOperations: inFlight, changingAuthorization: changing)
    }

    /// Converts availability to a closed safe failure before any provider work is admitted.
    /// - Parameter capability: Common feature required by the caller.
    /// - Throws: Exact closed/local prerequisite failure; performs no I/O.
    private func require(_ capability: SocialCapability) throws {
        switch availability(for: capability) {
        case .available: return
        case .closed: throw SocialFailure.closed
        case .unauthorized: throw SocialFailure.unauthorized
        case .missingProvider: throw SocialFailure.missingProvider
        case .missingScope: throw SocialFailure.missingScope
        case .unavailableHost: throw SocialFailure.unavailableHost
        }
    }

    /// Fences results from replaced or revoked authorization without exposing either identity.
    /// - Parameter expected: Revision captured before suspension.
    /// - Throws: Stale-session failure when authorization changed, including permanent close.
    private func requireRevision(_ expected: UUID) throws {
        guard revision == expected else { throw SocialFailure.staleSession }
    }

    /// Preserves known safe errors and removes arbitrary provider diagnostic strings.
    /// - Parameter error: Dependency or local coordination error.
    /// - Returns: Safe cancellation/deadline/Discord/Social error, or providerFailure.
    private func safe(_ error: any Error) -> any Error {
        if error is CancellationError { return CancellationError() }
        if let failure = error as? SocialFailure { return failure }
        if let failure = error as? DiscordError { return failure }
        if let failure = error as? TransportFailure, failure == .deadlineExceeded { return failure }
        return SocialFailure.providerFailure
    }
}
