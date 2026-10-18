import DiscordCore
import DiscordModels
import DiscordSocial
import DiscordTransport
import DiscordTestSupport
import Foundation
import Testing

/// Deterministic consent, provider admission and revocation tests; no Discord or host I/O.
@Suite("Social client", .timeLimit(.minutes(1)))
struct SocialClientTests {
    /// Bounds common presence fields by UTF-8 and conceals all display strings from diagnostics.
    @Test func presenceAndConfigurationBounds() throws {
        let presence = try SocialPresence(name: "private-name", details: "private-detail", state: "private-state")
        #expect(presence.name == "private-name")
        #expect(presence.details == "private-detail")
        #expect(presence.state == "private-state")
        #expect(!String(reflecting: presence).contains("private-name"))
        #expect(!String(describing: presence.customMirror).contains("private-detail"))
        _ = try SocialPresence(name: String(repeating: "a", count: 128), details: "", state: "")
        for name in ["", String(repeating: "é", count: 65)] {
            #expect(throws: SocialFailure.invalidConfiguration) { try SocialPresence(name: name) }
        }
        #expect(throws: SocialFailure.invalidConfiguration) {
            try SocialPresence(name: "x", details: String(repeating: "x", count: 129))
        }
        #expect(throws: SocialFailure.invalidConfiguration) {
            try SocialPresence(name: "x", state: String(repeating: "x", count: 129))
        }
        for cap in [0, 4097] {
            #expect(throws: SocialFailure.invalidConfiguration) {
                try SocialClient(clock: ContinuousClock(), stateLimits: SocialStateLimits(), maximumOperations: cap)
            }
        }
    }

    /// Capability reports require explicit user authorization, exact scopes and qualified hosts.
    @Test func capabilityAndLifecycle() async throws {
        let client = try SocialClient(clock: ContinuousClock(), profile: ProfileStub(body: { _ in try user() }),
            presence: PresenceStub(body: { _, _ in }), stateLimits: SocialStateLimits())
        #expect(await client.availability(for: .profile) == .unauthorized)
        await #expect(throws: SocialFailure.unauthorized) { try await client.currentProfile() }
        try await client.activate(scope: scope(), grantedScopes: [])
        #expect(await client.availability(for: .profile) == .missingScope)
        #expect(await client.availability(for: .presence) == .unavailableHost)
        try await client.activate(scope: scope(), grantedScopes: ["identify"], availableHosts: [.desktopRPC])
        #expect(await client.availability(for: .presence) == .missingScope)
        try await client.activate(scope: scope(), grantedScopes: ["identify", "rpc.activities.write"],
            availableHosts: [.desktopRPC])
        #expect(await client.availability(for: .profile) == .available)
        #expect(await client.availability(for: .presence) == .available)
        #expect(try await client.currentProfile().id == UserID(rawValue: 2))
        try await client.updatePresence(SocialPresence(name: "x"))
        #expect(await client.snapshot().inFlightOperations == 0)
        await client.disconnect()
        #expect(await client.snapshot().authorized == false)
        #expect(try await client.relationshipView().users.isEmpty)
        await client.close(); await client.close()
        #expect(await client.availability(for: .relationshipState) == .closed)
        await #expect(throws: SocialFailure.closed) { try await client.activate(scope: scope(), grantedScopes: []) }
        await #expect(throws: SocialFailure.closed) { try await client.currentProfile() }
        let absent = try SocialClient(clock: ContinuousClock(), stateLimits: SocialStateLimits())
        try await absent.activate(scope: scope(), grantedScopes: [])
        #expect(await absent.availability(for: .profile) == .missingProvider)
        #expect(await absent.availability(for: .presence) == .missingProvider)
        await #expect(throws: SocialFailure.missingProvider) { try await absent.currentProfile() }
        await #expect(throws: SocialFailure.missingProvider) { try await absent.updatePresence(SocialPresence(name: "x")) }
    }

    /// Local observations are scoped, ordered and discarded on account/consent replacement.
    @Test func stateSynchronizationAndInvalidActivation() async throws {
        let client = try SocialClient(clock: ContinuousClock(), stateLimits: SocialStateLimits())
        for invalid in [scope(account: 0), SocialScope(applicationID: .init(rawValue: 0), accountID: .init(rawValue: 2), consentGeneration: 0)] {
            await #expect(throws: SocialFailure.invalidConfiguration) { try await client.activate(scope: invalid, grantedScopes: []) }
        }
        for invalid in [Set([""]), Set([String(repeating: "x", count: 129)]), Set((0..<129).map { "scope\($0)" })] {
            await #expect(throws: SocialFailure.invalidConfiguration) { try await client.activate(scope: scope(), grantedScopes: invalid) }
        }
        try await client.activate(scope: scope(), grantedScopes: [])
        let baseline = SocialStateSnapshot(scope: scope(), generation: 1, sequence: 1,
            users: [SocialUser(id: .init(rawValue: 3), username: "friend")],
            relationships: [SocialRelationship(userID: .init(rawValue: 3), kind: .friend)])
        #expect(try await client.synchronize(baseline) == .applied)
        #expect(try await client.relationshipView().users(in: .friend).count == 1)
        let event = SocialStateEvent(scope: scope(), generation: 1, sequence: 2, change: .removeUser(.init(rawValue: 3)))
        #expect(try await client.apply(event) == .applied)
        #expect(try await client.relationshipView().users.isEmpty)
        try await client.activate(scope: scope(account: 4), grantedScopes: [])
        await #expect(throws: SocialFailure.accountMismatch) { try await client.synchronize(baseline) }
        await #expect(throws: SocialFailure.accountMismatch) { try await client.apply(event) }
        await client.disconnect()
        await #expect(throws: SocialFailure.unauthorized) { try await client.synchronize(baseline) }
        #expect(try await client.relationshipView().scope == nil)
    }

    /// Profile identity mismatch is rejected and dependency text is sanitized; safe Discord errors survive.
    @Test func profileIdentityAndSafeErrors() async throws {
        let mismatch = try SocialClient(clock: ContinuousClock(), profile: ProfileStub(body: { _ in try user(id: 9) }),
            stateLimits: SocialStateLimits())
        try await mismatch.activate(scope: scope(), grantedScopes: ["identify"])
        await #expect(throws: SocialFailure.accountMismatch) { try await mismatch.currentProfile() }
        let unsafe = try SocialClient(clock: ContinuousClock(), profile: ProfileStub(body: { _ in throw UnsafeFailure() }),
            presence: PresenceStub(body: { _, _ in throw UnsafeFailure() }), stateLimits: SocialStateLimits())
        try await unsafe.activate(scope: scope(), grantedScopes: ["identify", "rpc.activities.write"], availableHosts: [.desktopRPC])
        await #expect(throws: SocialFailure.providerFailure) { try await unsafe.currentProfile() }
        await #expect(throws: SocialFailure.providerFailure) { try await unsafe.updatePresence(SocialPresence(name: "x")) }
        let safe = try SocialClient(clock: ContinuousClock(), profile: ProfileStub(body: { _ in throw DiscordError.api(status: 401, code: nil) }),
            presence: PresenceStub(body: { _, _ in throw DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission) }),
            stateLimits: SocialStateLimits())
        try await safe.activate(scope: scope(), grantedScopes: ["identify", "rpc.activities.write"], availableHosts: [.desktopRPC])
        await #expect(throws: DiscordError.api(status: 401, code: nil)) { try await safe.currentProfile() }
        await #expect(throws: DiscordError.unknownMutationOutcome(.connectionLostAfterSubmission)) {
            try await safe.updatePresence(SocialPresence(name: "x"))
        }
        #expect(await safe.snapshot().inFlightOperations == 0)
    }

    /// Aggregate admission stays reserved across revoke and rejects late results without identity leakage.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func boundedCallsAndStaleResults() async throws {
        let entered = TestBarrier(); let release = TestBarrier()
        let client = try SocialClient(clock: ContinuousClock(), profile: ProfileStub(body: { _ in
            entered.open(); try await release.wait(); return try user()
        }), stateLimits: SocialStateLimits(), maximumOperations: 1)
        try await client.activate(scope: scope(), grantedScopes: ["identify"])
        let first = Task { try await client.currentProfile() }
        try await entered.wait()
        #expect(await client.snapshot().inFlightOperations == 1)
        await #expect(throws: SocialFailure.overloaded) { try await client.currentProfile() }
        await client.disconnect()
        try await client.activate(scope: scope(account: 4), grantedScopes: ["identify"])
        await #expect(throws: SocialFailure.overloaded) { try await client.currentProfile() }
        release.open()
        await #expect(throws: SocialFailure.staleSession) { try await first.value }
        #expect(await client.snapshot().inFlightOperations == 0)
    }

    /// Presence writers never overlap, even when consent changes during a submitted mutation.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func presenceSerializationAndRevoke() async throws {
        let entered = TestBarrier(); let release = TestBarrier()
        let client = try SocialClient(clock: ContinuousClock(), presence: PresenceStub(body: { _, _ in
            entered.open(); try await release.wait()
        }), stateLimits: SocialStateLimits())
        try await client.activate(scope: scope(), grantedScopes: ["rpc.activities.write"], availableHosts: [.desktopRPC])
        let first = Task { try await client.updatePresence(SocialPresence(name: "x")) }
        try await entered.wait()
        await #expect(throws: SocialFailure.mutationInProgress) { try await client.updatePresence(SocialPresence(name: "y")) }
        await client.close()
        #expect(await client.snapshot().inFlightOperations == 1)
        release.open()
        await #expect(throws: SocialFailure.staleSession) { try await first.value }
        #expect(await client.snapshot().inFlightOperations == 0)
    }

    /// Pre-cancelled, in-flight cancelled and expired calls release admission; deadline races use virtual time.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func cancellationAndDeadline() async throws {
        let clock = ManualClock(); let entered = TestBarrier(); let never = TestBarrier()
        let client = try SocialClient(clock: clock, profile: ClockProfileStub(body: { _ in
            entered.open(); try await never.wait(); return try user()
        }), stateLimits: SocialStateLimits())
        try await client.activate(scope: scope(), grantedScopes: ["identify"])
        await #expect(throws: TransportFailure.deadlineExceeded) { try await client.currentProfile(deadline: clock.now) }
        let first = Task { try await client.currentProfile(deadline: clock.now.advanced(by: .seconds(1))) }
        try await entered.wait()
        while clock.pendingSleepCount == 0 { await Task.yield() }
        try clock.advance(by: .seconds(1))
        await #expect(throws: TransportFailure.deadlineExceeded) { try await first.value }
        #expect(await client.snapshot().inFlightOperations == 0)
        let cancelled = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await client.currentProfile() }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(clock.pendingSleepCount == 0)
        let presenceEntered = TestBarrier(); let presenceWait = TestBarrier()
        let writer = try SocialClient(clock: ContinuousClock(), presence: PresenceStub(body: { _, _ in
            presenceEntered.open(); try await presenceWait.wait()
        }), stateLimits: SocialStateLimits())
        try await writer.activate(scope: scope(), grantedScopes: ["rpc.activities.write"], availableHosts: [.desktopRPC])
        let pending = Task { try await writer.updatePresence(SocialPresence(name: "x")) }
        try await presenceEntered.wait(); pending.cancel()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(await writer.snapshot().inFlightOperations == 0)
    }
}

