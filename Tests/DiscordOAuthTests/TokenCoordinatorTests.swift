import DiscordCore
import DiscordTestSupport
import Foundation
import Testing
@testable import DiscordOAuth

/// Offline token ownership regressions using explicit UTC time and gated exchanges.
@Suite(.timeLimit(.minutes(1)))
struct TokenCoordinatorTests {
    /// Fresh tokens avoid requests; the inclusive skew boundary refreshes once and retains omitted rotation.
    @Test func freshnessSkewAndRotation() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let clock = ManualClock()
        let storage = TokenTestStorage()
        let counter = TokenTestCounter()
        let coordinator = OAuthTokenCoordinator(storage: storage, now: { tokenTestDate(clock) }, refresh: { _, token in
            #expect(token.withUnsafeValue { $0 } == "refresh-old")
            await counter.increment()
            return try tokenTestResponse("new", lifetime: 200, refresh: nil)
        }, revoke: { _, _ in Issue.record("Unexpected revocation") })
        let identity = OAuthTokenIdentity(applicationID: .init(rawValue: 1))
        try await coordinator.install(tokenTestResponse("old", lifetime: 100), for: identity)
        #expect(try await coordinator.accessToken(for: identity).withUnsafeValue { $0 } == "old")
        #expect(await counter.value == 0)
        try clock.advance(by: .seconds(70))
        #expect(try await coordinator.accessToken(for: identity).withUnsafeValue { $0 } == "new")
        #expect(await counter.value == 1)
        let record = try #require(await storage.load(for: identity))
        #expect(record.expiresAt == Date(timeIntervalSince1970: 270))
        #expect(record.refreshToken?.withUnsafeValue { $0 } == "refresh-old")
        #expect(String(describing: record) == "OAuthStoredToken(redacted)")
        #expect(String(reflecting: record) == "OAuthStoredToken(redacted)")
        #expect(record.customMirror.children.count == 1)
        #expect(String(describing: identity) == "OAuthTokenIdentity(redacted)")
        #expect(String(reflecting: identity) == "OAuthTokenIdentity(redacted)")
        #expect(identity.customMirror.children.count == 1)
        await coordinator.close()
    }

    /// Many callers share one rotating exchange; one canceled waiter leaves all others unaffected.
    @Test func sharedRefreshAndIndependentCancellation() async throws {
        let storage = TokenTestStorage()
        let gate = TokenTestGate()
        let counter = TokenTestCounter()
        let coordinator = OAuthTokenCoordinator(storage: storage, now: { Date(timeIntervalSince1970: 0) }, refresh: { _, _ in
            await counter.increment()
            await gate.wait()
            return try tokenTestResponse("rotated")
        }, revoke: { _, _ in })
        let identity = OAuthTokenIdentity(applicationID: .init(rawValue: 1))
        try await coordinator.install(tokenTestResponse("old", lifetime: 1), for: identity)
        let tasks = (0..<64).map { _ in Task { try await coordinator.accessToken(for: identity) } }
        while await coordinator.snapshot().waiters < 64 { try Task.checkCancellation(); await Task.yield() }
        while await gate.waiters < 1 { try Task.checkCancellation(); await Task.yield() }
        #expect(await counter.value == 1)
        tasks[0].cancel()
        await #expect(throws: CancellationError.self) { try await tasks[0].value }
        #expect(await coordinator.snapshot().waiters == 63)
        await gate.open()
        for task in tasks.dropFirst() {
            #expect(try await task.value.withUnsafeValue { $0 } == "rotated")
        }
        #expect(await coordinator.snapshot().flights == 0)
        #expect(await coordinator.snapshot().waiters == 0)
        await coordinator.close()
    }

    /// Final subscriber cancellation returns promptly while owned work durably preserves a received rotation.
    @Test func abandonedRefreshRemainsOwned() async throws {
        let storage = TokenTestStorage()
        let gate = TokenTestGate()
        let coordinator = OAuthTokenCoordinator(storage: storage, now: { Date(timeIntervalSince1970: 0) }, refresh: { _, _ in
            await gate.wait()
            return try tokenTestResponse("persisted", refresh: "refresh-new")
        }, revoke: { _, _ in })
        let identity = OAuthTokenIdentity(applicationID: .init(rawValue: 1))
        try await coordinator.install(tokenTestResponse("old", lifetime: 1), for: identity)
        let task = Task { try await coordinator.accessToken(for: identity) }
        while await gate.waiters == 0 { try Task.checkCancellation(); await Task.yield() }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await coordinator.snapshot().waiters == 0)
        #expect(await coordinator.snapshot().flights == 1)
        await gate.open()
        while await coordinator.snapshot().flights != 0 { try Task.checkCancellation(); await Task.yield() }
        let record = try #require(await storage.load(for: identity))
        #expect(record.accessToken.withUnsafeValue { $0 } == "persisted")
        #expect(record.refreshToken?.withUnsafeValue { $0 } == "refresh-new")
        await coordinator.close()
    }

    /// Finite identity/subscriber limits reject overload; different application audiences never coalesce.
    @Test func capacityAndApplicationIsolation() async throws {
        let storage = TokenTestStorage()
        let gate = TokenTestGate()
        let counter = TokenTestCounter()
        let coordinator = OAuthTokenCoordinator(storage: storage, now: { Date(timeIntervalSince1970: 0) },
            maximumIdentities: 2, maximumWaiters: 3, maximumWaitersPerIdentity: 2, refresh: { _, _ in
                await counter.increment()
                await gate.wait()
                return try tokenTestResponse("new")
            }, revoke: { _, _ in })
        let first = OAuthTokenIdentity(applicationID: .init(rawValue: 1))
        let second = OAuthTokenIdentity(applicationID: .init(rawValue: 2), authorizationID: first.authorizationID)
        let third = OAuthTokenIdentity(applicationID: .init(rawValue: 3))
        for identity in [first, second, third] {
            try await coordinator.install(tokenTestResponse("old", lifetime: 1), for: identity)
        }
        let firstTask = Task { try await coordinator.accessToken(for: first) }
        while await coordinator.snapshot().waiters < 1 { try Task.checkCancellation(); await Task.yield() }
        let joined = Task { try await coordinator.accessToken(for: first) }
        while await coordinator.snapshot().waiters < 2 { try Task.checkCancellation(); await Task.yield() }
        await #expect(throws: OAuthTokenFailure.capacityExceeded) { try await coordinator.accessToken(for: first) }
        let secondTask = Task { try await coordinator.accessToken(for: second) }
        while await coordinator.snapshot().waiters < 3 { try Task.checkCancellation(); await Task.yield() }
        while await gate.waiters < 2 { try Task.checkCancellation(); await Task.yield() }
        await #expect(throws: OAuthTokenFailure.capacityExceeded) { try await coordinator.accessToken(for: third) }
        #expect(await counter.value == 2)
        await gate.open()
        for task in [firstTask, joined, secondTask] { #expect(try await task.value.withUnsafeValue { $0 } == "new") }
        await coordinator.close()
    }

    /// A definitive invalid grant atomically removes its publisher children; ambiguous failures preserve storage.
    @Test func invalidGrantAndTransientFailure() async throws {
        let storage = TokenTestStorage()
        let counter = TokenTestCounter()
        let coordinator = OAuthTokenCoordinator(storage: storage, now: { Date(timeIntervalSince1970: 0) }, refresh: { _, _ in
            await counter.increment()
            throw OAuthError.invalidGrant
        }, revoke: { _, _ in })
        let parent = OAuthTokenIdentity(applicationID: .init(rawValue: 1))
        let child = OAuthTokenIdentity(applicationID: .init(rawValue: 2), authorizationID: parent.authorizationID)
        try await coordinator.install(tokenTestResponse("parent", lifetime: 10), for: parent)
        try await coordinator.install(tokenTestResponse("child", lifetime: 10, refresh: nil), for: child, parent: parent)
        await #expect(throws: OAuthError.invalidGrant) { try await coordinator.accessToken(for: parent) }
        #expect(try await storage.load(for: parent) == nil)
        #expect(try await storage.load(for: child) == nil)
        await #expect(throws: OAuthTokenFailure.missingToken) { try await coordinator.accessToken(for: parent) }
        #expect(await counter.value == 1)
        await coordinator.close()

        let transient = OAuthTokenCoordinator(storage: storage, now: { Date(timeIntervalSince1970: 0) }, refresh: { _, _ in
            await counter.increment()
            throw TokenTestFailure.ambiguous
        }, revoke: { _, _ in })
        try await transient.install(tokenTestResponse("old", lifetime: 1), for: parent)
        let generation = try #require(await storage.load(for: parent)).generation
        await #expect(throws: TokenTestFailure.ambiguous) { try await transient.accessToken(for: parent) }
        #expect(try await storage.load(for: parent)?.generation == generation)
        #expect(await counter.value == 2)
        await transient.close()
    }

    /// Publisher refresh preserves child expiry; child expiry and revocation do not remove the parent or siblings.
    @Test func publisherExpiryAndChildRevocation() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let clock = ManualClock()
        let storage = TokenTestStorage()
        let revoked = TokenTestCounter()
        let coordinator = OAuthTokenCoordinator(storage: storage, now: { tokenTestDate(clock) }, refresh: { _, _ in
            try tokenTestResponse("parent-new", lifetime: 5)
        }, revoke: { identity, record in
            #expect(identity.applicationID.rawValue == 2)
            #expect(record.parent != nil)
            await revoked.increment()
        })
        let parent = OAuthTokenIdentity(applicationID: .init(rawValue: 1))
        let child = OAuthTokenIdentity(applicationID: .init(rawValue: 2), authorizationID: parent.authorizationID)
        let sibling = OAuthTokenIdentity(applicationID: .init(rawValue: 3), authorizationID: parent.authorizationID)
        try await coordinator.install(tokenTestResponse("parent", lifetime: 40), for: parent)
        for identity in [child, sibling] {
            try await coordinator.install(tokenTestResponse("child", lifetime: 400, refresh: nil), for: identity, parent: parent)
        }
        #expect(try await storage.load(for: child)?.expiresAt == Date(timeIntervalSince1970: 40))
        try clock.advance(by: .seconds(10))
        #expect(try await coordinator.accessToken(for: parent).withUnsafeValue { $0 } == "parent-new")
        #expect(try await storage.load(for: child)?.expiresAt == Date(timeIntervalSince1970: 40))
        #expect(try await storage.load(for: parent)?.expiresAt == Date(timeIntervalSince1970: 15))
        try clock.advance(by: .seconds(10))
        #expect(try await coordinator.accessToken(for: child).withUnsafeValue { $0 } == "child")
        try await coordinator.revokeToken(for: child)
        #expect(await revoked.value == 1)
        #expect(try await storage.load(for: parent) != nil)
        #expect(try await storage.load(for: sibling) != nil)
        try clock.advance(by: .seconds(20))
        await #expect(throws: OAuthTokenFailure.expired) { try await coordinator.accessToken(for: sibling) }
        #expect(try await storage.load(for: sibling) == nil)
        #expect(try await storage.load(for: parent) != nil)
        await coordinator.close()
    }

    /// Revocation wins against a cancellation-ignoring late refresh and cascades children before remote failure.
    @Test func revokeFencesLateRefreshAndCascades() async throws {
        let storage = TokenTestStorage()
        let gate = TokenTestGate()
        let coordinator = OAuthTokenCoordinator(storage: storage, now: { Date(timeIntervalSince1970: 0) }, refresh: { _, _ in
            await gate.wait()
            return try tokenTestResponse("too-late")
        }, revoke: { _, _ in throw TokenTestFailure.ambiguous })
        let parent = OAuthTokenIdentity(applicationID: .init(rawValue: 1))
        let child = OAuthTokenIdentity(applicationID: .init(rawValue: 2), authorizationID: parent.authorizationID)
        try await coordinator.install(tokenTestResponse("parent", lifetime: 1), for: parent)
        try await coordinator.install(tokenTestResponse("child", lifetime: 1, refresh: nil), for: child, parent: parent)
        let task = Task { try await coordinator.accessToken(for: parent) }
        while await gate.waiters == 0 { try Task.checkCancellation(); await Task.yield() }
        await #expect(throws: TokenTestFailure.ambiguous) { try await coordinator.revokeToken(for: parent) }
        await #expect(throws: OAuthTokenFailure.conflict) { try await task.value }
        #expect(try await storage.load(for: parent) == nil)
        #expect(try await storage.load(for: child) == nil)
        await gate.open()
        await coordinator.close()
        #expect(try await storage.load(for: parent) == nil)
        #expect(await coordinator.snapshot().flights == 0)
        #expect(await coordinator.snapshot().mutations == 0)
    }

    /// External generation changes reject stale rotations without replay or replacing the winning secret.
    @Test func externalReplacementIsAtomic() async throws {
        let storage = TokenTestStorage()
        let gate = TokenTestGate()
        let coordinator = OAuthTokenCoordinator(storage: storage, now: { Date(timeIntervalSince1970: 0) }, refresh: { _, _ in
            await gate.wait()
            return try tokenTestResponse("stale")
        }, revoke: { _, _ in })
        let identity = OAuthTokenIdentity(applicationID: .init(rawValue: 1))
        try await coordinator.install(tokenTestResponse("old", lifetime: 1), for: identity)
        let task = Task { try await coordinator.accessToken(for: identity) }
        while await gate.waiters == 0 { try Task.checkCancellation(); await Task.yield() }
        let old = try #require(await storage.load(for: identity))
        let winner = try OAuthStoredToken(response: tokenTestResponse("winner"), issuedAt: Date(timeIntervalSince1970: 0))
        #expect(try await storage.compareExchange(for: identity, expectedGeneration: old.generation,
            replacement: winner, now: Date(timeIntervalSince1970: 0)))
        await gate.open()
        await #expect(throws: OAuthTokenFailure.conflict) { try await task.value }
        #expect(try await storage.load(for: identity)?.accessToken.withUnsafeValue { $0 } == "winner")
        await coordinator.close()
    }

    /// Observed unmerge/deauthorization invalidates locally, cascades children and fences late refresh without network revocation.
    @Test func externalInvalidationHasNoRemoteSideEffects() async throws {
        let storage = TokenTestStorage()
        let gate = TokenTestGate()
        let revocations = TokenTestCounter()
        let coordinator = OAuthTokenCoordinator(storage: storage, now: { Date(timeIntervalSince1970: 0) }, refresh: { _, _ in
            await gate.wait()
            return try tokenTestResponse("stale")
        }, revoke: { _, _ in await revocations.increment() })
        let parent = OAuthTokenIdentity(applicationID: .init(rawValue: 1))
        let child = OAuthTokenIdentity(applicationID: .init(rawValue: 2), authorizationID: parent.authorizationID)
        let unrelated = OAuthTokenIdentity(applicationID: .init(rawValue: 3))
        try await coordinator.install(tokenTestResponse("parent", lifetime: 1), for: parent)
        try await coordinator.install(tokenTestResponse("child", lifetime: 1, refresh: nil), for: child, parent: parent)
        try await coordinator.install(tokenTestResponse("unrelated"), for: unrelated)
        let task = Task { try await coordinator.accessToken(for: parent) }
        while await gate.waiters == 0 { try Task.checkCancellation(); await Task.yield() }
        try await coordinator.invalidateToken(for: parent)
        await #expect(throws: OAuthTokenFailure.conflict) { try await task.value }
        #expect(try await storage.load(for: parent) == nil)
        #expect(try await storage.load(for: child) == nil)
        #expect(try await storage.load(for: unrelated) != nil)
        #expect(await revocations.value == 0)
        #expect(await coordinator.snapshot().mutations == 0)
        try await coordinator.invalidateToken(for: parent)
        await gate.open()
        await coordinator.close()
        #expect(try await storage.load(for: parent) == nil)
        #expect(await revocations.value == 0)
        #expect(await coordinator.snapshot().flights == 0)
        await #expect(throws: OAuthTokenFailure.closed) { try await coordinator.invalidateToken(for: parent) }
    }

    /// Expired nonrefreshable tokens are removed; invalid lineage, dates and canceled callers never start exchange work.
    @Test func missingExpiryLineageAndClockValidation() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let storage = TokenTestStorage()
        let clock = ManualClock()
        let coordinator = OAuthTokenCoordinator(storage: storage, now: { tokenTestDate(clock) }, refresh: { _, _ in
            Issue.record("Unexpected refresh")
            throw TokenTestFailure.ambiguous
        }, revoke: { _, _ in Issue.record("Unexpected revocation") })
        let parent = OAuthTokenIdentity(applicationID: .init(rawValue: 1))
        let child = OAuthTokenIdentity(applicationID: .init(rawValue: 2), authorizationID: parent.authorizationID)
        await #expect(throws: OAuthTokenFailure.missingToken) { try await coordinator.accessToken(for: parent) }
        await #expect(throws: OAuthTokenFailure.invalidLineage) {
            try await coordinator.install(tokenTestResponse("child", refresh: nil), for: child, parent: parent)
        }
        try await coordinator.install(tokenTestResponse("parent", lifetime: 10, refresh: nil), for: parent)
        await #expect(throws: OAuthError.malformedResponse) {
            try await coordinator.install(tokenTestResponse("child"), for: child, parent: parent)
        }
        await #expect(throws: OAuthTokenFailure.invalidLineage) {
            try await coordinator.install(tokenTestResponse("self", refresh: nil), for: parent, parent: parent)
        }
        await #expect(throws: OAuthTokenFailure.invalidLineage) {
            try await coordinator.install(tokenTestResponse("foreign", refresh: nil),
                for: .init(applicationID: .init(rawValue: 3)), parent: parent)
        }
        await #expect(throws: OAuthError.malformedResponse) {
            try await coordinator.install(tokenTestResponse("invalid"), for: parent,
                issuedAt: Date(timeIntervalSince1970: .infinity))
        }
        await #expect(throws: OAuthError.malformedResponse) {
            try await coordinator.install(tokenTestResponse("future"), for: parent,
                issuedAt: Date(timeIntervalSince1970: 1))
        }
        #expect(await coordinator.snapshot().mutations == 0)
        try clock.advance(by: .seconds(10))
        await #expect(throws: OAuthTokenFailure.expired) { try await coordinator.accessToken(for: parent) }
        #expect(try await storage.load(for: parent) == nil)
        try await coordinator.revokeToken(for: parent)
        await coordinator.close()
        await coordinator.close()
        await #expect(throws: OAuthTokenFailure.closed) { try await coordinator.accessToken(for: parent) }
        await #expect(throws: OAuthTokenFailure.closed) { try await coordinator.install(tokenTestResponse("closed"), for: parent) }
        await #expect(throws: OAuthTokenFailure.closed) { try await coordinator.revokeToken(for: parent) }
        #expect(await coordinator.snapshot().waiters == 0)
    }

    /// Close cooperatively joins cancellation cleanup and releases every retained subscriber once.
    @Test func closeAndPreCanceledCaller() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let storage = TokenTestStorage()
        let gate = TestBarrier()
        let coordinator = OAuthTokenCoordinator(storage: storage, now: { Date(timeIntervalSince1970: 0) }, refresh: { _, _ in
            try await gate.wait()
            return try tokenTestResponse("unexpected")
        }, revoke: { _, _ in })
        let identity = OAuthTokenIdentity(applicationID: .init(rawValue: 1))
        try await coordinator.install(tokenTestResponse("old", lifetime: 1), for: identity)
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await coordinator.accessToken(for: identity)
        }
        await #expect(throws: CancellationError.self) { try await canceled.value }
        #expect(await coordinator.snapshot().flights == 0)
        let task = Task { try await coordinator.accessToken(for: identity) }
        while gate.waitingCount == 0 { try Task.checkCancellation(); await Task.yield() }
        await coordinator.close()
        await #expect(throws: OAuthTokenFailure.closed) { try await task.value }
        #expect(gate.waitingCount == 0)
        #expect(await coordinator.snapshot().flights == 0)
        #expect(await coordinator.snapshot().waiters == 0)
    }

    /// Response expiry during exchange still stores rotation; invalid clocks and storage failures never publish tokens.
    @Test func expiredRotationAndStorageFailure() async throws {
        guard #available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *) else { return }
        let clock = ManualClock()
        let storage = TokenTestStorage()
        let coordinator = OAuthTokenCoordinator(storage: storage, now: { tokenTestDate(clock) }, refresh: { _, _ in
            try clock.advance(by: .seconds(3))
            return try tokenTestResponse("expired-rotation", lifetime: 2, refresh: "retained-rotation")
        }, revoke: { _, _ in })
        let identity = OAuthTokenIdentity(applicationID: .init(rawValue: 1))
        try await coordinator.install(tokenTestResponse("old", lifetime: 1), for: identity)
        await #expect(throws: OAuthTokenFailure.expired) { try await coordinator.accessToken(for: identity) }
        #expect(try await storage.load(for: identity)?.refreshToken?.withUnsafeValue { $0 } == "retained-rotation")
        await coordinator.close()

        let invalidClock = OAuthTokenCoordinator(storage: storage, now: { Date(timeIntervalSince1970: .infinity) },
            refresh: { _, _ in throw TokenTestFailure.ambiguous }, revoke: { _, _ in })
        await #expect(throws: OAuthError.malformedResponse) { try await invalidClock.accessToken(for: identity) }
        await #expect(throws: OAuthError.malformedResponse) {
            try await invalidClock.install(tokenTestResponse("invalid-clock"), for: identity)
        }
        await invalidClock.close()

        let failingStore = TokenTestFailingStorage()
        let failed = OAuthTokenCoordinator(storage: failingStore, refresh: { _, _ in throw TokenTestFailure.ambiguous },
            revoke: { _, _ in })
        await #expect(throws: TokenTestFailure.ambiguous) { try await failed.accessToken(for: identity) }
        #expect(await failed.snapshot().flights == 0)
        await #expect(throws: TokenTestFailure.ambiguous) { try await failed.install(tokenTestResponse("failed"), for: identity) }
        #expect(await failed.snapshot().mutations == 0)
        await failed.close()
    }

    /// An active revocation fences its grant while unrelated reads continue and mutation ownership remains bounded.
    @Test func mutationAdmissionAndGrantIsolation() async throws {
        let storage = TokenTestStorage()
        let gate = TokenTestGate()
        let coordinator = OAuthTokenCoordinator(storage: storage, now: { Date(timeIntervalSince1970: 0) }, refresh: { _, _ in
            Issue.record("Unexpected refresh")
            throw TokenTestFailure.ambiguous
        }, revoke: { _, _ in await gate.wait() })
        let identity = OAuthTokenIdentity(applicationID: .init(rawValue: 1))
        let unrelated = OAuthTokenIdentity(applicationID: .init(rawValue: 2))
        try await coordinator.install(tokenTestResponse("revoked"), for: identity)
        try await coordinator.install(tokenTestResponse("unrelated"), for: unrelated)
        let revoking = Task { try await coordinator.revokeToken(for: identity) }
        while await gate.waiters == 0 { try Task.checkCancellation(); await Task.yield() }
        #expect(await coordinator.snapshot().mutations == 1)
        await #expect(throws: OAuthTokenFailure.operationInProgress) { try await coordinator.accessToken(for: identity) }
        await #expect(throws: OAuthTokenFailure.operationInProgress) { try await coordinator.revokeToken(for: identity) }
        #expect(try await coordinator.accessToken(for: unrelated).withUnsafeValue { $0 } == "unrelated")
        await gate.open()
        try await revoking.value
        #expect(await coordinator.snapshot().mutations == 0)
        await coordinator.close()
    }
}

