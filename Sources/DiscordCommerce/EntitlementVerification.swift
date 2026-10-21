import DiscordLogging
import DiscordCore
import DiscordHTTP
import DiscordModels
import Foundation

/// Exact premium owner being authorized; user and guild grants must never be interchanged.
public enum EntitlementOwner: Sendable, Equatable {
    /// The requested feature belongs to exactly this user.
    case user(UserID)
    /// The requested feature belongs to exactly this guild; guild membership remains a separate caller check.
    case guild(GuildID)
}

/// Fail-closed rejection of authoritative entitlement data without exposing account or purchase identifiers.
public enum EntitlementVerificationError: Error, Sendable, Equatable {
    /// Returned ID, application, SKU or exact user/guild owner differs from the requested grant.
    case mismatchedGrant
    /// Deleted, not-yet-started, expired, unknown-origin or disallowed test-mode entitlement.
    case inactiveGrant
    /// Consumption state is absent or already true for a requested consumable.
    case unavailableConsumable
    /// The caller attempted consumption using a requirement that does not explicitly select a consumable.
    case consumptionNotRequested
    /// Host returned an excessive, duplicate or foreign purchase acknowledgement; no grant was authorized.
    case invalidPurchaseAcknowledgement
}

/// Caller-owned server authorization policy for one offering. Subscription status is deliberately absent:
/// only authoritative entitlement data authorizes access. Construction has no network or task side effects.
public struct EntitlementRequirement: Sendable {
    public let applicationID: ApplicationID
    public let skuID: SKUID
    public let owner: EntitlementOwner
    public let consumable: Bool
    public let allowsTestPurchases: Bool

    /// Records exact grant matching and development policy without trusting client purchase receipts.
    /// - Parameters:
    ///   - applicationID: Application serving the premium feature.
    ///   - skuID: Exact offering selected by the server's own catalog.
    ///   - owner: Exact user or guild owner; guild grants require separately verified guild membership.
    ///   - consumable: Require explicitly false consumed state; defaults false for durable/subscription grants.
    ///   - allowsTestPurchases: Explicit development-only opt-in to TEST_MODE_PURCHASE; defaults false.
    /// No I/O occurs and no current grant is established until authoritative verification succeeds.
    public init(applicationID: ApplicationID, skuID: SKUID, owner: EntitlementOwner,
        consumable: Bool = false, allowsTestPurchases: Bool = false) {
        self.applicationID = applicationID; self.skuID = skuID; self.owner = owner
        self.consumable = consumable; self.allowsTestPurchases = allowsTestPurchases
    }

    /// Validates one authoritative snapshot against exact owner/offering, time and consumption policy.
    /// - Parameters:
    ///   - entitlement: Server-fetched Discord data, never an untrusted client-supplied object.
    ///   - entitlementID: Exact ID requested from the server, preventing response substitution.
    ///   - now: Trusted current instant supplied by the backend; start is inclusive, end exclusive, nanoseconds exact.
    /// - Throws: Sanitized matching/inactive/consumable errors. Missing timestamps fail closed unless test purchases
    ///   are explicitly enabled for perpetual partial test entitlements; null dates represent open bounds.
    ///   Unknown origins never receive access automatically. This synchronous check cannot prevent a later
    ///   revocation/consume race, prove freshness or implement durable exactly-once game delivery.
    public func validate(_ entitlement: Entitlement, entitlementID: EntitlementID,
        now: DiscordTimestamp) throws {
        let matchesOwner = switch owner {
        case .user(let id): entitlement.userID == .value(id) && {
            if case .value = entitlement.guildID { return false }
            return true
        }()
        case .guild(let id): entitlement.guildID == .value(id)
        }
        guard entitlement.id == entitlementID, entitlement.applicationID == applicationID,
              entitlement.skuID == skuID, matchesOwner else { throw EntitlementVerificationError.mismatchedGrant }
        guard !entitlement.deleted, let origin = entitlement.type.knownValue,
              allowsTestPurchases || origin != .testModePurchase else { throw EntitlementVerificationError.inactiveGrant }
        for (field, isStart) in [(entitlement.startsAt, true), (entitlement.endsAt, false)] {
            switch field {
            case .absent:
                guard allowsTestPurchases, origin == .testModePurchase else { throw EntitlementVerificationError.inactiveGrant }
            case .null: break
            case .value(let bound):
                let less = now.unixSeconds < bound.unixSeconds ||
                    (now.unixSeconds == bound.unixSeconds && now.nanosecond < bound.nanosecond)
                if isStart ? less : !less { throw EntitlementVerificationError.inactiveGrant }
            }
        }
        if consumable, entitlement.consumed != .value(false) {
            throw EntitlementVerificationError.unavailableConsumable
        }
    }
}

