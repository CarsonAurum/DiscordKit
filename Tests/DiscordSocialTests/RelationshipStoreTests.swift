import DiscordCore
import Testing
@testable import DiscordSocial

/// Deterministic tests for authorized local social observations; no native SDK or network is used.
@Suite struct RelationshipStoreTests {
    private let scope = SocialScope(
        applicationID: ApplicationID(rawValue: 10), accountID: UserID(rawValue: 20), consentGeneration: 3
    )

    /// Creates a complete synthetic user with optional Unicode display data.
    /// - Parameters:
    ///   - id: Exact unsigned identifier, default one.
    ///   - username: Exact display username, default Alice.
    ///   - displayName: Optional display name; default absent.
    ///   - avatar: Optional avatar reference; default absent.
    ///   - presence: Complete trusted presence metadata; default unavailable.
    /// - Returns: Immutable normalized local-provider user.
    private func user(_ id: UInt64 = 1, _ username: String = "Alice",
                      displayName: String? = nil, avatar: String? = nil,
                      presence: SocialUserPresence? = nil) -> SocialUser {
        SocialUser(id: UserID(rawValue: id), username: username, displayName: displayName, avatar: avatar, presence: presence)
    }

    /// Creates one complete authorized baseline with adjustable ordering and payload.
    /// - Parameters:
    ///   - generation: Provider generation, default one.
    ///   - sequence: Last included sequence, default ten.
    ///   - users: Full users; default is a single Alice record.
    ///   - relationships: Full relationships; default is Alice as a friend.
    /// - Returns: Complete synthetic snapshot in the fixture consent scope.
    private func snapshot(generation: UInt64 = 1, sequence: UInt64 = 10,
                          users: [SocialUser]? = nil, relationships: [SocialRelationship]? = nil) -> SocialStateSnapshot {
        SocialStateSnapshot(
            scope: scope, generation: generation, sequence: sequence,
            users: users ?? [user()],
            relationships: relationships ?? [.init(userID: UserID(rawValue: 1), kind: .friend)]
        )
    }

    /// Wraps an exact-scope ordered synthetic change.
    /// - Parameters:
    ///   - sequence: Explicit sequence after the fixture baseline.
    ///   - change: Complete local-provider mutation.
    ///   - generation: Connection generation, default one.
    /// - Returns: Immutable event in the fixture scope.
    private func event(_ sequence: UInt64, _ change: SocialStateChange,
                       generation: UInt64 = 1) -> SocialStateEvent {
        SocialStateEvent(scope: scope, generation: generation, sequence: sequence, change: change)
    }

    /// Creates an activated store with selected tiny limits and optional complete baseline.
    /// - Parameters:
    ///   - maximumUsers: Positive user budget, default sixteen.
    ///   - maximumRelationships: Positive relationship budget, default sixteen.
    ///   - maximumUserStringBytes: Positive per-user byte budget, default 128.
    ///   - maximumTotalStringBytes: Positive aggregate string budget, default 1,024.
    ///   - seeded: Whether to install the fixture baseline; defaults to true.
    /// - Returns: Inert actor with deterministic synthetic state.
    /// - Throws: Any limit, activation, or fixture snapshot validation failure.
    private func store(maximumUsers: Int = 16, maximumRelationships: Int = 16,
                       maximumUserStringBytes: Int = 128, maximumTotalStringBytes: Int = 1_024,
                       seeded: Bool = true) async throws -> SocialRelationshipStore {
        let store = SocialRelationshipStore(limits: try SocialStateLimits(
            maximumUsers: maximumUsers, maximumRelationships: maximumRelationships,
            maximumUserStringBytes: maximumUserStringBytes, maximumTotalStringBytes: maximumTotalStringBytes
        ))
        try await store.activate(scope: scope)
        if seeded { _ = try await store.apply(snapshot: snapshot()) }
        return store
    }