/// Creates deterministic token responses without real credentials or transport work.
/// - Parameters:
///   - access: Synthetic nonempty bearer token.
///   - lifetime: Positive lifetime in seconds, default 100.
///   - refresh: Synthetic refresh token, default refresh-old; nil models nonrefreshable grants.
/// - Returns: A validated response with an identify scope.
/// - Throws: Credential or response validation errors for malformed test setup.
private func tokenTestResponse(_ access: String, lifetime: Int = 100, refresh: String? = "refresh-old") throws -> OAuthTokenResponse {
    try OAuthTokenResponse(accessToken: BearerToken(access), refreshToken: refresh.map { try OAuthRefreshToken($0) },
        expiresIn: lifetime, scopes: ["identify"])
}

/// Converts the explicitly advanced test clock's integer seconds into deterministic UTC.
/// - Parameter clock: Test-local virtual clock; all cases advance whole seconds.
/// - Returns: UTC time measured from the arbitrary Unix epoch test origin.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private func tokenTestDate(_ clock: ManualClock) -> Date {
    Date(timeIntervalSince1970: Double(clock.now.offset.components.seconds))
}

/// Safe synthetic exchange failure used to model an indeterminate network outcome.
private enum TokenTestFailure: Error { case ambiguous }

/// Test-only actor store implementing atomic generation replacement and bounded-depth publisher cascades.
private actor TokenTestStorage: OAuthTokenStorage {
    private var records: [OAuthTokenIdentity: OAuthStoredToken] = [:]

    /// Loads one actor-consistent synthetic record without network or disk I/O.
    /// - Parameter identity: Exact application/grant key.
    /// - Returns: Present synthetic record or nil.
    func load(for identity: OAuthTokenIdentity) async throws -> OAuthStoredToken? { records[identity] }

    /// Implements the production protocol transaction contract for deterministic race tests.
    /// - Parameters:
    ///   - identity: Exact record to replace or remove.
    ///   - expectedGeneration: Current record fence, including nil for absence.
    ///   - replacement: New synthetic secret or nil for atomic parent/child invalidation.
    ///   - now: Virtual UTC time for parent liveness.
    /// - Returns: True after atomic replacement; false without changes for stale or invalid writes.
    func compareExchange(for identity: OAuthTokenIdentity, expectedGeneration: UUID?,
                         replacement: OAuthStoredToken?, now: Date) async throws -> Bool {
        guard records[identity]?.generation == expectedGeneration else { return false }
        if let replacement {
            if let parent = replacement.parent {
                guard parent.authorizationID == identity.authorizationID,
                      parent.applicationID != identity.applicationID,
                      let ancestor = records[parent], ancestor.parent == nil,
                      ancestor.expiresAt > now, replacement.expiresAt <= ancestor.expiresAt,
                      replacement.refreshToken == nil else { return false }
            }
            records[identity] = replacement
        } else {
            records.removeValue(forKey: identity)
            for child in records.filter({ $0.value.parent == identity }).keys { records.removeValue(forKey: child) }
        }
        return true
    }
}