/// Constructs the fixed synthetic authorization domain, without credentials.
/// - Parameter account: Exact account ID, default 2; zero supports negative tests.
/// - Returns: Application 1/consent-generation 1 scope.
private func scope(account: UInt64 = 2) -> SocialScope {
    SocialScope(applicationID: .init(rawValue: 1), accountID: .init(rawValue: account), consentGeneration: 1)
}

/// Decodes a realistic user projection using exact numeric identifiers.
/// - Parameter id: Synthetic account ID, default 2.
/// - Returns: Parsed public user fields.
/// - Throws: Schema errors if the fixture ceases to match the implemented projection.
private func user(id: UInt64 = 2) throws -> User {
    try User(data: Data("{\"id\":\"\(id)\",\"username\":\"test\",\"discriminator\":\"0\",\"global_name\":null,\"avatar\":null}".utf8))
}

/// Injected closure reader used to assert common provider admission and identity behavior.
private struct ProfileStub: SocialProfileProvider {
    let body: @Sendable (TransportContext<ContinuousClock>) async throws -> User
    /// Requires the same identify scope as the public user-profile route.
    var profileRequirements: SocialProviderRequirements { .init(scopes: ["identify"]) }
    /// Executes the deterministic test body; errors and suspension are intentional fixture inputs.
    /// - Parameter context: Client deadline/cancellation context.
    /// - Returns: Synthetic user.
    /// - Throws: The test's configured failure.
    func currentProfile(context: TransportContext<ContinuousClock>) async throws -> User { try await body(context) }
}