    /// Each independent budget rejects zero/negative values, while maximal integer limits are overflow-safe.
    @Test func limitValidation() throws {
        #expect(throws: SocialStateError.invalidLimits) { try SocialStateLimits(maximumUsers: 0) }
        #expect(throws: SocialStateError.invalidLimits) { try SocialStateLimits(maximumRelationships: -1) }
        #expect(throws: SocialStateError.invalidLimits) { try SocialStateLimits(maximumUserStringBytes: 0) }
        #expect(throws: SocialStateError.invalidLimits) { try SocialStateLimits(maximumTotalStringBytes: -1) }
        let defaults = try SocialStateLimits()
        #expect(defaults.maximumUsers == 4_096)
        #expect(defaults.maximumRelationships == 4_096)
        #expect(defaults.maximumUserStringBytes == 4_096)
        #expect(defaults.maximumTotalStringBytes == 4_194_304)
        let largest = try SocialStateLimits(maximumUsers: .max, maximumRelationships: .max,
                                           maximumUserStringBytes: .max, maximumTotalStringBytes: .max)
        #expect(largest.maximumTotalStringBytes == .max)
    }

    /// Construction starts inactive; activation requires a baseline and clear revokes even delayed callbacks.
    @Test func activationAndClearAreExplicit() async throws {
        let store = SocialRelationshipStore(limits: try SocialStateLimits())
        let initial = await store.view()
        #expect(initial.scope == nil)
        #expect(initial.generation == nil && initial.sequence == nil)
        #expect(initial.synchronization == .inactive)
        #expect(initial.users.isEmpty && initial.relationships.isEmpty)
        await #expect(throws: SocialStateError.scopeMismatch) { try await store.apply(snapshot: snapshot()) }
        try await store.activate(scope: scope)
        #expect(await store.view().synchronization == .needsSnapshot)
        #expect(try await store.apply(snapshot: snapshot()) == .applied)
        try await store.activate(scope: scope)
        #expect(await store.view().users.isEmpty)
        #expect(await store.view().generation == nil)
        _ = try await store.apply(snapshot: snapshot())
        await store.clear()
        await store.clear()
        #expect(await store.view() == initial)
        await #expect(throws: SocialStateError.scopeMismatch) {
            try await store.apply(event: event(11, .removeUser(UserID(rawValue: 1))))
        }
    }

    /// Application, account, and consent generations each isolate stale providers without clearing active state.
    @Test func scopesAndIdentifierAdmission() async throws {
        let store = try await store()
        let original = await store.view()
        let mismatches = [
            SocialScope(applicationID: ApplicationID(rawValue: 11), accountID: scope.accountID, consentGeneration: 3),
            SocialScope(applicationID: scope.applicationID, accountID: UserID(rawValue: 21), consentGeneration: 3),
            SocialScope(applicationID: scope.applicationID, accountID: scope.accountID, consentGeneration: 4)
        ]
        for mismatch in mismatches {
            await #expect(throws: SocialStateError.scopeMismatch) {
                try await store.apply(snapshot: SocialStateSnapshot(
                    scope: mismatch, generation: 99, sequence: 99, users: [], relationships: []
                ))
            }
            await #expect(throws: SocialStateError.scopeMismatch) {
                try await store.apply(event: SocialStateEvent(
                    scope: mismatch, generation: 99, sequence: 99, change: .removeUser(UserID(rawValue: 1))
                ))
            }
            #expect(await store.view() == original)
        }
        for badScope in [
            SocialScope(applicationID: ApplicationID(rawValue: 0), accountID: scope.accountID, consentGeneration: 3),
            SocialScope(applicationID: scope.applicationID, accountID: UserID(rawValue: 0), consentGeneration: 3)
        ] {
            await #expect(throws: SocialStateError.invalidIdentifier) { try await store.activate(scope: badScope) }
            #expect(await store.view() == original)
        }
        try await store.activate(scope: mismatches[1])
        #expect(await store.view().users.isEmpty)
        #expect(await store.view().scope == mismatches[1])
        await #expect(throws: SocialStateError.scopeMismatch) { try await store.apply(snapshot: snapshot()) }
    }

    /// Complete snapshots sort full-width IDs, preserve display data and unknown kinds, and enable exact local groups.
    @Test func deterministicQueriesAndGroups() async throws {
        let store = try await store(seeded: false)
        let people = [user(.max, "ALICE"), user(2, "blocked"), user(1, "Alice", displayName: "Álice", avatar: "asset:1"),
                      user(7, "incoming"), user(9, "outgoing"), user(8, "other"), user(6, "uncategorized")]
        let relationships: [SocialRelationship] = [
            .init(userID: UserID(rawValue: .max), kind: .friend),
            .init(userID: UserID(rawValue: 9), kind: .outgoingRequest),
            .init(userID: UserID(rawValue: 2), kind: .blocked),
            .init(userID: UserID(rawValue: 8), kind: .unknown(777)),
            .init(userID: UserID(rawValue: 7), kind: .incomingRequest),
            .init(userID: UserID(rawValue: 1), kind: .friend)
        ]
        #expect(try await store.apply(snapshot: snapshot(users: people, relationships: relationships)) == .applied)
        let view = await store.view()
        #expect(view.users.map(\.id.rawValue) == [1, 2, 6, 7, 8, 9, .max])
        #expect(view.relationships.map(\.userID.rawValue) == [1, 2, 7, 8, 9, .max])
        #expect(view.user(for: UserID(rawValue: 1)) == people[2])
        #expect(view.user(for: UserID(rawValue: 77)) == nil)
        #expect(view.relationship(for: UserID(rawValue: 8))?.kind == .unknown(777))
        #expect(view.relationship(for: UserID(rawValue: 6)) == nil)
        #expect(view.users(in: .blocked).map(\.username) == ["blocked"])
        #expect(view.users(in: .incomingRequest).map(\.username) == ["incoming"])
        #expect(view.users(in: .outgoingRequest).map(\.username) == ["outgoing"])
        #expect(view.users(in: .unknown(777)).map(\.username) == ["other"])
        #expect(view.users(in: .unknown(778)).isEmpty)
        #expect(view.friends(matchingUsername: "LiC").map(\.id.rawValue) == [1, .max])
        #expect(view.friends(matchingUsername: "").count == 2)
        #expect(view.friends(matchingUsername: "incoming").isEmpty)
    }

    /// Duplicate and older order metadata is ignored before parsing malformed payloads; empty replacement is valid.
    @Test func staleSnapshotsAndEventsAreNoOps() async throws {
        let store = try await store()
        let original = await store.view()
        for candidate in [snapshot(generation: 0, sequence: .max, users: [user(0)]),
                          snapshot(sequence: 9, users: [user(0)]), snapshot(users: [user(0)])] {
            #expect(try await store.apply(snapshot: candidate) == .ignoredStale)
            #expect(await store.view() == original)
        }
        for candidate in [event(.max, .removeUser(UserID(rawValue: 0)), generation: 0),
                          event(9, .removeUser(UserID(rawValue: 0))), event(10, .removeUser(UserID(rawValue: 0)))] {
            #expect(try await store.apply(event: candidate) == .ignoredStale)
            #expect(await store.view() == original)
        }
        #expect(try await store.apply(snapshot: snapshot(sequence: 11, users: [], relationships: [])) == .applied)
        #expect(await store.view().synchronization == .synchronized)
        #expect(await store.view().users.isEmpty)
        #expect(try await store.apply(snapshot: snapshot(generation: 2, sequence: 0)) == .applied)
        let replaced = await store.view()
        #expect(replaced.generation == 2 && replaced.sequence == 0)
    }

    /// Missing baseline, gaps, and new generations erase display data until an equal-or-newer complete snapshot arrives.
    @Test func gapsAndGenerationChangesRequireSnapshot() async throws {
        let store = try await store(seeded: false)
        #expect(try await store.apply(event: event(4, .upsertUser(user()))) == .requiresSnapshot)
        #expect(await store.view().generation == 1)
        #expect(await store.view().sequence == 4)
        #expect(await store.view().users.isEmpty)
        #expect(try await store.apply(snapshot: snapshot(sequence: 3)) == .ignoredStale)
        #expect(try await store.apply(snapshot: snapshot(sequence: 4)) == .applied)
        #expect(try await store.apply(event: event(6, .removeUser(UserID(rawValue: 1)))) == .requiresSnapshot)
        #expect(await store.view().synchronization == .needsSnapshot)
        #expect(await store.view().relationships.isEmpty)
        #expect(try await store.apply(event: event(7, .upsertUser(user()))) == .requiresSnapshot)
        #expect(try await store.apply(snapshot: snapshot(sequence: 6)) == .ignoredStale)
        #expect(try await store.apply(snapshot: snapshot(sequence: 7)) == .applied)
        #expect(try await store.apply(event: event(0, .removeUser(UserID(rawValue: 1)), generation: 2)) == .requiresSnapshot)
        #expect(await store.view().generation == 2)
        #expect(await store.view().users.isEmpty)
        #expect(try await store.apply(snapshot: snapshot(generation: 1, sequence: .max)) == .ignoredStale)
        #expect(try await store.apply(snapshot: snapshot(generation: 2, sequence: 0)) == .applied)
        #expect(try await store.apply(event: event(1, .removeRelationship(UserID(rawValue: 1)), generation: 2)) == .applied)
        #expect(await store.view().users.count == 1)
        #expect(await store.view().relationships.isEmpty)
    }

    /// Sequence exhaustion cannot wrap and a higher connection generation safely establishes a new domain.
    @Test func unsignedSequenceExhaustion() async throws {
        let store = try await store(seeded: false)
        _ = try await store.apply(snapshot: snapshot(generation: .max - 1, sequence: .max - 1))
        #expect(try await store.apply(event: event(.max, .upsertUser(user(1, "last")), generation: .max - 1)) == .applied)
        #expect(try await store.apply(event: event(0, .upsertUser(user(1, "wrapped")), generation: .max - 1)) == .ignoredStale)
        #expect(await store.view().users.first?.username == "last")
        #expect(try await store.apply(snapshot: snapshot(generation: .max, sequence: 0)) == .applied)
        #expect(await store.view().sequence == 0)
    }

    /// Invalid complete baselines reject duplicate IDs, zero IDs and dangling references atomically.
    @Test func malformedSnapshotsPreservePriorState() async throws {
        let store = try await store()
        let original = await store.view()
        let invalid: [(SocialStateSnapshot, SocialStateError)] = [
            (snapshot(sequence: 11, users: [user(), user()]), .duplicateIdentifier),
            (snapshot(sequence: 11, relationships: [.init(userID: UserID(rawValue: 1), kind: .friend),
                                                   .init(userID: UserID(rawValue: 1), kind: .blocked)]), .duplicateIdentifier),
            (snapshot(sequence: 11, users: [user(0)], relationships: []), .invalidIdentifier),
            (snapshot(sequence: 11, relationships: [.init(userID: UserID(rawValue: 0), kind: .friend)]), .invalidIdentifier),
            (snapshot(sequence: 11, relationships: [.init(userID: UserID(rawValue: 2), kind: .friend)]), .missingUser)
        ]
        for (candidate, error) in invalid {
            await #expect(throws: error) { try await store.apply(snapshot: candidate) }
            #expect(await store.view() == original)
        }
    }

    /// Every resident count and string budget rejects excess; failures erase old observations and retain recovery order.
    @Test func snapshotCapacityAndUTF8Boundaries() async throws {
        let cases: [(SocialRelationshipStore, SocialStateSnapshot)] = [
            (try await store(maximumUsers: 1), snapshot(sequence: 11, users: [user(), user(2)])),
            (try await store(maximumRelationships: 1), snapshot(sequence: 11, users: [user(), user(2)], relationships: [
                .init(userID: UserID(rawValue: 1), kind: .friend), .init(userID: UserID(rawValue: 2), kind: .blocked)
            ])),
            (try await store(maximumUserStringBytes: 5), snapshot(sequence: 11, users: [user(1, "ééé")])),
            (try await store(maximumTotalStringBytes: 5), snapshot(sequence: 11, users: [user(1, "a"), user(2, "12345")]))
        ]
        for (store, candidate) in cases {
            await #expect(throws: SocialStateError.capacityExceeded) { try await store.apply(snapshot: candidate) }
            let view = await store.view()
            #expect(view.synchronization == .needsSnapshot)
            #expect(view.users.isEmpty && view.relationships.isEmpty)
            #expect(view.sequence == 11)
            #expect(try await store.apply(snapshot: snapshot()) == .ignoredStale)
            #expect(try await store.apply(snapshot: snapshot(sequence: 11)) == .applied)
        }
        let exact = try await store(maximumUserStringBytes: 6, maximumTotalStringBytes: 6, seeded: false)
        let unicode = user(1, "é", displayName: "é", avatar: "é")
        #expect(try await exact.apply(snapshot: snapshot(users: [unicode])) == .applied)
        #expect(await exact.view().users == [unicode])
    }

    /// All four event cases preserve referential integrity, allow idempotent removal, and release byte/count budgets.
    @Test func orderedMutationsAndBudgetRelease() async throws {
        let store = try await store(maximumUsers: 2, maximumRelationships: 1,
                                    maximumUserStringBytes: 5, maximumTotalStringBytes: 6)
        #expect(try await store.apply(event: event(11, .upsertUser(user(1, "x")))) == .applied)
        #expect(try await store.apply(event: event(12, .upsertUser(user(2, "12345")))) == .applied)
        #expect(try await store.apply(event: event(13, .removeRelationship(UserID(rawValue: 1)))) == .applied)
        #expect(try await store.apply(event: event(14, .upsertRelationship(.init(userID: UserID(rawValue: 2), kind: .incomingRequest)))) == .applied)
        #expect(try await store.apply(event: event(15, .upsertRelationship(.init(userID: UserID(rawValue: 2), kind: .friend)))) == .applied)
        #expect(await store.view().users(in: .friend).map(\.id.rawValue) == [2])
        #expect(try await store.apply(event: event(16, .removeUser(UserID(rawValue: 2)))) == .applied)
        #expect(await store.view().relationships.isEmpty)
        #expect(try await store.apply(event: event(17, .removeUser(UserID(rawValue: 2)))) == .applied)
        #expect(try await store.apply(event: event(18, .removeRelationship(UserID(rawValue: 2)))) == .applied)
        #expect(try await store.apply(event: event(19, .upsertUser(user(3, "12345")))) == .applied)
        #expect(await store.view().users.map(\.username) == ["x", "12345"])
    }

    /// An invalid contiguous mutation cannot be skipped while claiming synchronized state; equal watermark snapshot recovers.
    @Test func malformedEventsRequireResynchronization() async throws {
        let invalid: [(SocialStateChange, SocialStateError)] = [
            (.upsertUser(user(0)), .invalidIdentifier),
            (.removeUser(UserID(rawValue: 0)), .invalidIdentifier),
            (.upsertRelationship(.init(userID: UserID(rawValue: 0), kind: .blocked)), .invalidIdentifier),
            (.upsertRelationship(.init(userID: UserID(rawValue: 2), kind: .friend)), .missingUser),
            (.removeRelationship(UserID(rawValue: 0)), .invalidIdentifier)
        ]
        for (change, error) in invalid {
            let store = try await store()
            await #expect(throws: error) { try await store.apply(event: event(11, change)) }
            #expect(await store.view().synchronization == .needsSnapshot)
            #expect(await store.view().users.isEmpty)
            #expect(await store.view().sequence == 11)
            #expect(try await store.apply(snapshot: snapshot(sequence: 11)) == .applied)
        }
    }

    /// Event admission accounts for user count, relationship count, replacement byte growth, and multi-user byte growth.
    @Test func eventCapacityFailsClosed() async throws {
        let cases: [(SocialRelationshipStore, SocialStateChange)] = [
            (try await store(maximumUsers: 1), .upsertUser(user(2))),
            (try await store(maximumUserStringBytes: 5), .upsertUser(user(1, "123456"))),
            (try await store(maximumTotalStringBytes: 5), .upsertUser(user(1, "123456"))),
            (try await store(maximumTotalStringBytes: 5), .upsertUser(user(2, "x")))
        ]
        for (store, change) in cases {
            await #expect(throws: SocialStateError.capacityExceeded) { try await store.apply(event: event(11, change)) }
            #expect(await store.view().synchronization == .needsSnapshot)
            #expect(await store.view().users.isEmpty)
        }
        let store = try await store(maximumRelationships: 1)
        _ = try await store.apply(event: event(11, .upsertUser(user(2))))
        await #expect(throws: SocialStateError.capacityExceeded) {
            try await store.apply(event: event(12, .upsertRelationship(.init(userID: UserID(rawValue: 2), kind: .friend))))
        }
        #expect(await store.view().relationships.isEmpty)
    }

    /// Concurrent duplicate callbacks serialize atomically with one successful application and bounded immutable reads.
    @Test func concurrentDuplicateAdmission() async throws {
        let store = try await store()
        let candidate = event(11, .upsertUser(user(1, "updated")))
        let outcomes = try await withThrowingTaskGroup(of: SocialApplyOutcome.self) { group in
            for _ in 0..<32 { group.addTask { try await store.apply(event: candidate) } }
            var results: [SocialApplyOutcome] = []
            for try await result in group { results.append(result) }
            return results
        }
        #expect(outcomes.filter { $0 == .applied }.count == 1)
        #expect(outcomes.filter { $0 == .ignoredStale }.count == 31)
        #expect(await store.view().users == [user(1, "updated")])
        #expect(await store.view().sequence == 11)
    }

    /// Presence groups partition relationships by exact game/availability and prioritize known prior players elsewhere.
    @Test func localPresenceGroupsAndOrdering() async throws {
        let store = try await store(seeded: false)
        let people = [
            user(9, presence: .init(status: .online, hasPlayedScopedApplication: true)),
            user(3, presence: .init(status: .online, playingApplicationID: ApplicationID(rawValue: .max))),
            user(1, presence: .init(status: .online, playingApplicationID: scope.applicationID)),
            user(2, presence: .init(status: .idle, playingApplicationID: scope.applicationID)),
            user(4, presence: .init(status: .doNotDisturb, playingApplicationID: scope.applicationID)),
            user(5, presence: .init(status: .offline, playingApplicationID: scope.applicationID)),
            user(6, presence: .init(status: .unknown(Int.max), playingApplicationID: scope.applicationID)),
            user(7), user(8, presence: .init(status: .idle, hasPlayedScopedApplication: true)),
            user(10, presence: .init(status: .online, playingApplicationID: scope.applicationID)),
            user(11, presence: .init(status: .doNotDisturb))
        ]
        let relations = people.filter { $0.id.rawValue != 10 }.map {
            SocialRelationship(userID: $0.id, kind: $0.id.rawValue == 2 ? .blocked : .friend)
        }
        _ = try await store.apply(snapshot: snapshot(users: people, relationships: relations))
        let view = await store.view()
        #expect(view.relationships(inPresenceGroup: .onlinePlayingGame).map(\.userID.rawValue) == [1, 2, 4])
        #expect(view.relationships(inPresenceGroup: .onlineElsewhere).map(\.userID.rawValue) == [8, 9, 3, 11])
        #expect(view.relationships(inPresenceGroup: .offline).map(\.userID.rawValue) == [5])
        #expect(view.relationships(inPresenceGroup: .unknown).map(\.userID.rawValue) == [6, 7])
        for group in [SocialPresenceGroup.onlinePlayingGame, .onlineElsewhere, .offline, .unknown] {
            #expect(view.users(inPresenceGroup: group).map(\.id) == view.relationships(inPresenceGroup: group).map(\.userID))
        }
        #expect(view.users(in: .blocked).map(\.id.rawValue) == [2])
        #expect(view.users(inPresenceGroup: .onlinePlayingGame).allSatisfy { $0.id.rawValue != 10 })
    }

    /// Complete user replacement clears stale presence, and fixed-size presence does not spend display-string budgets.
    @Test func presenceReplacementAndRemoval() async throws {
        let store = try await store(maximumUserStringBytes: 5, maximumTotalStringBytes: 5)
        #expect(await store.view().users(inPresenceGroup: .unknown).map(\.id.rawValue) == [1])
        _ = try await store.apply(event: event(11, .upsertUser(user(presence:
            .init(status: .online, playingApplicationID: scope.applicationID, hasPlayedScopedApplication: true)))))
        #expect(await store.view().users(inPresenceGroup: .onlinePlayingGame).map(\.id.rawValue) == [1])
        _ = try await store.apply(event: event(12, .upsertUser(user(presence:
            .init(status: .offline, playingApplicationID: scope.applicationID)))))
        #expect(await store.view().users(inPresenceGroup: .offline).map(\.id.rawValue) == [1])
        #expect(await store.view().users(inPresenceGroup: .onlinePlayingGame).isEmpty)
        _ = try await store.apply(event: event(13, .upsertUser(user())))
        #expect(await store.view().users(inPresenceGroup: .unknown).map(\.id.rawValue) == [1])
        #expect(await store.view().users.first?.presence == nil)
        _ = try await store.apply(event: event(14, .removeUser(UserID(rawValue: 1))))
        for group in [SocialPresenceGroup.onlinePlayingGame, .onlineElsewhere, .offline, .unknown] {
            #expect(await store.view().users(inPresenceGroup: group).isEmpty)
        }
    }

    /// Account/consent/application switches erase presence and never classify another application's activity as the current game.
    @Test func presenceGroupingUsesExactScope() async throws {
        let store = try await store(seeded: false)
        let present = user(presence: .init(status: .online, playingApplicationID: scope.applicationID))
        _ = try await store.apply(snapshot: snapshot(users: [present]))
        #expect(await store.view().users(inPresenceGroup: .onlinePlayingGame) == [present])
        let other = SocialScope(applicationID: ApplicationID(rawValue: .max), accountID: scope.accountID, consentGeneration: 4)
        let oldView = await store.view()
        await #expect(throws: SocialStateError.scopeMismatch) {
            try await store.apply(snapshot: SocialStateSnapshot(scope: other, generation: 1, sequence: 1,
                                                               users: [present], relationships: []))
        }
        #expect(await store.view() == oldView)
        try await store.activate(scope: other)
        #expect(await store.view().users(inPresenceGroup: .onlinePlayingGame).isEmpty)
        _ = try await store.apply(snapshot: SocialStateSnapshot(scope: other, generation: 1, sequence: 1,
            users: [present], relationships: [.init(userID: present.id, kind: .friend)]))
        #expect(await store.view().users(inPresenceGroup: .onlinePlayingGame).isEmpty)
        #expect(await store.view().users(inPresenceGroup: .onlineElsewhere) == [present])
        await store.clear()
        #expect(await store.view().relationships(inPresenceGroup: .onlineElsewhere).isEmpty)
    }

    /// Zero application activity IDs reject admission atomically, and invalid event metadata requires a new complete baseline.
    @Test func presenceMetadataAdmission() async throws {
        let store = try await store()
        let invalid = user(presence: .init(status: .online, playingApplicationID: ApplicationID(rawValue: 0)))
        let before = await store.view()
        await #expect(throws: SocialStateError.invalidIdentifier) {
            try await store.apply(snapshot: snapshot(sequence: 11, users: [invalid]))
        }
        #expect(await store.view() == before)
        await #expect(throws: SocialStateError.invalidIdentifier) {
            try await store.apply(event: event(11, .upsertUser(invalid)))
        }
        #expect(await store.view().synchronization == .needsSnapshot)
        #expect(await store.view().users(inPresenceGroup: .unknown).isEmpty)
        _ = try await store.apply(snapshot: snapshot(sequence: 11))
        #expect(await store.view().users(inPresenceGroup: .unknown).map(\.id.rawValue) == [1])
    }

    /// Normal/debug formatting and reflection hide account scope, display fields, relationships and provider mutations.
    @Test func socialObservationDiagnosticsAreRedacted() async throws {
        let store = try await store()
        let change = SocialStateChange.removeUser(UserID(rawValue: 1))
        let values: [any CustomStringConvertible & CustomDebugStringConvertible & CustomReflectable] = [
            scope, user(1, "display_secret"), SocialRelationship(userID: UserID(rawValue: 1), kind: .friend),
            snapshot(), change, event(11, change), await store.view(),
            SocialUserPresence(status: .online, playingApplicationID: scope.applicationID, hasPlayedScopedApplication: true)
        ]
        for value in values {
            #expect(value.description.hasSuffix("(redacted)"))
            #expect(value.debugDescription == value.description)
            #expect(!String(reflecting: value).contains("display_secret"))
            #expect(value.customMirror.children.count == 1)
        }
    }
}
