import DiscordCore
import Foundation

/// An application audience and opaque authorization lineage, never a credential.
/// Reuse the authorization identifier for publisher/game tokens belonging to the
/// same user grant; create a new identifier after reauthorization. Identifiers
/// must not contain account names or secrets, and must not become metric labels.
public struct OAuthTokenIdentity: Hashable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let applicationID: ApplicationID
    public let authorizationID: UUID

    /// Names one application's token within a grant without performing I/O.
    /// - Parameters:
    ///   - applicationID: The token's audience, including the game application for a child token.
    ///   - authorizationID: Stable opaque grant identifier shared with publisher children;
    ///     the default creates an independent grant. Never reuse a revoked grant's identifier.
    public init(applicationID: ApplicationID, authorizationID: UUID = UUID()) {
        self.applicationID = applicationID
        self.authorizationID = authorizationID
    }

    /// A constant diagnostic category concealing identifiers.
    public var description: String { "OAuthTokenIdentity(redacted)" }
    /// The same constant diagnostic category in debug output.
    public var debugDescription: String { description }
    /// Prevents reflected diagnostics from exposing authorization identifiers.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// A storage record whose credentials retain their explicitly redacted wrappers.
/// Storage implementations must encrypt and protect records appropriately; this
/// value is not encrypted memory and deliberately does not conform to Codable.
public struct OAuthStoredToken: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    public let accessToken: BearerToken
    public let refreshToken: OAuthRefreshToken?
    public let scopes: Set<String>
    public let expiresAt: Date
    public let generation: UUID
    public let parent: OAuthTokenIdentity?

    /// Creates a validated replacement record for an authoritative storage transaction.
    /// - Parameters:
    ///   - response: Validated bearer response; publisher children cannot carry refresh tokens.
    ///   - issuedAt: Conservative acquisition time used with response lifetime, in UTC.
    ///   - parent: Optional publisher identity. The coordinator and storage validate its existence.
    ///   - parentExpiresAt: Required for children; caps their original expiry even after parent refresh.
    ///   - retainingRefreshToken: Existing refresh token retained when a refresh response omits rotation.
    /// - Throws: `OAuthError.malformedResponse` for nonfinite times, missing parent expiry,
    ///   or a child response containing a refresh token. No credentials enter diagnostics.
    public init(response: OAuthTokenResponse, issuedAt: Date, parent: OAuthTokenIdentity? = nil,
                parentExpiresAt: Date? = nil, retainingRefreshToken: OAuthRefreshToken? = nil) throws {
        let expiration = issuedAt.addingTimeInterval(Double(response.expiresIn))
        guard issuedAt.timeIntervalSince1970.isFinite, expiration.timeIntervalSince1970.isFinite,
              parent == nil || (parentExpiresAt?.timeIntervalSince1970.isFinite == true && response.refreshToken == nil)
        else { throw OAuthError.malformedResponse }
        accessToken = response.accessToken
        refreshToken = parent == nil ? response.refreshToken ?? retainingRefreshToken : nil
        scopes = response.scopes
        expiresAt = parent == nil ? expiration : min(expiration, parentExpiresAt!)
        generation = UUID()
        self.parent = parent
    }

    /// A fixed marker concealing secrets, scopes, lineage and expiry metadata.
    public var description: String { "OAuthStoredToken(redacted)" }
    /// The same safe marker in debug descriptions.
    public var debugDescription: String { description }
    /// Prevents reflected diagnostics from exposing record contents.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Injected secure storage with atomic generation fences and publisher cascades.
///
/// Implementations own encryption, authorization, durability, bounded record and
/// lineage counts, and transactional consistency across workers. No insecure
/// default store is provided. Sharing this store prevents stale writes, but does
/// not itself single-flight refresh across processes: deployments must additionally
/// provide one coordinator owner or a distributed refresh lease per grant.
public protocol OAuthTokenStorage: Sendable {
    /// Loads a consistent record without logging credentials or identity metadata.
    /// - Parameter identity: Application audience and grant to load.
    /// - Returns: The current record, or nil after absence or a completed invalidation.
    /// - Throws: Storage failures; adapters must expose safe diagnostics.
    func load(for identity: OAuthTokenIdentity) async throws -> OAuthStoredToken?

