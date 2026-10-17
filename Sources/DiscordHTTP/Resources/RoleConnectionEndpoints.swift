import DiscordCore
import DiscordModels

/// Both application-owned linked-role definition operations on Discord API v10, verified 2026-10-16
/// against https://docs.discord.com/developers/resources/application-role-connection-metadata.
/// Bot authentication follows the official preview security contract. All executions share ordinary
/// credential/route rate admission, cancellation, deadlines and finite rejected-429 retries; no Gateway
/// adoption, implicit user update, role assignment or background metadata synchronization is required.
public enum ApplicationRoleConnectionMetadataEndpoints {
    /// Gets the application's complete list of linked-role metadata definitions without fetching user connections.
    /// - Parameters:
    ///   - applicationID: Exact application ID, checked for bot ownership by Discord; not a major rate parameter.
    ///   - readPolicy: Optional credential-scoped reuse; default coalescing with no completed caching.
    /// - Returns: Safe bot-only GET /applications/{application.id}/role-connections/metadata. The official
    ///   preview allows top-level null and nullable localization dictionaries, preserved rather than normalized.
    /// - Throws: Descriptor/policy errors now; token ownership/API/transport/cancellation/schema failures later.
    ///   Server results do not grant linked-role configuration permissions or establish fresh user eligibility.
    public static func get(applicationID: ApplicationID,
                           readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Nullable<[ApplicationRoleConnectionMetadata]>> {
        try Endpoint(method: "GET", path: ["applications", applicationID.description, "role-connections", "metadata"],
            route: "/applications/{application.id}/role-connections/metadata", authentication: .bot, retrySafety: .safe,
            readPolicy: expressionReadPolicy(readPolicy, tags: ["role-connection-metadata-catalog"]),
            decode: { try userNullableArray($0) { try ApplicationRoleConnectionMetadata(data: $0) } })
    }

    /// Replaces the application's metadata records with an explicit finite validated definition list.
    /// - Parameters:
    ///   - applicationID: Application owned by the bot token; current ownership remains a Discord check.
    ///   - request: Zero through five distinct-key records, or an explicit preview-supported null clear.
    /// - Returns: Unsafe bot-only PUT returning the full nullable list and invalidating metadata/application reads.
    /// - Throws: Body/descriptor errors now; ownership/API/transport/schema or indeterminate mutation failures later.
    ///   The operation sends one request, does not merge existing definitions and never updates individual users.
    public static func update(applicationID: ApplicationID,
                              request: ApplicationRoleConnectionMetadataUpdate) throws -> Endpoint<Nullable<[ApplicationRoleConnectionMetadata]>> {
        try Endpoint(method: "PUT", path: ["applications", applicationID.description, "role-connections", "metadata"],
            route: "/applications/{application.id}/role-connections/metadata", authentication: .bot,
            body: try guildJSON(request.jsonValue()), invalidates: ["role-connection-metadata-catalog", "application-catalog"],
            decode: { try userNullableArray($0) { try ApplicationRoleConnectionMetadata(data: $0) } })
    }
}
