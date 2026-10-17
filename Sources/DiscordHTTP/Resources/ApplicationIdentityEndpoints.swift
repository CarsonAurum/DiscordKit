import DiscordCore
import DiscordModels

/// Complete written API v10 identity lookup/deletion operations, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/application-identity-profile. Each requires the
/// application's bot token and target user's application_identities.write OAuth2 authorization.
/// Discord checks ownership/consent; a descriptor never establishes either. Operations share the
/// ordinary credential/global rate coordinator, cancellation, deadlines and bounded rejected-429 retries.
public enum ApplicationIdentityEndpoints {
    /// Discovers exact external account keys for one user without fetching profile data.
    /// - Parameters:
    ///   - applicationID: Application owned by the bot token; Discord checks ownership.
    ///   - userID: Target Discord user whose consent must include application_identities.write.
    ///   - readPolicy: Optional credential-scoped read reuse; default coalesces in flight without completed caching.
    /// - Returns: Safe bot-only GET /users/{user.id}/application-identities/{application.id}, returning a
    ///   wrapped ordered list; empty identities remain an explicit successful empty result.
    /// - Throws: Descriptor/policy errors now; ownership/consent/API/transport/schema/cancellation errors on execution.
    ///   No pagination, background discovery, account linking or automatic profile read is introduced.
    public static func byUser(applicationID: ApplicationID, userID: UserID,
                              readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ApplicationIdentityList> {
        try Endpoint(method: "GET", path: ["users", userID.description, "application-identities", applicationID.description],
            route: "/users/{user.id}/application-identities/{application.id}", authentication: .bot, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["application-identity-catalog"]),
            decode: { try ApplicationIdentityList(data: $0) })
    }

    /// Resolves a caller-known external account key to its current Discord user/application identity records.
    /// - Parameters:
    ///   - applicationID: Owning application whose bot token executes the request.
    ///   - key: Validated open provider type, external account ID and optional exact provider_id query value.
    ///   - readPolicy: Optional credential-scoped read reuse; nil disables it, positive TTL may be stale.
    /// - Returns: Safe bot-only GET /applications/{application.id}/application-identities/{provider.type}/{provider.issued.user.id}.
    ///   The wrapped list is empty when no match exists; returned user IDs are not inferred from external IDs.
    /// - Throws: Descriptor/policy errors now; ownership/consent/API/transport/schema/cancellation failures later.
    ///   This does not fetch stats, perform OAuth, claim account ownership or automatically retry a missing match.
    public static func byExternal(applicationID: ApplicationID, key: ApplicationIdentityKey,
                                  readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ApplicationIdentityList> {
        let query = key.providerID.map { [QueryItem(name: "provider_id", value: $0)] } ?? []
        return try Endpoint(method: "GET", path: ["applications", applicationID.description, "application-identities",
                key.providerType, key.providerIssuedUserID],
            route: "/applications/{application.id}/application-identities/{provider.type}/{provider.issued.user.id}",
            query: query, authentication: .bot, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["application-identity-catalog"]),
            decode: { try ApplicationIdentityList(data: $0) })
    }

    /// Deletes one identity and its associated profile, without unlinking any other identity or silently repairing conflicts.
    /// - Parameters:
    ///   - applicationID: Application owned by the authenticated bot.
    ///   - userID: Target Discord user whose matching identity and stored profile will be deleted.
    ///   - key: Exact provider tuple, preferably explicitly selected from a prior lookup; provider_id becomes the
    ///     optional JSON body. Nil omits the body entirely; an empty string remains explicit.
    /// - Returns: Unsafe bot-only POST /users/{user.id}/application-identities/{application.id}/{provider.type}/{provider.issued.user.id}/delete
    ///   accepting only empty HTTP 204. Success invalidates identity/profile reads within the credential scope.
    /// - Throws: Descriptor/body errors now; Discord blocks deleting the final account-linking identity and checks
    ///   consent, ownership and conflicts. Submitted failures can be indeterminate; no ambiguous replay occurs.
    ///   Profile-only NONE identities are deletable. No separate token-revocation or general unlinking request is issued.
    public static func delete(applicationID: ApplicationID, userID: UserID,
                              key: ApplicationIdentityKey) throws -> Endpoint<EmptyResponse> {
        try Endpoint(method: "POST", path: ["users", userID.description, "application-identities", applicationID.description,
                key.providerType, key.providerIssuedUserID, "delete"],
            route: "/users/{user.id}/application-identities/{application.id}/{provider.type}/{provider.issued.user.id}/delete",
            authentication: .bot, successStatuses: [204],
            body: key.providerID == nil ? nil : try guildJSON(key.jsonValue()),
            invalidates: ["application-identity-catalog", "application-identity-profile-catalog"],
            decode: { try EmptyResponse(data: $0) })
    }
}

