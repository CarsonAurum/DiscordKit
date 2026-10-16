import DiscordCore
import DiscordHTTP

/// Authenticated discovery descriptors required by the minimal sharded Gateway runtime.
public enum GatewayEndpoints {
    /// Creates GET /gateway/bot for current URL, recommended shards and Identify allowances.
    ///
    /// Requires a bot token and API v10. No intents or guild permissions are required.
    /// HTTP execution coordinates route/global rate admission and bounded safe retries.
    /// In-flight discovery may coalesce within one authentication scope, but completed
    /// responses are never cached: session-start allowances change as shards Identify.
    /// Do not construct a new startup ledger on every discovery call; refresh the shared one.
    /// https://docs.discord.com/developers/events/gateway#get-gateway-bot
    /// - Returns: Typed, bounded JSON discovery descriptor, with unknown fields retained.
    /// - Throws: Descriptor validation failures; execution/decoding errors surface when sent.
    public static func bot() throws -> Endpoint<GatewayDiscovery> {
        try Endpoint(method: "GET", path: ["gateway", "bot"], authentication: .bot,
            retrySafety: .safe, readPolicy: ReadPolicy()) { bytes in
                try GatewayDiscovery(json: JSONValue.parse(bytes))
            }
    }
}
