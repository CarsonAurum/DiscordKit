import DiscordCore
import DiscordModels
import Foundation

/// One exclusive entitlement boundary; an enum prevents contradictory before/after query parameters.
public enum EntitlementPosition: Sendable, Equatable {
    /// Entitlements with IDs smaller than this boundary. The wire array's order is preserved.
    case before(EntitlementID)
    /// Entitlements with IDs larger than this boundary. The wire array's order is preserved.
    case after(EntitlementID)
}

/// One exclusive subscription boundary without assuming undocumented response ordering.
public enum SubscriptionPosition: Sendable, Equatable {
    /// Subscriptions with IDs smaller than this boundary.
    case before(SubscriptionID)
    /// Subscriptions with IDs larger than this boundary.
    case after(SubscriptionID)
}

/// Written API v10 SKU operations, verified 2026-10-16 against the official SKU reference.
/// Construction performs no I/O, privilege lookup or catalog hydration. Shared credential-global and
/// route admission, bounded retries, cancellation and transport ownership belong to RESTClient.
public enum SKUEndpoints {
    /// Lists every SKU for an application in one finite snapshot without inventing pagination.
    /// Subscription groups (type 6) remain visible; integrations normally select the subscription SKU (type 5).
    /// - Parameters:
    ///   - applicationID: Owning application; Discord validates bot ownership and monetization eligibility.
    ///   - readPolicy: Optional credential-scoped reuse; default coalesces without completed caching.
    ///     Opted-in positive TTL snapshots can remain stale after external catalog changes.
    /// - Returns: Safe GET descriptor requiring HTTP 200 with the ordered SKU array, including an empty array.
    /// - Throws: Descriptor/policy validation now; authentication/API/transport/schema/cancellation errors at execution.
    /// No Gateway intents or guild permissions are required; this operation does not establish purchase eligibility.
    public static func list(applicationID: ApplicationID,
                            readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[SKU]> {
        try Endpoint(method: "GET", path: ["applications", applicationID.description, "skus"],
            route: "/applications/{application.id}/skus", authentication: .bot, retrySafety: .safe,
            readPolicy: monetizationReadPolicy(readPolicy, tags: ["sku-catalog"]),
            decode: { try guildArray($0) { try SKU(data: $0) } })
    }
}

/// Five written entitlement operations for API v10, verified 2026-10-16 against the Entitlement reference
/// and official OpenAPI authentication/validation contracts. Discord checks application ownership,
/// entitlement ownership, consumable SKU eligibility and test-entitlement eligibility on execution.
/// No Gateway intent, audit-reason header or synthetic application major rate partition is introduced.
public enum EntitlementEndpoints {
    /// Lists one filtered entitlement page, including expired entries unless explicitly excluded.
    /// - Parameters:
    ///   - applicationID: Owning application, authorized by the executing bot or OAuth bearer token.
    ///   - userID: Optional entitled-user filter; nil omits it.
    ///   - skuIDs: Optional unique SKU set of at most 100 IDs; nil omits it, while an empty array sends an empty set.
    ///     Input order is retained in the documented comma-delimited representation.
    ///   - position: Optional exclusive before/after boundary; nil preserves upstream traversal defaults.
    ///   - limit: Optional count in 1...100; nil preserves upstream default 100.
    ///   - guildID: Optional entitled-guild filter; nil omits it without a membership lookup.
    ///   - excludeEnded: Optional ended-entitlement exclusion; nil preserves upstream default false.
    ///   - excludeDeleted: Optional deleted-entitlement exclusion; nil preserves upstream default true.
    ///   - readPolicy: Credential-scoped reuse, coalescing without completed caching by default; nil disables reuse.
    ///     Opted-in TTL snapshots cannot establish current premium access after an external lifecycle change.
    /// - Returns: Safe HTTP 200 GET descriptor preserving array order and exact unknown fields, including empty pages.
    /// - Throws: Invalid-value for bad limits, duplicate/excessive SKU IDs or invalid metadata/policy before I/O;
    ///   authentication/scopes, API, transport, schema and cancellation errors during execution.
    /// See https://docs.discord.com/developers/resources/entitlement#list-entitlements. Pagination is explicit;
    /// no follow-up request, retry outside the shared finite budget or privilege decision occurs here.
    public static func list(applicationID: ApplicationID, userID: UserID? = nil, skuIDs: [SKUID]? = nil,
        position: EntitlementPosition? = nil, limit: Int? = nil, guildID: GuildID? = nil,
        excludeEnded: Bool? = nil, excludeDeleted: Bool? = nil,
        readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[Entitlement]> {
        var query: [QueryItem] = []
        if let userID { query.append(.init(name: "user_id", value: userID.description)) }
        if let skuIDs {
            guard skuIDs.count <= 100, Set(skuIDs).count == skuIDs.count else { throw DiscordError.validation(.invalidValue) }
            query.append(.init(name: "sku_ids", value: skuIDs.map(\.description).joined(separator: ",")))
        }
        switch position {
        case .before(let id): query.append(.init(name: "before", value: id.description))
        case .after(let id): query.append(.init(name: "after", value: id.description))
        case nil: break
        }
        if let limit {
            guard (1...100).contains(limit) else { throw DiscordError.validation(.invalidValue) }
            query.append(.init(name: "limit", value: String(limit)))
        }
        if let guildID { query.append(.init(name: "guild_id", value: guildID.description)) }
        if let excludeEnded { query.append(.init(name: "exclude_ended", value: String(excludeEnded))) }
        if let excludeDeleted { query.append(.init(name: "exclude_deleted", value: String(excludeDeleted))) }
        return try Endpoint(method: "GET", path: ["applications", applicationID.description, "entitlements"],
            route: "/applications/{application.id}/entitlements", query: query, authentication: .botOrBearer,
            retrySafety: .safe, readPolicy: monetizationReadPolicy(readPolicy, tags: ["entitlement-catalog"]),
            decode: { data in
                let values = try guildArray(data) { try Entitlement(data: $0) }
                guard values.count <= (limit ?? 100) else { throw DiscordError.transport(.invalidResponse) }
                return values
            })
    }

    /// Fetches one entitlement without deriving access rights or performing another resource request.
    /// - Parameters:
    ///   - applicationID: Owning application checked against the executing bot/bearer authorization upstream.
    ///   - entitlementID: Exact entitlement to retrieve; a missing entitlement remains an API error.
    ///   - readPolicy: Optional scoped read reuse; default coalesces without completed caching.
    /// - Returns: Safe GET requiring HTTP 200, including partial perpetual test-entitlement lifecycle fields.
    /// - Throws: Descriptor/policy errors now; authentication/scopes/API/transport/schema/cancellation errors later.
    public static func get(applicationID: ApplicationID, entitlementID: EntitlementID,
                           readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Entitlement> {
        try Endpoint(method: "GET", path: ["applications", applicationID.description, "entitlements", entitlementID.description],
            route: "/applications/{application.id}/entitlements/{entitlement.id}", authentication: .botOrBearer,
            retrySafety: .safe, readPolicy: monetizationReadPolicy(readPolicy, tags: ["entitlement-catalog"]),
            decode: { try Entitlement(data: $0) })
    }

    /// Marks a one-time consumable entitlement consumed, without attempting purchase fulfillment or replay reconciliation.
    /// - Parameters:
    ///   - applicationID: Owning application authorized by the bot or appropriately scoped bearer token.
    ///   - entitlementID: User entitlement; Discord validates ownership, SKU consumability and current state.
    /// - Returns: Unsafe POST descriptor requiring an empty HTTP 204 and invalidating scoped entitlement snapshots.
    /// - Throws: Descriptor errors now; authorization/state/API failures or an indeterminate submitted mutation later.
    /// Complete 429 rejections may replay only within the shared finite budget; ambiguous sends are never replayed.
    public static func consume(applicationID: ApplicationID,
                               entitlementID: EntitlementID) throws -> Endpoint<EmptyResponse> {
        try entitlementMutation("POST", applicationID: applicationID, entitlementID: entitlementID,
            consume: true, successStatuses: [204], decode: { try EmptyResponse(data: $0) })
    }

    /// Creates one perpetual test entitlement for an explicitly typed guild or user owner.
    /// - Parameters:
    ///   - applicationID: Owning application; this operation requires its bot token, not an OAuth bearer token.
    ///   - request: Exact SKU and guild/user owner; owner_type is derived by the validated request.
    /// - Returns: Unsafe POST requiring HTTP 200 with the partial entitlement; starts_at/ends_at may be absent.
    ///   Scoped entitlement snapshots are invalidated on observed success; Discord clients may need reloading.
    /// - Throws: JSON/body/descriptor errors now; ownership/eligibility/API or indeterminate submission failures later.
    /// No current entitlement is fetched, duplicate create requests merged, or ambiguous mutation retried.
    public static func createTest(applicationID: ApplicationID,
                                  request: CreateTestEntitlementRequest) throws -> Endpoint<Entitlement> {
        try entitlementMutation("POST", applicationID: applicationID, authentication: .bot,
            payload: request.jsonValue(), decode: { try Entitlement(data: $0) })
    }

    /// Deletes one currently active test entitlement; ordinary paid entitlements are rejected upstream.
    /// - Parameters:
    ///   - applicationID: Owning application authorized by the executing bot or bearer token.
    ///   - entitlementID: Exact active test entitlement; no test-mode or owner discovery is performed.
    /// - Returns: Unsafe DELETE requiring empty HTTP 204 and scoped entitlement-cache invalidation.
    /// - Throws: Descriptor errors now; auth/state/API or indeterminate submitted-mutation errors during execution.
    /// Missing resources remain server errors; finite 429 retries do not authorize replaying ambiguous sends.
    public static func deleteTest(applicationID: ApplicationID,
                                  entitlementID: EntitlementID) throws -> Endpoint<EmptyResponse> {
        try entitlementMutation("DELETE", applicationID: applicationID, entitlementID: entitlementID,
            successStatuses: [204], decode: { try EmptyResponse(data: $0) })
    }
}

/// API v10 SKU subscription reads verified 2026-10-16 against the written Subscription reference and
/// official OpenAPI path/authentication definitions. Subscription status is billing information, not
/// authorization to premium features; applications must evaluate current entitlements separately.
public enum SubscriptionEndpoints {
    /// Lists one subscription page containing the SKU, optionally filtered to an explicit user.
    /// - Parameters:
    ///   - skuID: Exact recurring SKU; Discord validates application ownership and monetization eligibility.
    ///   - userID: Required for bot queries. Nil creates a bearer-only descriptor for the OAuth-authorized user;
    ///     a nonnil filter accepts either bot or appropriately scoped bearer authorization.
    ///   - position: Optional exclusive before/after subscription boundary; nil preserves upstream defaults.
    ///   - limit: Optional 1...100 result count; nil preserves upstream default 50.
    ///   - readPolicy: Scoped reuse, coalescing without completed caching by default; nil disables reuse.
    /// - Returns: Safe HTTP 200 GET descriptor retaining wire order, nullable lifecycle fields and empty pages.
    /// - Throws: Invalid-value for bad limit/metadata/policy now; missing-value if a bot executes an unfiltered
    ///   descriptor; scope/API/transport/schema/cancellation failures during execution.
    /// No Gateway intents, permission hydration or hidden pagination is required. Shared coordinated rate admission
    /// and finite retry budgets apply; neither a billing snapshot nor a private country field grants access.
    public static func list(skuID: SKUID, userID: UserID? = nil, position: SubscriptionPosition? = nil,
                            limit: Int? = nil, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[Subscription]> {
        var query: [QueryItem] = []
        switch position {
        case .before(let id): query.append(.init(name: "before", value: id.description))
        case .after(let id): query.append(.init(name: "after", value: id.description))
        case nil: break
        }
        if let limit {
            guard (1...100).contains(limit) else { throw DiscordError.validation(.invalidValue) }
            query.append(.init(name: "limit", value: String(limit)))
        }
        if let userID { query.append(.init(name: "user_id", value: userID.description)) }
        return try Endpoint(method: "GET", path: ["skus", skuID.description, "subscriptions"],
            route: "/skus/{sku.id}/subscriptions", query: query, authentication: userID == nil ? .bearer : .botOrBearer,
            retrySafety: .safe, readPolicy: monetizationReadPolicy(readPolicy, tags: ["subscription-catalog"]),
            decode: { data in
                let values = try guildArray(data) { try Subscription(data: $0) }
                guard values.count <= (limit ?? 50) else { throw DiscordError.transport(.invalidResponse) }
                return values
            })
    }

    /// Retrieves one SKU subscription without converting billing state into feature entitlement.
    /// - Parameters:
    ///   - skuID: SKU the subscription contains; checked by Discord upstream.
    ///   - subscriptionID: Exact subscription identifier; missing resources remain server API errors.
    ///   - userID: Optional explicit user filter from the official OpenAPI; nil omits it.
    ///   - readPolicy: Credential-scoped eligible reuse; default coalesces without a completed cache.
    /// - Returns: Safe HTTP 200 GET descriptor accepting bot or appropriately scoped OAuth bearer authorization.
    /// - Throws: Descriptor/policy errors now; auth/scopes/API/transport/schema/cancellation errors at execution.
    public static func get(skuID: SKUID, subscriptionID: SubscriptionID, userID: UserID? = nil,
                           readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Subscription> {
        try Endpoint(method: "GET", path: ["skus", skuID.description, "subscriptions", subscriptionID.description],
            route: "/skus/{sku.id}/subscriptions/{subscription.id}",
            query: userID.map { [.init(name: "user_id", value: $0.description)] } ?? [],
            authentication: .botOrBearer, retrySafety: .safe,
            readPolicy: monetizationReadPolicy(readPolicy, tags: ["subscription-catalog"]),
            decode: { try Subscription(data: $0) })
    }
}

/// Preserves explicit freshness/coalescing while adding scoped resource invalidation dependencies.
/// - Parameters:
///   - policy: Optional caller reuse choices; nil disables both coalescing and completed caching.
///   - tags: Finite resource-family tags; credential identity provides the authorization scope at execution.
/// - Returns: Equivalent caller policy plus family tags. No cache entry, task or network resource is created.
func monetizationReadPolicy(_ policy: ReadPolicy?, tags: Set<String>) -> ReadPolicy? {
    policy.map { ReadPolicy(coalescing: $0.coalescing, timeToLive: $0.timeToLive, tags: $0.tags.union(tags)) }
}

/// Constructs an explicitly unsafe entitlement write without synthetic rate partitions or hidden context reads.
/// - Parameters:
///   - method: Exact POST or DELETE method chosen by the public descriptor.
///   - applicationID: Owning application inserted into one escaped path segment.
///   - entitlementID: Optional target; nil addresses the entitlement collection.
///   - consume: Whether to append the fixed consume action, default false.
///   - authentication: Required credential category; defaults to bot/Bearer, creation explicitly selects bot.
///   - payload: Optional previously validated JSON body; nil transmits no body.
///   - successStatuses: Exact success set, default 200; consumption/deletion select 204.
///   - decode: Bounded original typed response decoder, including strict empty-response validation.
/// - Returns: Immutable descriptor invalidating the scoped entitlement catalog on observed mutation success.
/// - Throws: JSON/body/descriptor errors synchronously. Rate, cancellation and submission uncertainty belong to execution.
func entitlementMutation<T: Sendable>(_ method: String, applicationID: ApplicationID,
    entitlementID: EntitlementID? = nil, consume: Bool = false, authentication: AuthenticationPolicy = .botOrBearer,
    payload: JSONValue? = nil, successStatuses: Set<Int> = [200],
    decode: @escaping @Sendable (Data) throws -> T) throws -> Endpoint<T> {
    try Endpoint(method: method,
        path: ["applications", applicationID.description, "entitlements"] +
            (entitlementID.map { [$0.description] } ?? []) + (consume ? ["consume"] : []),
        route: "/applications/{application.id}/entitlements" + (entitlementID == nil ? "" : "/{entitlement.id}") +
            (consume ? "/consume" : ""), authentication: authentication, successStatuses: successStatuses,
        body: payload.map { try guildJSON($0) }, invalidates: ["entitlement-catalog"], decode: decode)
}
