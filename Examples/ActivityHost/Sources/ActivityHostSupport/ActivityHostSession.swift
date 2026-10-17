import DiscordActivities
import DiscordCore

/// Client-side Activity orchestration with an injected authenticated backend; no confidential credentials are accepted.
public enum ActivityHostSession {
    /// Authorizes through Discord, exchanges the code on the application's backend, and authenticates the iframe.
    /// - Parameters:
    ///   - client: Explicitly started Activity client over an authenticated browser transport.
    ///   - applicationID: Application configured for this iframe/backend session; never inferred from user input.
    ///   - exchange: Application-authenticated backend operation. It binds the code to this session, exchanges it once,
    ///     keeps client/refresh secrets on the server and returns only the scoped user access token over HTTPS.
    /// - Returns: Typed host authentication snapshot. Profile data and tokens must not enter logs.
    /// - Throws: Cancellation, consent/host rejection, backend exchange or payload validation failure. No retry occurs.
    /// This example requests identify only; individual operations need their own additional approved scopes.
    public static func authenticate<C: Clock>(client: ActivityClient<C>, applicationID: ApplicationID,
        exchange: @Sendable (String) async throws -> ActivityUserAccessToken) async throws -> ActivityAuthentication where C.Duration == Duration {
        let authorization = try await client.execute(ActivityRequests.authorize(clientID: applicationID.description, scopes: ["identify"]))
        try Task.checkCancellation()
        let token = try await exchange(authorization.code)
        try Task.checkCancellation()
        return try await client.execute(ActivityRequests.authenticate(accessToken: .value(token)))
    }

    /// Starts one explicit purchase and sends advisory entitlement IDs to an authenticated backend for authorization.
    /// - Parameters:
    ///   - client: Started/authenticated host client; START_PURCHASE remains web-only per current reference.
    ///   - skuID: Offering selected by trusted application configuration.
    ///   - verify: Backend call that binds the current user/SKU and checks each hint against GET entitlement data.
    ///     Null means asynchronous completion; ENTITLEMENT_CREATE must trigger a later authoritative backend check.
    /// - Returns: Backend's application-specific result. The host's response never grants an item by itself.
    /// - Throws: Cancellation, host/purchase/backend failure or malformed acknowledgement. Ambiguous purchases are not retried.
    public static func purchase<C: Clock, Result: Sendable>(client: ActivityClient<C>, skuID: String,
        verify: @Sendable ([String]?) async throws -> Result) async throws -> Result where C.Duration == Duration {
        let result = try await client.execute(ActivityRequests.startPurchase(skuID: skuID))
        try Task.checkCancellation()
        switch result.entitlements {
        case .null: return try await verify(nil)
        case .value(let values): return try await verify(values.map(\.id))
        }
    }
}
