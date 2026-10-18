import DiscordCore
import DiscordHTTP
import DiscordModels
import DiscordTransport

/// User-consented API v10 Social operations over an existing bounded REST pipeline.
/// Construction starts no I/O and never acquires consent, refreshes tokens, joins a socket,
/// or substitutes bot credentials. The application retains ownership of shared HTTP authorities.
public struct SocialHTTPProvider<C: Clock>: SocialProfileProvider where C.Duration == Duration {
    public typealias ProviderClock = C
    private let client: RESTClient<C>
    public let profileRequirements = SocialProviderRequirements(scopes: ["identify"])
    /// User scope for every lobby operation; Discord separately validates membership and linking permissions.
    public let lobbyRequirements = SocialProviderRequirements(scopes: ["sdk.social_layer"])

    /// Retains an independently owned HTTP client without inspecting or copying its credential.
    /// - Parameter client: User bearer client sharing credential identity, admission and optional cache authorities.
    ///   Every operation enforces bearer authentication at execution; a bot-configured client fails before I/O.
    public init(client: RESTClient<C>) { self.client = client }

    /// Reads the consented user's profile through GET /users/@me with bearer-only authentication.
    /// - Parameter context: Cancellation and optional inclusive deadline in the REST client's clock domain.
    /// - Returns: Complete user projection; this snapshot establishes no relationship or messaging permission.
    /// - Throws: Missing bearer credential, cancellation, deadline, API, admission, transport or schema failures.
    /// Only in-flight read coalescing is eligible by default; no completed cache or hidden hydration is requested.
    public func currentProfile(context: TransportContext<C>) async throws -> User {
        let base = try UserEndpoints.current()
        let endpoint = try Endpoint(method: base.method, path: base.path, authentication: .bearer,
            retrySafety: base.retrySafety, readPolicy: base.readPolicy, decode: base.decode)
        return try await client.execute(endpoint, deadline: context.deadline)
    }

    /// Creates or joins the caller's secret-scoped lobby using its sdk.social_layer grant.
    /// - Parameters:
    ///   - request: Validated secret, optional replacement metadata and idle timeout; secrets remain redacted.
    ///   - context: Cancellation and deadline in the HTTP clock domain.
    /// - Returns: The authoritative lobby response; SDK-origin and application-bot lobbies retain different joining rules.
    /// - Throws: Validation, authentication/scope, API, cancellation, deadline, transport or decoding failures.
    /// Submitted mutations are never blindly replayed; an indeterminate result requires explicit reconciliation.
    public func createOrJoinLobby(_ request: CreateOrJoinLobbyRequest, context: TransportContext<C>) async throws -> Lobby {
        try await client.execute(LobbyEndpoints.createOrJoin(request: request), deadline: context.deadline)
    }

    /// Leaves one lobby as the consented user without deleting the application-owned lobby.
    /// - Parameters:
    ///   - lobbyID: Exact lobby identifier; a missing lobby remains an API failure.
    ///   - context: Cancellation and deadline in the HTTP clock domain.
    /// - Throws: Authentication/scope, API, cancellation, deadline or uncertain submitted-mutation failures.
    /// No user-ID lookup, implicit retry or local membership assertion occurs.
    public func leaveLobby(_ lobbyID: LobbyID, context: TransportContext<C>) async throws {
        _ = try await client.execute(LobbyEndpoints.leave(lobbyID: lobbyID), deadline: context.deadline)
    }

    /// Links an existing text channel under the user's sdk.social_layer grant and CanLinkLobby membership.
    /// - Parameters:
    ///   - lobbyID: Exact target lobby.
    ///   - channelID: Existing eligible text channel, validated authoritatively by Discord.
    ///   - context: Cancellation and optional HTTP-clock deadline.
    /// - Returns: Updated lobby; no channel or membership hydration is performed.
    /// - Throws: Validation, permissions, authentication, API, cancellation, deadline or indeterminate mutation failures.
    public func linkChannel(lobbyID: LobbyID, channelID: ChannelID, context: TransportContext<C>) async throws -> Lobby {
        try await client.execute(LobbyEndpoints.linkChannel(lobbyID: lobbyID, channelID: channelID), deadline: context.deadline)
    }