/// Written API v10 stats profile read/write operations. Adoptable with HTTP alone; no Gateway, OAuth
/// runtime, Social SDK or automatic periodic synchronization is required. The target user must already
/// grant application_identities.write to the application, and the caller must use its bot token.
public enum ApplicationIdentityProfileEndpoints {
    /// Fetches one stored profile without resolving external IDs or hydrating any other linked identity.
    /// - Parameters:
    ///   - applicationID: Application owned by the executing bot.
    ///   - userID: Discord user with the required application_identities.write consent.
    ///   - providerIssuedUserID: Exact external account ID, a safe nonempty path segment up to 4,096 UTF-8 bytes
    ///     under local bounds; Unicode and percent signs are encoded once, no provider type is invented for the route.
    ///   - readPolicy: Optional authentication-scoped reuse, default coalescing without completed-result caching.
    /// - Returns: Safe bot-only GET of the complete required-nullable username/metadata/data profile.
    /// - Throws: Invalid identifier/policy errors now; authorization/not-found/API/transport/schema/cancellation errors later.
    ///   Cached profiles do not prove present authorization, public media reachability or current account ownership.
    public static func get(applicationID: ApplicationID, userID: UserID, providerIssuedUserID: String,
                           readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ApplicationIdentityProfile> {
        let key = try ApplicationIdentityKey(providerType: "NONE", providerIssuedUserID: providerIssuedUserID)
        return try Endpoint(method: "GET", path: ["applications", applicationID.description, "users", userID.description,
                "identities", key.providerIssuedUserID, "profile"],
            route: "/applications/{application.id}/users/{user.id}/identities/{provider.issued.user.id}/profile",
            authentication: .bot, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["application-identity-profile-catalog"]),
            decode: { try ApplicationIdentityProfile(data: $0) })
    }

    /// Updates explicit username/full stats fields on the matching identity with one ordinary PATCH request.
    /// - Parameters:
    ///   - applicationID: Application owned by the executing bot and authorized by the target user.
    ///   - userID: Target Discord user; permissions, consent and account conflicts remain Discord checks.
    ///   - providerIssuedUserID: Exact matching external account ID, safe nonempty segment up to 4,096 UTF-8 bytes.
    ///   - request: Validated changes. Supplying data replaces all prior stats; omitting data preserves them.
    ///     An empty body object remains an explicit request unless the caller elects snapshot reconciliation beforehand.
    /// - Returns: Unsafe bot-only PATCH accepting HTTP 201 or 204. Empty success bodies return .null; a present
    ///   body is parsed as a complete profile. Official prose promises an object but the response section specifies
    ///   bodyless later updates, so no mandatory first-write body is invented. Empty 201 is also tolerated.
    /// - Throws: Identifier/body/descriptor errors now; Discord can reject missing game-stats approval, scope/ownership,
    ///   conflicting or mismatched external IDs, field limits or authentication. Transport/server failures after submission
    ///   can be indeterminate and are not replayed automatically; explicit rejected 429s share finite retry budgets.
    ///   The first successful write may create a NONE profile-only identity. No implicit fetch, merge or delete occurs.
    public static func update(applicationID: ApplicationID, userID: UserID, providerIssuedUserID: String,
                              request: ApplicationIdentityProfileUpdate) throws -> Endpoint<Nullable<ApplicationIdentityProfile>> {
        let key = try ApplicationIdentityKey(providerType: "NONE", providerIssuedUserID: providerIssuedUserID)
        return try Endpoint(method: "PATCH", path: ["applications", applicationID.description, "users", userID.description,
                "identities", key.providerIssuedUserID, "profile"],
            route: "/applications/{application.id}/users/{user.id}/identities/{provider.issued.user.id}/profile",
            authentication: .bot, successStatuses: [201, 204], body: try guildJSON(request.jsonValue()),
            invalidates: ["application-identity-catalog", "application-identity-profile-catalog"],
            decode: { $0.isEmpty ? .null : .value(try ApplicationIdentityProfile(data: $0)) })
    }
}