/// A safe failing adapter proving storage errors release all coordinator reservations.
private struct TokenTestFailingStorage: OAuthTokenStorage {
    /// Fails the synthetic read without exposing stored data.
    /// - Parameter identity: Ignored application/grant key.
    /// - Returns: Never returns a record.
    /// - Throws: The fixed synthetic ambiguous failure.
    func load(for identity: OAuthTokenIdentity) async throws -> OAuthStoredToken? { throw TokenTestFailure.ambiguous }

    /// Fails the synthetic transaction without changing state.
    /// - Parameters:
    ///   - identity: Ignored key.
    ///   - expectedGeneration: Ignored generation fence.
    ///   - replacement: Ignored proposed record.
    ///   - now: Ignored UTC instant.
    /// - Returns: Never returns a commit result.
    /// - Throws: The fixed synthetic ambiguous failure.
    func compareExchange(for identity: OAuthTokenIdentity, expectedGeneration: UUID?,
                         replacement: OAuthStoredToken?, now: Date) async throws -> Bool { throw TokenTestFailure.ambiguous }
}

/// Noncanceling gate deliberately models late server completion after local revocation.
private actor TokenTestGate {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private var opened = false

    /// Reports deterministic registration count so tests can order exchanges without sleeps.
    var waiters: Int { continuations.count }

    /// Suspends until opened, intentionally ignoring cancellation to exercise generation fences.
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    /// Permanently opens the gate and resumes each registered continuation exactly once.
    func open() {
        opened = true
        let current = continuations
        continuations.removeAll()
        for continuation in current { continuation.resume() }
    }
}

/// Actor-isolated count of physical exchanges for single-flight and no-replay assertions.
private actor TokenTestCounter {
    var value = 0
    /// Records one exchange start; concurrent callers remain serialized by the actor.
    func increment() { value += 1 }
}
