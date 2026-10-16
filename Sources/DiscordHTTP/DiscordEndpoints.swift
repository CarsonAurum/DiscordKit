import DiscordModels
import Foundation

/// The initial API v10 endpoint slice; raw routes do not extend this parity claim.
public enum DiscordEndpoints {
    /// Describes `GET /users/@me`, without requiring Gateway or entity caching.
    /// - Parameter readPolicy: Explicit eligible-read policy, defaulting to in-flight coalescing only.
    ///   Completed-result caching requires a caller-selected positive TTL and can serve stale scopes.
    /// - Returns: A safe read accepting bot or OAuth2 bearer authentication and HTTP 200.
    /// - Throws: Descriptor validation errors, including invalid freshness metadata.
    ///
    /// OAuth2 requires `identify`; `email` controls email visibility and `identify.premium`
    /// controls premium type. No Gateway intents or guild permissions are required. The REST
    /// client coordinates learned rate limits, deadlines and bounded retries. See
    /// <https://docs.discord.com/developers/resources/user#get-current-user> (verified 2026-10-16).
    public static func currentUser(readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<User> {
        try Endpoint(method: "GET", path: ["users", "@me"], authentication: .botOrBearer,
                     retrySafety: .safe, readPolicy: readPolicy, decode: { try User(data: $0) })
    }

    /// Describes `GET /applications/@me` using the application's bot token.
    /// - Parameter readPolicy: Explicit read reuse, defaulting to in-flight coalescing without a TTL cache.
    /// - Returns: A safe API v10 read accepting HTTP 200, decoded as a partial typed application snapshot.
    /// - Throws: Descriptor validation errors, including nonpositive TTLs.
    ///
    /// This route requires bot authentication, no Gateway intents, and no pagination. Caller
    /// cancellation and learned rate limits are handled by the shared HTTP execution pipeline.
    /// See <https://docs.discord.com/developers/resources/application#get-current-application>
    /// (verified 2026-10-16). Partial owner/bot/team fields remain available in raw model fields.
    public static func currentApplication(readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Application> {
        try Endpoint(method: "GET", path: ["applications", "@me"], authentication: .bot,
                     retrySafety: .safe, readPolicy: readPolicy, decode: { try Application(data: $0) })
    }
}