    /// Removes the linked channel under the same user grant and CanLinkLobby requirements as linking.
    /// - Parameters:
    ///   - lobbyID: Exact lobby; no preliminary read is performed.
    ///   - context: Cancellation and optional HTTP-clock deadline.
    /// - Returns: Updated authoritative lobby.
    /// - Throws: Authentication, permission, API, cancellation, deadline, transport or uncertain mutation failures.
    public func unlinkChannel(lobbyID: LobbyID, context: TransportContext<C>) async throws -> Lobby {
        try await client.execute(LobbyEndpoints.unlinkChannel(lobbyID: lobbyID), deadline: context.deadline)
    }

    /// Sends one lobby message using the member's sdk.social_layer grant.
    /// - Parameters:
    ///   - lobbyID: Lobby in which the current user has membership.
    ///   - request: Validated content, optional metadata and flags; no DM protocol is inferred.
    ///   - context: Cancellation and optional HTTP-clock deadline.
    /// - Returns: Created lobby message; success does not establish delivery into a linked channel.
    /// - Throws: Validation, membership/scope, API, cancellation, deadline or indeterminate mutation failures.
    /// The shared REST pipeline retains bounded rate-limit admission and rejected-429 retry policy.
    public func sendLobbyMessage(lobbyID: LobbyID, request: SendLobbyMessageRequest,
                                 context: TransportContext<C>) async throws -> LobbyMessage {
        try await client.execute(LobbyEndpoints.sendMessage(lobbyID: lobbyID, request: request), deadline: context.deadline)
    }

    /// Reads one finite recent-message snapshot; the public Lobby API publishes no history cursor.
    /// - Parameters:
    ///   - lobbyID: Lobby with current user membership and sdk.social_layer authorization.
    ///   - limit: Optional inclusive 1...200 cap; nil requests the upstream default of 50.
    ///   - context: Cancellation and optional HTTP-clock deadline.
    /// - Returns: Messages in upstream order, including an empty array; no traversal or hydration occurs.
    /// - Throws: Invalid bounds, auth/membership, API, cancellation, deadline, transport or malformed-response failures.
    public func lobbyMessages(lobbyID: LobbyID, limit: Int? = nil,
                              context: TransportContext<C>) async throws -> [LobbyMessage] {
        try await client.execute(LobbyEndpoints.messages(lobbyID: lobbyID, limit: limit), deadline: context.deadline)
    }

    /// Creates the documented single-use, one-hour invite into an already linked channel.
    /// - Parameters:
    ///   - lobbyID: Lobby with a linked channel and the caller's sdk.social_layer membership.
    ///   - context: Cancellation and optional HTTP-clock deadline.
    /// - Returns: Invite code; the operation neither accepts it nor joins a Discord guild.
    /// - Throws: Missing-link, authentication/scope, API, cancellation, deadline or indeterminate mutation failures.
    public func createLinkedChannelInvite(lobbyID: LobbyID, context: TransportContext<C>) async throws -> LobbyInvite {
        try await client.execute(LobbyEndpoints.createChannelInviteForSelf(lobbyID: lobbyID), deadline: context.deadline)
    }
}

/// Explicit application-bot authority for public identity/profile HTTP equivalents.
/// A bot credential never supplies Social user consent. Discord independently checks application
/// ownership, target-user application_identities.write consent and game-stats approval.
public struct SocialHTTPApplicationProvider<C: Clock>: Sendable where C.Duration == Duration {
    private let client: RESTClient<C>
    public let applicationID: ApplicationID
    /// Target-user consent required in addition to the separately configured application bot credential.
    /// Ownership and game-stats approval remain authoritative server checks, never inferred from this value.
    public let identityRequirements = SocialProviderRequirements(scopes: ["application_identities.write"])

    /// Binds the application identity without I/O or credential-category inference.
    /// - Parameters:
    ///   - applicationID: Application owned by the caller's bot; Discord checks this ownership on execution.
    ///   - client: Independently owned bot HTTP client with shared credential/rate/reuse authorities.
    public init(applicationID: ApplicationID, client: RESTClient<C>) {
        self.applicationID = applicationID; self.client = client
    }