/// Backend-only verification/consumption using the existing typed API v10 entitlement descriptors.
/// Executors must be authenticated authoritative REST clients sharing credential rate authorities.
public enum EntitlementVerification {
    /// Fetches exactly one entitlement without in-flight or completed read reuse, then applies the server policy.
    /// - Parameters:
    ///   - entitlementID: Untrusted purchase hint, never sufficient by itself to grant a feature.
    ///   - requirement: Server-owned application, SKU, owner and environment policy.
    ///   - now: Trusted clock called after network completion so expiry is checked at verification time.
    ///   - fetch: Cooperative authoritative server executor, normally RESTClient.execute with bot credentials.
    /// - Returns: Verified snapshot for deliberate server use; no item is granted, persisted or consumed.
    /// - Throws: Pre/post-fetch cancellation, original API/transport errors, or sanitized policy errors. A successful
    ///   snapshot can subsequently be revoked; long-lived authorization needs explicit freshness/invalidation policy.
    public static func verify(entitlementID: EntitlementID, requirement: EntitlementRequirement,
        now: @Sendable () -> DiscordTimestamp,
        fetch: @Sendable (Endpoint<Entitlement>) async throws -> Entitlement) async throws -> Entitlement {
        let logger = DiscordLog.makeLogger("commerce.entitlements")
        logger.trace("Entitlement verification started", metadata: ["dk.event": "commerce.verification.started"])
        try Task.checkCancellation()
        let descriptor = try EntitlementEndpoints.get(applicationID: requirement.applicationID,
            entitlementID: entitlementID, readPolicy: nil)
        let entitlement: Entitlement
        do {
            logger.trace("Authoritative entitlement fetch admitted", metadata: ["dk.event": "commerce.verification.fetch.admitted"])
            entitlement = try await fetch(descriptor)
            logger.trace("Authoritative entitlement fetch completed", metadata: ["dk.event": "commerce.verification.fetch.completed"])
        } catch {
            if error is CancellationError || Task.isCancelled {
                logger.trace("Entitlement fetch cancelled", metadata: ["dk.event": "commerce.verification.cancelled"])
            } else {
                logger.debug("Entitlement fetch failed", metadata: ["dk.event": "commerce.verification.failed"])
            }
            throw error
        }
        try Task.checkCancellation()
        do {
            logger.trace("Entitlement owner offering and validity validating", metadata: ["dk.event": "commerce.verification.policy.validating"])
            try requirement.validate(entitlement, entitlementID: entitlementID, now: now())
            logger.trace("Entitlement grant policy admitted", metadata: ["dk.event": "commerce.verification.policy.admitted"])
        } catch {
            logger.debug("Entitlement authorization rejected", metadata: ["dk.event": "commerce.verification.rejected"])
            throw error
        }
        logger.debug("Entitlement verification completed", metadata: ["dk.event": "commerce.verification.completed"])
        return entitlement
    }

