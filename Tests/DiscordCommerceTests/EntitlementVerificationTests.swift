import DiscordTestSupport
import DiscordLogging
import DiscordCore
import DiscordHTTP
import DiscordModels
import Foundation
import Testing
@testable import DiscordCommerce

/// Deterministic authoritative access, exact timestamp boundaries and consumable/purchase orchestration.
@Suite struct EntitlementVerificationTests {
    /// Baseline timestamp checked with exact seconds/nanoseconds and no wall-clock dependency.
    static let now = try! DiscordTimestamp(rawValue: "2026-10-17T12:00:00.000000001Z")

    /// Known user/guild grants match exact application/SKU/owner; mismatch, deletion and future origins fail closed.
    /// - Throws: Unexpected fixture/policy errors fail the test.
    @Test func identityAndOriginPolicy() throws {
        let policy = Self.policy()
        let entitlement = try Self.fixture()
        try policy.validate(entitlement, entitlementID: .init(rawValue: 1), now: Self.now)
        for override in [["id": JSONValue.string("9")], ["application_id": .string("9")],
                         ["sku_id": .string("9")], ["user_id": .string("9")]] {
            #expect(throws: EntitlementVerificationError.mismatchedGrant) {
                try policy.validate(Self.fixture(override), entitlementID: .init(rawValue: 1), now: Self.now)
            }
        }
        for override in [["deleted": JSONValue.bool(true)], ["type": try .number(.init(rawValue: "99"))],
                         ["type": try .number(.init(rawValue: "4"))]] {
            #expect(throws: EntitlementVerificationError.inactiveGrant) {
                try policy.validate(Self.fixture(override), entitlementID: .init(rawValue: 1), now: Self.now)
            }
        }
        let guild = EntitlementRequirement(applicationID: .init(rawValue: 2), skuID: .init(rawValue: 3), owner: .guild(.init(rawValue: 5)))
        try guild.validate(Self.fixture(["guild_id": .string("5")]), entitlementID: .init(rawValue: 1), now: Self.now)
        #expect(throws: EntitlementVerificationError.mismatchedGrant) {
            try policy.validate(Self.fixture(["guild_id": .string("5")]), entitlementID: .init(rawValue: 1), now: Self.now)
        }
        try policy.validate(Self.fixture(["guild_id": .null]), entitlementID: .init(rawValue: 1), now: Self.now)
        #expect(throws: EntitlementVerificationError.mismatchedGrant) {
            try guild.validate(entitlement, entitlementID: .init(rawValue: 1), now: Self.now)
        }
    }

    /// Start is inclusive/end exclusive to nanoseconds; missing dates require explicit test-mode policy and origin.
    /// - Throws: Unexpected fixture/policy setup fails the test.
    @Test func timestampAndTestPolicy() throws {
        let policy = Self.policy()
        for start in ["2026-10-17T12:00:00Z", Self.now.rawValue] {
            try policy.validate(Self.fixture(["starts_at": .string(start)]), entitlementID: .init(rawValue: 1), now: Self.now)
        }
        #expect(throws: EntitlementVerificationError.inactiveGrant) {
            try policy.validate(Self.fixture(["starts_at": .string("2026-10-17T12:00:00.000000002Z")]),
                entitlementID: .init(rawValue: 1), now: Self.now)
        }
        for end in ["2026-10-17T12:00:00Z", Self.now.rawValue] {
            #expect(throws: EntitlementVerificationError.inactiveGrant) {
                try policy.validate(Self.fixture(["ends_at": .string(end)]), entitlementID: .init(rawValue: 1), now: Self.now)
            }
        }
        try policy.validate(Self.fixture(["ends_at": .string("2026-10-17T12:00:00.000000002Z")]),
            entitlementID: .init(rawValue: 1), now: Self.now)
        let testPolicy = Self.policy(allowsTests: true)
        let missing = try Self.fixture(removing: ["starts_at", "ends_at"])
        #expect(throws: EntitlementVerificationError.inactiveGrant) { try policy.validate(missing, entitlementID: .init(rawValue: 1), now: Self.now) }
        #expect(throws: EntitlementVerificationError.inactiveGrant) { try testPolicy.validate(missing, entitlementID: .init(rawValue: 1), now: Self.now) }
        try testPolicy.validate(Self.fixture(["type": .number(.init(rawValue: "4"))], removing: ["starts_at", "ends_at"]),
            entitlementID: .init(rawValue: 1), now: Self.now)
    }

    /// Consumables require explicitly false consumption; absent and already consumed values never imply availability.
    /// - Throws: Unexpected fixture/policy failures fail the test.
    @Test func consumableAvailability() throws {
        let policy = Self.policy(consumable: true)
        try policy.validate(Self.fixture(), entitlementID: .init(rawValue: 1), now: Self.now)
        for entitlement in [try Self.fixture(["consumed": .bool(true)]), try Self.fixture(removing: ["consumed"])] {
            #expect(throws: EntitlementVerificationError.unavailableConsumable) {
                try policy.validate(entitlement, entitlementID: .init(rawValue: 1), now: Self.now)
            }
        }
    }

    /// Verification disables all read reuse and samples trusted time after the authoritative fetch completes.
    /// - Throws: Unexpected descriptor/verification errors fail the test.
    @Test func freshVerificationAndConsumption() async throws {
        let recorder = CommerceRecorder()
        let entitlement = try Self.fixture()
        let result = try await EntitlementVerification.consume(entitlementID: .init(rawValue: 1),
            requirement: Self.policy(consumable: true), now: { Self.now }, fetch: { endpoint in
                #expect(endpoint.path == ["applications", "2", "entitlements", "1"] && endpoint.readPolicy == nil)
                await recorder.record("fetch")
                return entitlement
            }, consume: { endpoint in
                #expect(endpoint.path == ["applications", "2", "entitlements", "1", "consume"])
                #expect(endpoint.retrySafety == .unsafe && endpoint.successStatuses == [204])
                await recorder.record("consume")
                return try endpoint.decode(Data())
            })
        #expect(result.id == entitlement.id)
        #expect(await recorder.events == ["fetch", "consume"])
        await #expect(throws: EntitlementVerificationError.consumptionNotRequested) {
            try await EntitlementVerification.consume(entitlementID: .init(rawValue: 1), requirement: Self.policy(),
                now: { Self.now }, fetch: { _ in Issue.record("must not fetch"); return entitlement },
                consume: { _ in Issue.record("must not consume"); return try EmptyResponse(data: Data()) })
        }
        await #expect(throws: CommerceFailure.failed) {
            try await EntitlementVerification.verify(entitlementID: .init(rawValue: 1), requirement: Self.policy(),
                now: { Self.now }, fetch: { _ in throw CommerceFailure.failed })
        }
    }

    /// A rejected verification or canceled fetch never reaches consumption; uncertain consume errors propagate without retry.
    /// - Throws: Unexpected fixture setup fails the test.
    @Test func failuresAndCancellation() async throws {
        let valid = try Self.fixture(), invalid = try Self.fixture(["deleted": .bool(true)])
        await #expect(throws: EntitlementVerificationError.inactiveGrant) {
            try await EntitlementVerification.consume(entitlementID: .init(rawValue: 1), requirement: Self.policy(consumable: true),
                now: { Self.now }, fetch: { _ in invalid }, consume: { _ in Issue.record("must not consume"); return try EmptyResponse(data: Data()) })
        }
        let canceled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await EntitlementVerification.verify(entitlementID: .init(rawValue: 1), requirement: Self.policy(),
                now: { Self.now }, fetch: { _ in Issue.record("must not fetch"); return valid })
        }
        await #expect(throws: CancellationError.self) { try await canceled.value }
        let during = Task {
            try await EntitlementVerification.consume(entitlementID: .init(rawValue: 1), requirement: Self.policy(consumable: true),
                now: { Self.now }, fetch: { _ in withUnsafeCurrentTask { $0?.cancel() }; return valid },
                consume: { _ in Issue.record("must not consume"); return try EmptyResponse(data: Data()) })
        }
        await #expect(throws: CancellationError.self) { try await during.value }
        let recorder = CommerceRecorder()
        await #expect(throws: CommerceFailure.failed) {
            try await EntitlementVerification.consume(entitlementID: .init(rawValue: 1), requirement: Self.policy(consumable: true),
                now: { Self.now }, fetch: { _ in valid }, consume: { _ in await recorder.record("consume"); throw CommerceFailure.failed })
        }
        #expect(await recorder.events == ["consume"])
    }

    /// Host receipts are hints: no acknowledgement stays nil; exact IDs are independently fetched and checked on the backend.
    /// - Throws: Unexpected fixture/purchase failures fail the test.
    @Test func activityPurchaseVerification() async throws {
        let entitlement = try Self.fixture()
        let noResult = try await ActivityPurchasing.purchase(requirement: Self.policy(), now: { Self.now },
            startPurchase: { sku in #expect(sku == SKUID(rawValue: 3)); return nil },
            fetch: { _ in Issue.record("must not fetch"); return entitlement })
        #expect(noResult == nil)
        let empty = try await ActivityPurchasing.purchase(requirement: Self.policy(), now: { Self.now },
            startPurchase: { _ in [] }, fetch: { _ in Issue.record("must not fetch"); return entitlement })
        #expect(empty?.isEmpty == true)
        let verified = try await ActivityPurchasing.purchase(requirement: Self.policy(), now: { Self.now },
            startPurchase: { _ in [.init(rawValue: 1)] }, fetch: { endpoint in
                #expect(endpoint.readPolicy == nil); return entitlement
            })
        #expect(verified?.map(\.id) == [EntitlementID(rawValue: 1)])
        let canceled = Task {
            try await ActivityPurchasing.purchase(requirement: Self.policy(), now: { Self.now }, startPurchase: { _ in
                withUnsafeCurrentTask { $0?.cancel() }; return nil
            }, fetch: { _ in Issue.record("must not fetch"); return entitlement })
        }
        await #expect(throws: CancellationError.self) { try await canceled.value }
        for ids in [[EntitlementID(rawValue: 1), .init(rawValue: 1)], (1...101).map { EntitlementID(rawValue: UInt64($0)) }] {
            await #expect(throws: EntitlementVerificationError.invalidPurchaseAcknowledgement) {
                try await ActivityPurchasing.purchase(requirement: Self.policy(), now: { Self.now },
                    startPurchase: { _ in ids }, fetch: { _ in Issue.record("must not fetch"); return entitlement })
            }
        }
        await #expect(throws: EntitlementVerificationError.mismatchedGrant) {
            try await ActivityPurchasing.purchase(requirement: Self.policy(), now: { Self.now },
                startPurchase: { _ in [.init(rawValue: 9)] }, fetch: { _ in entitlement })
        }
    }

    /// Constructs an exact server-owned policy with explicit development/consumption opt-ins.
    /// - Parameters:
    ///   - consumable: Require explicit unused receipt state; defaults false.
    ///   - allowsTests: Permit known test-mode receipts and their absent time bounds; defaults false.
    /// - Returns: User 4's application 2/SKU 3 policy without I/O or shared state.
    private static func policy(consumable: Bool = false, allowsTests: Bool = false) -> EntitlementRequirement {
        EntitlementRequirement(applicationID: .init(rawValue: 2), skuID: .init(rawValue: 3),
            owner: .user(.init(rawValue: 4)), consumable: consumable, allowsTestPurchases: allowsTests)
    }

    /// Parses a complete authoritative synthetic grant with deliberate field overrides/omissions.
    /// - Parameters:
    ///   - overrides: Exact replacements for tested branches; defaults empty.
    ///   - removing: Keys to omit after replacement, preserving absent separately from null; defaults empty.
    /// - Returns: Immutable fixture with open validity bounds and explicit unused state by default.
    /// - Throws: JSON/model errors for a malformed synthetic setup.
    private static func fixture(_ overrides: [String: JSONValue] = [:], removing: [String] = []) throws -> Entitlement {
        var fields: [String: JSONValue] = ["id": .string("1"), "application_id": .string("2"), "sku_id": .string("3"),
            "user_id": .string("4"), "type": try .number(.init(rawValue: "1")), "deleted": .bool(false),
            "starts_at": .null, "ends_at": .null, "consumed": .bool(false)]
        fields.merge(overrides) { _, new in new }
        for key in removing { fields.removeValue(forKey: key) }
        return try Entitlement(data: JSONValue.object(fields).serialized())
    }
}