    /// Lists external application identities for an explicitly selected consenting Discord user.
    /// - Parameters:
    ///   - userID: User granting application_identities.write; the supplied ID does not prove consent.
    ///   - context: Cancellation and optional deadline in the HTTP clock domain.
    /// - Returns: Ordered identity records, including an empty list; no profile fetch or linking occurs.
    /// - Throws: Authentication, ownership/consent, API, cancellation, deadline, transport or schema failures.
    public func identities(userID: UserID, context: TransportContext<C>) async throws -> ApplicationIdentityList {
        try await client.execute(ApplicationIdentityEndpoints.byUser(applicationID: applicationID, userID: userID), deadline: context.deadline)
    }

    /// Resolves an exact external account key through the documented application identity route.
    /// - Parameters:
    ///   - key: Validated provider tuple; external identifiers never become inferred Discord identifiers.
    ///   - context: Cancellation and optional HTTP-clock deadline.
    /// - Returns: Matching identity list, possibly empty; no account authentication or linking is performed.
    /// - Throws: Validation, bot ownership/consent, API, cancellation, deadline, transport or schema failures.
    public func identities(key: ApplicationIdentityKey, context: TransportContext<C>) async throws -> ApplicationIdentityList {
        try await client.execute(ApplicationIdentityEndpoints.byExternal(applicationID: applicationID, key: key), deadline: context.deadline)
    }

    /// Deletes one explicitly selected identity and its profile under application-bot authority.
    /// - Parameters:
    ///   - userID: Consenting target user; deleting the last account-linking identity remains prohibited upstream.
    ///   - key: Exact provider tuple to remove; no discovery or other account unlinking occurs.
    ///   - context: Cancellation and optional HTTP-clock deadline.
    /// - Throws: Validation, authentication/consent, API, cancellation, deadline or uncertain mutation failures.
    /// No token revocation, automatic retry or broader Social-account unlink is implied.
    public func deleteIdentity(userID: UserID, key: ApplicationIdentityKey, context: TransportContext<C>) async throws {
        _ = try await client.execute(ApplicationIdentityEndpoints.delete(applicationID: applicationID, userID: userID, key: key), deadline: context.deadline)
    }

    /// Reads stored stats/profile data for one application identity without fetching public user data.
    /// - Parameters:
    ///   - userID: User granting application_identities.write to this application.
    ///   - providerIssuedUserID: Exact validated external account path segment, at most 4,096 UTF-8 bytes.
    ///   - context: Cancellation and optional HTTP-clock deadline.
    /// - Returns: Stored profile snapshot; present data does not establish current consent or account ownership.
    /// - Throws: Validation, authentication/consent/approval, API, cancellation, deadline or decoding failures.
    public func profile(userID: UserID, providerIssuedUserID: String,
                        context: TransportContext<C>) async throws -> ApplicationIdentityProfile {
        try await client.execute(ApplicationIdentityProfileEndpoints.get(applicationID: applicationID, userID: userID,
            providerIssuedUserID: providerIssuedUserID), deadline: context.deadline)
    }

    /// Updates explicitly supplied profile fields; supplied stats replace the complete stats object.
    /// - Parameters:
    ///   - userID: Consenting user; game-stats approval remains Discord-authoritative.
    ///   - providerIssuedUserID: Exact external key, validated by the existing descriptor.
    ///   - request: Validated username/full-stats replacement; omission preserves a field, never merges nested stats.
    ///   - context: Cancellation and optional HTTP-clock deadline.
    /// - Returns: Present returned profile or explicit null for the documented bodyless successful update.
    /// - Throws: Validation, auth/consent/approval, API, cancellation, deadline or indeterminate mutation failures.
    public func updateProfile(userID: UserID, providerIssuedUserID: String, request: ApplicationIdentityProfileUpdate,
                              context: TransportContext<C>) async throws -> Nullable<ApplicationIdentityProfile> {
        try await client.execute(ApplicationIdentityProfileEndpoints.update(applicationID: applicationID, userID: userID,
            providerIssuedUserID: providerIssuedUserID, request: request), deadline: context.deadline)
    }
}