    /// Verifies one consumable on the backend, then submits exactly one explicit consumption mutation.
    /// - Parameters:
    ///   - entitlementID: Exact consumable receipt to verify and consume.
    ///   - requirement: Server policy with consumable=true; a durable/subscription requirement is rejected before I/O.
    ///   - now: Trusted verification instant obtained after the fetch.
    ///   - fetch: Authoritative uncached server GET executor.
    ///   - consume: Cooperative typed consume executor, ordinarily the same shared backend REST client.
    /// - Returns: Verified pre-consumption snapshot only after an acknowledged consume succeeds.
    /// - Throws: Policy/cancellation/API/transport errors. Cancellation after submission or an uncertain mutation
    ///   can mean consumption succeeded; reconcile with a fresh server read before any explicit retry. There is
    ///   no automatic replay, refund, game-item delivery or exactly-once guarantee across concurrent workers.
    ///   Applications must use durable receipt ownership/idempotent delivery. This is not Social Commerce fulfillment.
    public static func consume(entitlementID: EntitlementID, requirement: EntitlementRequirement,
        now: @Sendable () -> DiscordTimestamp,
        fetch: @Sendable (Endpoint<Entitlement>) async throws -> Entitlement,
        consume: @Sendable (Endpoint<EmptyResponse>) async throws -> EmptyResponse) async throws -> Entitlement {
        guard requirement.consumable else { throw EntitlementVerificationError.consumptionNotRequested }
        let entitlement = try await verify(entitlementID: entitlementID, requirement: requirement, now: now, fetch: fetch)
        try Task.checkCancellation()
        DiscordLog.makeLogger("commerce.entitlements").trace("Verified entitlement consumption submitting once", metadata: ["dk.event": "commerce.consumption.submitting"])
        _ = try await consume(EntitlementEndpoints.consume(applicationID: requirement.applicationID,
            entitlementID: entitlementID))
        DiscordLog.makeLogger("commerce.entitlements").info("Entitlement consumption acknowledged", metadata: ["dk.event": "commerce.consumption.completed"])
        return entitlement
    }
}

/// Activity purchase orchestration through an injected Embedded App SDK host bridge and authoritative backend.
/// The host must map to web-only startPurchase({sku_id}); native SDK/JavaScript hosting is not bundled here.
public enum ActivityPurchasing {
    /// Starts one explicit purchase and independently verifies each hinted entitlement using the server API.
    /// - Parameters:
    ///   - requirement: Server-owned offering/user/environment policy; Activity purchases require a user owner.
    ///   - now: Trusted backend clock called after each authoritative read.
    ///   - startPurchase: Host bridge to startPurchase, returning its Entitlement[] IDs or nil. This bridge's data
    ///     is a hint only; it must propagate host errors/cancellation and must not embed a bot token/client secret.
    ///   - fetch: Authoritative backend GET executor; credentials remain exclusively on the backend.
    /// - Returns: Verified snapshots in host order; nil means no synchronous entitlement acknowledgement.
    ///   Empty arrays remain explicit successful empty results. ENTITLEMENT_CREATE may arrive later and should
    ///   trigger a separate server check. The flow never grants items from the host acknowledgement alone.
    /// - Throws: Cancellation, host/fetch errors or grant-policy errors. More than 100 IDs, duplicates and guild
    ///   requirements fail before server reads. No polling, subscription-status authorization or hidden consume occurs.
    public static func purchase(requirement: EntitlementRequirement, now: @Sendable () -> DiscordTimestamp,
        startPurchase: @Sendable (SKUID) async throws -> [EntitlementID]?,
        fetch: @Sendable (Endpoint<Entitlement>) async throws -> Entitlement) async throws -> [Entitlement]? {
        guard case .user = requirement.owner else { throw EntitlementVerificationError.invalidPurchaseAcknowledgement }
        try Task.checkCancellation()
        let logger = DiscordLog.makeLogger("commerce.entitlements")
        logger.trace("Activity purchase host operation starting", metadata: ["dk.event": "commerce.purchase.host.started"])
        let acknowledgement = try await startPurchase(requirement.skuID)
        logger.trace("Activity purchase host operation returned", metadata: ["dk.event": "commerce.purchase.host.completed",
            "dk.acknowledged": .stringConvertible(acknowledgement != nil)])
        try Task.checkCancellation()
        guard let identifiers = acknowledgement else { return nil }
        guard identifiers.count <= 100, Set(identifiers).count == identifiers.count
        else { throw EntitlementVerificationError.invalidPurchaseAcknowledgement }
        logger.trace("Purchase acknowledgement bounds validated", metadata: ["dk.event": "commerce.purchase.verification.started",
            "dk.count": .stringConvertible(identifiers.count)])
        var verified: [Entitlement] = []
        for identifier in identifiers {
            verified.append(try await EntitlementVerification.verify(entitlementID: identifier,
                requirement: requirement, now: now, fetch: fetch))
        }
        DiscordLog.makeLogger("commerce.entitlements").info("Purchase acknowledgements verified", metadata: ["dk.event": "commerce.purchase.completed",
            "dk.count": .stringConvertible(verified.count)])
        return verified
    }
}