    /// Atomically replaces the expected generation or removes its complete child lineage.
    /// - Parameters:
    ///   - identity: Record being inserted, replaced or invalidated.
    ///   - expectedGeneration: Required current generation; nil requires absence.
    ///   - replacement: New record, or nil to remove this record and all direct publisher children.
    ///   - now: Finite UTC instant for parent freshness validation.
    /// - Returns: False without changes for a generation mismatch or invalid parent.
    ///   A child insertion must require a present, unexpired root parent with the same
    ///   authorization identifier and another application audience, no refresh token,
    ///   and expiry no later than that parent's expiry. Parent refresh preserves child
    ///   records and their original expiry; parent removal deletes them atomically.
    /// - Throws: Storage failures. Transactions must never partially replace secrets or
    ///   partially remove descendants, even under cancellation or process failure.
    func compareExchange(for identity: OAuthTokenIdentity, expectedGeneration: UUID?,
                         replacement: OAuthStoredToken?, now: Date) async throws -> Bool
}

/// Explicit coordinator admission, freshness and generation failures without secrets.
public enum OAuthTokenFailure: Error, Equatable, Sendable {
    case capacityExceeded
    case closed
    case missingToken
    case expired
    case conflict
    case operationInProgress
    case invalidLineage
}

/// Bounded, explicitly adopted token ownership with one refresh per local audience/grant.
///
/// Construction starts no task or network I/O. Canceled callers return independently;
/// an already admitted refresh continues without subscribers so a rotated refresh
/// token can be persisted. Call `close()` to cancel and join all owned work. Refresh
/// and revocation closures must cooperate with cancellation, select credentials for
/// the identity's application, and must not replay ambiguous token exchanges.
/// Single-flight is process-local; storage fences prevent stale resurrection.
public actor OAuthTokenCoordinator {
    private struct Flight {
        let generation: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<BearerToken, any Error>]
        var invalidated = false
    }

    private let storage: any OAuthTokenStorage
    private let now: @Sendable () -> Date
    private let refresh: @Sendable (OAuthTokenIdentity, OAuthRefreshToken) async throws -> OAuthTokenResponse
    private let revoke: @Sendable (OAuthTokenIdentity, OAuthStoredToken) async throws -> Void
    private let refreshSkew: TimeInterval
    private let maximumIdentities: Int
    private let maximumWaiters: Int
    private let maximumWaitersPerIdentity: Int
    private var flights: [OAuthTokenIdentity: Flight] = [:]
    private var mutations: Set<UUID> = []
    private var waiterCount = 0
    private var closed = false

    /// Creates an idle coordinator with injected secure storage, clock and network policy.
    /// - Parameters:
    ///   - storage: Shared authoritative transactional secret storage.
    ///   - now: UTC clock used for persistent expiry; inject virtual time in tests.
    ///   - refreshSkew: Nonnegative finite seconds before expiry to refresh, default 30.
    ///   - maximumIdentities: Maximum owned exchanges plus mutations, default 128.
    ///   - maximumWaiters: Aggregate subscribers, default 1,024.
    ///   - maximumWaitersPerIdentity: Subscribers per audience/grant, default 128.
    ///   - refresh: One refresh exchange; no automatic retries. Its response is atomically stored.
    ///   - revoke: One revocation exchange after local durable invalidation, including parent cascades.
    /// - Precondition: All capacity bounds are positive and skew is finite and nonnegative.
    public init(storage: any OAuthTokenStorage, now: @escaping @Sendable () -> Date = { Date() },
                refreshSkew: TimeInterval = 30, maximumIdentities: Int = 128,
                maximumWaiters: Int = 1_024, maximumWaitersPerIdentity: Int = 128,
                refresh: @escaping @Sendable (OAuthTokenIdentity, OAuthRefreshToken) async throws -> OAuthTokenResponse,
                revoke: @escaping @Sendable (OAuthTokenIdentity, OAuthStoredToken) async throws -> Void) {
        precondition(refreshSkew.isFinite && refreshSkew >= 0)
        precondition(min(maximumIdentities, maximumWaiters, maximumWaitersPerIdentity) > 0)
        self.storage = storage
        self.now = now
        self.refreshSkew = refreshSkew
        self.maximumIdentities = maximumIdentities
        self.maximumWaiters = maximumWaiters
        self.maximumWaitersPerIdentity = maximumWaitersPerIdentity
        self.refresh = refresh
        self.revoke = revoke
    }

    /// Loads a fresh bearer or joins the one local refresh for this audience and grant.
    /// - Parameter identity: Stable identity; publisher child audiences never refresh directly.
    /// - Returns: An access token valid at completion. Freshly rotated tokens can lie within skew.
    /// - Throws: Cancellation for this caller, storage/exchange errors, `OAuthError.invalidGrant`
    ///   after durable invalidation, or `OAuthTokenFailure` for overload, expiry or conflicts.
    ///   Transient/ambiguous failures retain the record and never trigger an implicit replay.
    public func accessToken(for identity: OAuthTokenIdentity) async throws -> BearerToken {
        try Task.checkCancellation()
        let waiter = UUID()
        let token = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                register(identity: identity, waiter: waiter, continuation: continuation)
            }
        } onCancel: {
            Task { await self.cancel(identity: identity, waiter: waiter) }
        }
        try Task.checkCancellation()
        return token
    }

    /// Atomically installs a newly authorized or explicitly exchanged publisher child token.
    /// - Parameters:
    ///   - response: Validated OAuth response. Child responses cannot contain refresh tokens.
    ///   - identity: Token audience and grant; never reuse a revoked authorization identifier.
    ///   - parent: Present root publisher identity for a game token, otherwise nil.
    ///   - issuedAt: Conservative response acquisition time, no later than the injected clock;
    ///     nil uses the current clock instant. A future timestamp cannot extend token validity.
    /// - Throws: Cancellation before admission, storage errors, malformed times or lineage,
    ///   bounded admission failures, or conflict if another owner changes the record.
    ///   Concurrent local refresh results are fenced before persistence; unrelated grants continue.
    public func install(_ response: OAuthTokenResponse, for identity: OAuthTokenIdentity,
                        parent: OAuthTokenIdentity? = nil, issuedAt: Date? = nil) async throws {
        try beginMutation(identity)
        defer { mutations.remove(identity.authorizationID) }
        invalidateFlights(authorizationID: identity.authorizationID)
        let currentTime = try currentTime()
        let issuance = issuedAt ?? currentTime
        guard issuance.timeIntervalSince1970.isFinite, issuance <= currentTime else {
            throw OAuthError.malformedResponse
        }
        let current = try await storage.load(for: identity)
        var parentRecord: OAuthStoredToken?
        if let parent {
            guard parent.authorizationID == identity.authorizationID, parent.applicationID != identity.applicationID,
                  let loaded = try await storage.load(for: parent), loaded.parent == nil,
                  loaded.expiresAt > currentTime else { throw OAuthTokenFailure.invalidLineage }
            parentRecord = loaded
        }
        let replacement = try OAuthStoredToken(response: response, issuedAt: issuance,
            parent: parent, parentExpiresAt: parentRecord?.expiresAt)
        let completionTime = try self.currentTime()
        guard replacement.expiresAt > completionTime else { throw OAuthTokenFailure.expired }
        guard try await storage.compareExchange(for: identity, expectedGeneration: current?.generation,
            replacement: replacement, now: completionTime) else { throw OAuthTokenFailure.conflict }
    }

    /// Durably invalidates a grant before attempting one remote revocation exchange.
    /// - Parameter identity: Audience to revoke; a root publisher cascades to all stored children.
    /// - Throws: Cancellation before admission, bounded/mutation conflicts or storage/exchange errors.
    ///   Remote failure leaves local tokens invalidated; callers must treat server state as unknown
    ///   and must not automatically replay an ambiguous operation. Missing records are a no-op.
    public func revokeToken(for identity: OAuthTokenIdentity) async throws {
        try beginMutation(identity)
        defer { mutations.remove(identity.authorizationID) }
        guard let record = try await removeToken(for: identity) else { return }
        try await revoke(identity, record)
    }

    /// Applies an externally observed revocation or unmerge to local authoritative storage only.
    /// - Parameter identity: Invalidated audience/grant; root publishers atomically remove their children.
    /// - Throws: Cancellation before admission, storage errors, bounded/mutation conflicts or a stale
    ///   generation conflict. Missing records are harmless. Local pending callers fail with conflict,
    ///   and generation fences prevent late refresh results from resurrecting the removed grant.
    ///   No revocation exchange, retry, new authorization or background network work is started.
    public func invalidateToken(for identity: OAuthTokenIdentity) async throws {
        try beginMutation(identity)
        defer { mutations.remove(identity.authorizationID) }
        _ = try await removeToken(for: identity)
    }

    /// Rejects new work, promptly releases subscribers and joins all owned exchanges.
    /// Repeated calls join the same remaining cleanup. Storage remains owned by its caller.
    /// In-progress install/invalidate/revoke calls are caller-owned and must be awaited by that caller.
    public func close() async {
        closed = true
        let current = flights
        for identity in current.keys { invalidateFlight(identity, error: OAuthTokenFailure.closed) }
        for flight in current.values { await flight.task.value }
    }

    /// Reports bounded ownership counts without credential or account labels.
    /// - Returns: Active exchanges, waiting callers, and caller-owned mutation count.
    public func snapshot() -> (flights: Int, waiters: Int, mutations: Int) {
        (flights.count, waiterCount, mutations.count)
    }

    /// Validates mutation admission and reserves one grant across actor suspension points.
    /// - Parameter identity: Grant whose local operations are temporarily fenced.
    /// - Throws: Cancellation, closed ownership, overload or an already active mutation.
    private func beginMutation(_ identity: OAuthTokenIdentity) throws {
        try Task.checkCancellation()
        guard !closed else { throw OAuthTokenFailure.closed }
        guard !mutations.contains(identity.authorizationID) else { throw OAuthTokenFailure.operationInProgress }
        guard flights.count + mutations.count < maximumIdentities else { throw OAuthTokenFailure.capacityExceeded }
        mutations.insert(identity.authorizationID)
    }

    /// Rejects nonfinite injected clock values before any expiry comparison or transaction.
    /// - Returns: The finite UTC instant supplied by the injected clock.
    /// - Throws: `OAuthError.malformedResponse` for a nonfinite clock instant.
    private func currentTime() throws -> Date {
        let instant = now()
        guard instant.timeIntervalSince1970.isFinite else { throw OAuthError.malformedResponse }
        return instant
    }

    /// Fences local readers and performs one atomic durable removal before any optional remote work.
    /// - Parameter identity: Exact record; storage removal cascades only its publisher descendants.
    /// - Returns: The removed record for a deliberate revocation exchange, or nil for absence.
    /// - Throws: Storage errors, nonfinite clock input, or conflict when another owner changes the record.
    private func removeToken(for identity: OAuthTokenIdentity) async throws -> OAuthStoredToken? {
        invalidateFlights(authorizationID: identity.authorizationID)
        guard let record = try await storage.load(for: identity) else { return nil }
        guard try await storage.compareExchange(for: identity, expectedGeneration: record.generation,
            replacement: nil, now: currentTime()) else { throw OAuthTokenFailure.conflict }
        return record
    }

    /// Registers an independent continuation before starting or joining bounded owned work.
    /// - Parameters:
    ///   - identity: Audience/grant used as the single-flight key.
    ///   - waiter: Unique cancellation token.
    ///   - continuation: Exactly-once completion retained until cancellation or publication.
    private func register(identity: OAuthTokenIdentity, waiter: UUID,
                          continuation: CheckedContinuation<BearerToken, any Error>) {
        guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
        guard !closed else { continuation.resume(throwing: OAuthTokenFailure.closed); return }
        guard !mutations.contains(identity.authorizationID) else {
            continuation.resume(throwing: OAuthTokenFailure.operationInProgress); return
        }
        guard waiterCount < maximumWaiters else {
            continuation.resume(throwing: OAuthTokenFailure.capacityExceeded); return
        }
        if var flight = flights[identity] {
            guard !flight.invalidated else { continuation.resume(throwing: OAuthTokenFailure.conflict); return }
            guard flight.waiters.count < maximumWaitersPerIdentity else {
                continuation.resume(throwing: OAuthTokenFailure.capacityExceeded); return
            }
            flight.waiters[waiter] = continuation
            flights[identity] = flight
        } else {
            guard flights.count + mutations.count < maximumIdentities else {
                continuation.resume(throwing: OAuthTokenFailure.capacityExceeded); return
            }
            let generation = UUID()
            let task = Task {
                let result: Result<BearerToken, any Error>
                do { result = .success(try await resolve(identity)) }
                catch { result = .failure(error) }
                finish(identity: identity, generation: generation, result: result)
            }
            flights[identity] = Flight(generation: generation, task: task, waiters: [waiter: continuation])
        }
        waiterCount += 1
    }

    /// Returns a fresh record or performs exactly one fenced refresh, without implicit replay.
    /// - Parameter identity: Audience/grant to resolve.
    /// - Returns: Current or newly refreshed bearer token.
    /// - Throws: Missing/expired token, invalid grant, generation conflict or injected failures.
    private func resolve(_ identity: OAuthTokenIdentity) async throws -> BearerToken {
        try Task.checkCancellation()
        guard let record = try await storage.load(for: identity) else { throw OAuthTokenFailure.missingToken }
        var instant = try currentTime()
        if let parent = record.parent {
            let ancestor = try await storage.load(for: parent)
            instant = try currentTime()
            // A refreshed parent's new access expiry cannot shorten an already
            // issued child's original expiry. Durable parent removal is the fence.
            guard let ancestor, ancestor.parent == nil else {
                _ = try await storage.compareExchange(for: identity, expectedGeneration: record.generation,
                    replacement: nil, now: instant)
                throw OAuthTokenFailure.expired
            }
        }
        if record.expiresAt.timeIntervalSince(instant) > refreshSkew { return record.accessToken }
        guard record.parent == nil, let refreshToken = record.refreshToken else {
            if record.expiresAt <= instant {
                _ = try await storage.compareExchange(for: identity, expectedGeneration: record.generation,
                    replacement: nil, now: instant)
                throw OAuthTokenFailure.expired
            }
            return record.accessToken
        }
        let response: OAuthTokenResponse
        try Task.checkCancellation()
        do { response = try await refresh(identity, refreshToken) }
        catch {
            if let failure = error as? OAuthError, failure == .invalidGrant {
                _ = try await storage.compareExchange(for: identity, expectedGeneration: record.generation,
                    replacement: nil, now: currentTime())
            }
            throw error
        }
        // Persist a received rotation even if subscribers have since canceled.
        let replacement = try OAuthStoredToken(response: response, issuedAt: instant,
            retainingRefreshToken: refreshToken)
        let completion = try currentTime()
        guard try await storage.compareExchange(for: identity, expectedGeneration: record.generation,
            replacement: replacement, now: completion) else { throw OAuthTokenFailure.conflict }
        guard replacement.expiresAt > completion else { throw OAuthTokenFailure.expired }
        return replacement.accessToken
    }

    /// Releases one caller promptly while keeping an admitted rotation owned until completion.
    /// - Parameters:
    ///   - identity: Audience/grant flight.
    ///   - waiter: Subscriber token; already completed or canceled tokens are harmless.
    private func cancel(identity: OAuthTokenIdentity, waiter: UUID) {
        guard var flight = flights[identity], let continuation = flight.waiters.removeValue(forKey: waiter) else { return }
        flights[identity] = flight
        waiterCount -= 1
        continuation.resume(throwing: CancellationError())
    }

    /// Cancels local snapshots for an entire grant before explicit mutation crosses suspension.
    /// - Parameter authorizationID: Opaque lineage; all audiences are conservatively fenced.
    private func invalidateFlights(authorizationID: UUID) {
        for identity in flights.keys.filter({ $0.authorizationID == authorizationID }) {
            invalidateFlight(identity, error: OAuthTokenFailure.conflict)
        }
    }

    /// Releases subscribers once and retains canceled task ownership until its final cleanup.
    /// - Parameters:
    ///   - identity: Audience/grant flight to fence, if present.
    ///   - error: Safe lifecycle or generation failure delivered to existing subscribers.
    private func invalidateFlight(_ identity: OAuthTokenIdentity, error: any Error) {
        guard var flight = flights[identity] else { return }
        waiterCount -= flight.waiters.count
        for continuation in flight.waiters.values { continuation.resume(throwing: error) }
        flight.waiters.removeAll()
        flight.invalidated = true
        flights[identity] = flight
        flight.task.cancel()
    }

    /// Publishes one matching generation and releases its bounded ownership accounting.
    /// - Parameters:
    ///   - identity: Audience/grant flight.
    ///   - generation: Fence against stale completion.
    ///   - result: Access token or safe adapter/coordinator error, delivered independently.
    private func finish(identity: OAuthTokenIdentity, generation: UUID, result: Result<BearerToken, any Error>) {
        guard let flight = flights[identity], flight.generation == generation else { return }
        flights.removeValue(forKey: identity)
        waiterCount -= flight.waiters.count
        for continuation in flight.waiters.values { continuation.resume(with: result) }
    }
}