/// Original synthetic transport failure used to verify no consume retry or accidental grant occurs.
private enum CommerceFailure: Error { case failed }
/// Serialized nonsecret invocation log for deterministic request ordering assertions.
private actor CommerceRecorder {
    var events: [String] = []
    /// Appends one operation label to the observed order.
    /// - Parameter event: Synthetic fixed operation name, never an account or token identifier.
    func record(_ event: String) { events.append(event) }
}

extension EntitlementVerificationTests {
    /// Uses native SwiftLog capture for verification, rejection and fetch failure while keeping
    /// authoritative entitlement fields and arbitrary executor errors outside log messages.
    /// - Throws: Unexpected valid entitlement construction or verification errors.
    @Test func structuredLoggingExcludesPurchaseIdentity() async throws {
        let recorder = LogRecorder()
        let entitlement = try Self.fixture()
        try await DiscordLog.$loggerFactory.withValue({ recorder.makeLogger($0) }) {
            _ = try await EntitlementVerification.verify(entitlementID: .init(rawValue: 1),
                requirement: Self.policy(), now: { Self.now }, fetch: { _ in entitlement })
            await #expect(throws: EntitlementVerificationError.mismatchedGrant) {
                try await EntitlementVerification.verify(entitlementID: .init(rawValue: 999_987_654),
                    requirement: Self.policy(), now: { Self.now }, fetch: { _ in entitlement })
            }
            await #expect(throws: TestSupportFailure.scripted("private-commerce-error")) {
                try await EntitlementVerification.verify(entitlementID: .init(rawValue: 1),
                    requirement: Self.policy(), now: { Self.now }, fetch: { _ in
                        throw TestSupportFailure.scripted("private-commerce-error")
                    })
            }
        }
        let entries = recorder.entries.filter { $0.label == "discordkit.commerce.entitlements" }
        #expect(entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "commerce.verification.completed" })
        #expect(entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "commerce.verification.rejected" })
        #expect(entries.contains { $0.level == .debug && $0.metadata["dk.event"] == "commerce.verification.failed" })
        let rendered = entries.map { $0.message + String(describing: $0.metadata) }.joined()
        #expect(!rendered.contains("999987654"))
        #expect(!rendered.contains("private-commerce-error"))
        #expect(entries.allSatisfy { Set($0.metadata.keys).isSubset(of: ["dk.event", "dk.subsystem", "dk.module"]) })
    }
}