/// Virtual-time reader that makes deadline cleanup observable without wall-clock sleeps.
@available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
private struct ClockProfileStub: SocialProfileProvider {
    let body: @Sendable (TransportContext<ManualClock>) async throws -> User
    /// Requires the exact consented profile scope.
    var profileRequirements: SocialProviderRequirements { .init(scopes: ["identify"]) }
    /// Runs an injected cancellation-aware gate under the manual clock.
    /// - Parameter context: Virtual monotonic context.
    /// - Returns: Synthetic user when released.
    /// - Throws: Fixture cancellation or configured failures.
    func currentProfile(context: TransportContext<ManualClock>) async throws -> User { try await body(context) }
}

/// Deterministic local writer with independently visible host/scope prerequisites.
private struct PresenceStub: SocialPresenceProvider {
    let body: @Sendable (SocialPresence, TransportContext<ContinuousClock>) async throws -> Void
    /// Requires a qualified desktop host and explicit approved write scope.
    var presenceRequirements: SocialProviderRequirements { .init(host: .desktopRPC, scopes: ["rpc.activities.write"]) }
    /// Runs the injected writer exactly once without retry or lifecycle ownership.
    /// - Parameters:
    ///   - presence: Common presence input.
    ///   - context: Client deadline/cancellation context.
    /// - Throws: Fixture-defined failure or cancellation.
    func updatePresence(_ presence: SocialPresence, context: TransportContext<ContinuousClock>) async throws {
        try await body(presence, context)
    }
}

/// Untrusted dependency error used to verify payload-safe error conversion.
private struct UnsafeFailure: Error, CustomStringConvertible {
    /// Deliberate secret sentinel that must never escape through the composition error.
    var description: String { "sentinel-provider-secret" }
}
