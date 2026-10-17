import DiscordCore
import Foundation

/// Installation contexts supported by API v10 applications; recognition does not grant installation rights.
public enum ApplicationIntegrationType: Int, Sendable, CaseIterable {
    /// Installed into a guild with appropriate MANAGE_GUILD authorization.
    case guildInstall = 0
    /// Installed to the authorizing user's account.
    case userInstall = 1
}

/// Application event-webhook state; response wrappers retain unknown future integral states.
public enum ApplicationEventWebhookStatus: Int, Sendable {
    /// Disabled by the developer.
    case disabled = 1
    /// Enabled by the developer.
    case enabled = 2
    /// Disabled by Discord, such as for inactivity; this state cannot be requested.
    case disabledByDiscord = 3
}

/// Application category currently exposed by the official API v10 OpenAPI preview.
public enum ApplicationType: Int, Sendable {
    /// An application associated with guild role subscriptions.
    case guildRoleSubscriptions = 4
}

/// Preview application interaction-content scanning policy; no local content scanning occurs.
public enum ApplicationExplicitContentFilter: Int, Sendable {
    /// Inherit the guild's content filter setting.
    case inherit = 0
    /// Always scan interactions.
    case always = 1
}

/// Known public legacy Application flag bits; full future-width values remain in Application.flagsNew.
public struct ApplicationFlags: OptionSet, Sendable, Hashable {
    /// Complete exact machine-width bits, including unknown combinations.
    public let rawValue: UInt64
    /// Retains all supplied bits without inferring approval, intents, permissions or edit eligibility.
    /// - Parameter rawValue: Complete unsigned flag bits; no normalization, I/O or ownership changes occur.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
    /// Uses the Auto Moderation API.
    public static let autoModerationRuleCreateBadge = Self(rawValue: 1 << 6)
    /// Approved privileged presence intent.
    public static let gatewayPresence = Self(rawValue: 1 << 12)
    /// Limited privileged presence intent; mutable through the current-application endpoint.
    public static let gatewayPresenceLimited = Self(rawValue: 1 << 13)
    /// Approved privileged member intent.
    public static let gatewayGuildMembers = Self(rawValue: 1 << 14)
    /// Limited privileged member intent; mutable through the current-application endpoint.
    public static let gatewayGuildMembersLimited = Self(rawValue: 1 << 15)
    /// Unusual growth currently prevents verification.
    public static let verificationPendingGuildLimit = Self(rawValue: 1 << 16)
    /// Embedded in the Discord client.
    public static let embedded = Self(rawValue: 1 << 17)
    /// Approved privileged message-content intent.
    public static let gatewayMessageContent = Self(rawValue: 1 << 18)
    /// Limited message-content intent; mutable through the current-application endpoint.
    public static let gatewayMessageContentLimited = Self(rawValue: 1 << 19)
    /// Has registered global application commands.
    public static let applicationCommandBadge = Self(rawValue: 1 << 23)
}

/// Marker for developer-team identifiers, independent of guild/application IDs.
public enum ApplicationTeamTag: Sendable {}
/// Exact unsigned developer-team snowflake.
public typealias ApplicationTeamID = Snowflake<ApplicationTeamTag>
/// Marker for SKU identifiers referenced by an Application, without importing commerce execution.
public enum ApplicationSKUTag: Sendable {}
/// Exact unsigned SKU reference, without a commerce ownership claim.
public typealias ApplicationSKUID = Snowflake<ApplicationSKUTag>
/// Marker for project references exposed by the official OpenAPI preview.
public enum ApplicationProjectTag: Sendable {}
/// Exact unsigned preview project identifier.
public typealias ApplicationProjectID = Snowflake<ApplicationProjectTag>
/// Marker for activity-launch snowflakes, distinct from opaque activity instance identifiers.
public enum ApplicationActivityLaunchTag: Sendable {}
/// Exact activity-launch snowflake from the written Application resource.
public typealias ApplicationActivityLaunchID = Snowflake<ApplicationActivityLaunchTag>

/// Team membership states; future integer states survive through RawValue.
public enum ApplicationTeamMembershipState: Int, Sendable {
    /// Invited to the team but has not accepted.
    case invited = 1
    /// Accepted the team invitation.
    case accepted = 2
}

/// Team member roles; ownership is determined by the team's ownerUserID rather than this field.
public enum ApplicationTeamRole: String, Sendable {
    /// Can administer non-destructive team settings.
    case admin
    /// Can configure applications and access developer secrets.
    case developer
    /// Can inspect team/application information.
    case readOnly = "read_only"
}

/// Documented activity location kinds, including the preview-only party discriminator.
public enum ApplicationActivityLocationKind: String, Sendable {
    /// A guild channel.
    case guildChannel = "gc"
    /// A DM or group DM channel.
    case privateChannel = "pc"
    /// Preview-recognized party; its additional schema remains unmodeled and retained exactly.
    case party
}

/// A complete API v10 written Application projection with explicitly identified OpenAPI preview extensions, verified 2026-10-16.
/// User and guild references are documented partial projections; installation/team/activity children are owned typed values.
/// Raw team and flagsNew retain their original public shapes. Strings/URLs are response data, never permission or destination validation.
public struct Application: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let id: ApplicationID
    /// Wire `name`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let name: String
    /// Wire `icon`. Required nullable icon hash; no CDN resource is fetched.
    public let icon: Nullable<String>
    /// Wire `description`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let applicationDescription: String
    /// Wire `bot_public`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let botPublic: Bool
    /// Wire `bot_require_code_grant`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let botRequireCodeGrant: Bool
    /// Wire `verify_key`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let verifyKey: String
    /// Wire `team`. Required nullable exact raw team retained for source compatibility; use teamDetails for its typed view.
    public let team: Nullable<JSONValue>
    /// Wire `team`. Typed view of the same required nullable team; all current team-owned fields are validated.
    public let teamDetails: Nullable<ApplicationTeam>
    /// Wire `rpc_origins`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let rpcOrigins: Field<[String]>
    /// Wire `bot`. Optional nested projection preserving absence.
    public let bot: Field<ApplicationUser>
    /// Wire `terms_of_service_url`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let termsOfServiceURL: Field<String>
    /// Wire `privacy_policy_url`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let privacyPolicyURL: Field<String>
    /// Wire `owner`. Optional nested projection preserving absence.
    public let owner: Field<ApplicationUser>
    /// Wire `guild_id`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let guildID: Field<GuildID>
    /// Wire `guild`. Optional nested projection preserving absence.
    public let guild: Field<ApplicationGuild>
    /// Wire `primary_sku_id`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let primarySKUID: Field<ApplicationSKUID>
    /// Wire `slug`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let slug: Field<String>
    /// Wire `cover_image`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let coverImage: Field<String>
    /// Wire `flags`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let flags: Field<UInt64>
    /// Wire `flags_new`. Full arbitrary-width response bitset as exact decimal text; never narrowed or sent as flags_new in a request.
    public let flagsNew: Field<String>
    /// Wire `approximate_guild_count`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let approximateGuildCount: Field<Int>
    /// Wire `approximate_user_install_count`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let approximateUserInstallCount: Field<Int>
    /// Wire `approximate_user_authorization_count`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let approximateUserAuthorizationCount: Field<Int>
    /// Wire `redirect_uris`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let redirectURIs: Field<[String]>
    /// Wire `interactions_endpoint_url`. Optional nullable wire value; omission and explicit null remain distinct.
    public let interactionsEndpointURL: Field<String>
    /// Wire `role_connections_verification_url`. Optional nullable wire value; omission and explicit null remain distinct.
    public let roleConnectionsVerificationURL: Field<String>
    /// Wire `event_webhooks_url`. Optional nullable wire value; omission and explicit null remain distinct.
    public let eventWebhooksURL: Field<String>
    /// Wire `event_webhooks_status`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let eventWebhooksStatus: Field<RawValue<ApplicationEventWebhookStatus>>
    /// Wire `event_webhooks_types`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let eventWebhooksTypes: Field<[String]>
    /// Wire `tags`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let tags: Field<[String]>
    /// Wire `install_params`. Optional nested projection preserving absence.
    public let installParams: Field<ApplicationInstallParams>
    /// Wire `integration_types_config`. Installation-context keys retain unknown decimal values; each configuration has a typed owned projection.
    public let integrationTypesConfig: Field<[String: ApplicationIntegrationTypeConfiguration]>
    /// Wire `custom_install_url`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let customInstallURL: Field<String>
    /// Preview-only `type`; unknown integral categories, omission and explicit null remain distinct.
    public let type: Field<RawValue<ApplicationType>>
    /// Preview-only `max_participants`; optional nullable exact activity participant maximum.
    public let maxParticipants: Field<Int>
    /// Preview-only `explicit_content_filter`; optional interaction-scanning policy retaining future integral values.
    public let explicitContentFilter: Field<RawValue<ApplicationExplicitContentFilter>>
    /// Preview-only `conjure_project_id`; optional exact project reference, without a project execution API.
    public let conjureProjectID: Field<ApplicationProjectID>
    /// Preview-only `vibegrations_project_id`; optional exact project reference, without a project execution API.
    public let vibegrationsProjectID: Field<ApplicationProjectID>
    /// Preview-only `eligible_oauth2_scopes`; optional current eligibility strings, never an OAuth2 scope grant.
    public let eligibleOAuth2Scopes: Field<[String]>
    /// Complete original object, including unknown fields and exact numeric lexemes; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete immutable API v10 snapshot under limits covering all known and unknown subtrees.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known presence, scalar types and required nested fields are validated.
    ///   - limits: Whole-document byte, depth and node limits, default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or overflowing fields. Parsing is synchronous, performs no I/O, and owns no external resources.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded immutable subtree without recursive reparsing or unrelated-resource hydration.
    /// - Parameters:
    ///   - value: Original object subtree from a successfully bounded root document.
    ///   - limits: Bounds established for that root, reused during exact scalar projection.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; unknown values retain their spelling.
    /// No suspension, resource ownership, credential access or authorization lookup occurs.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ApplicationID.self)
        name = try object.required("name", String.self)
        icon = try object.required("icon", Nullable<String>.self)
        applicationDescription = try object.required("description", String.self)
        botPublic = try object.required("bot_public", Bool.self)
        botRequireCodeGrant = try object.required("bot_require_code_grant", Bool.self)
        verifyKey = try object.required("verify_key", String.self)
        let rawTeam = try object.resource.nullableObject("team")
        team = rawTeam
        switch rawTeam {
        case .null: teamDetails = .null
        case .value(let value): teamDetails = .value(try ApplicationTeam(value: value, limits: limits))
        }
        rpcOrigins = try object.field("rpc_origins", [String].self)
        bot = try object.messageField("bot", ApplicationUser.self)
        termsOfServiceURL = try object.field("terms_of_service_url", String.self)
        privacyPolicyURL = try object.field("privacy_policy_url", String.self)
        owner = try object.messageField("owner", ApplicationUser.self)
        guildID = try object.field("guild_id", GuildID.self)
        guild = try object.messageField("guild", ApplicationGuild.self)
        primarySKUID = try object.field("primary_sku_id", ApplicationSKUID.self)
        slug = try object.field("slug", String.self)
        coverImage = try object.field("cover_image", String.self)
        flags = try object.field("flags", UInt64.self)
        flagsNew = try object.field("flags_new", String.self)
        approximateGuildCount = try object.field("approximate_guild_count", Int.self)
        approximateUserInstallCount = try object.field("approximate_user_install_count", Int.self)
        approximateUserAuthorizationCount = try object.field("approximate_user_authorization_count", Int.self)
        redirectURIs = try object.field("redirect_uris", [String].self)
        interactionsEndpointURL = try object.field("interactions_endpoint_url", String.self, nullable: true)
        roleConnectionsVerificationURL = try object.field("role_connections_verification_url", String.self, nullable: true)
        eventWebhooksURL = try object.field("event_webhooks_url", String.self, nullable: true)
        eventWebhooksStatus = try object.field("event_webhooks_status", RawValue<ApplicationEventWebhookStatus>.self)
        eventWebhooksTypes = try object.field("event_webhooks_types", [String].self)
        tags = try object.field("tags", [String].self)
        installParams = try object.messageField("install_params", ApplicationInstallParams.self)
        integrationTypesConfig = try object.messageDictionary("integration_types_config", ApplicationIntegrationTypeConfiguration.self)
        customInstallURL = try object.field("custom_install_url", String.self)
        type = try object.field("type", RawValue<ApplicationType>.self, nullable: true)
        maxParticipants = try object.field("max_participants", Int.self, nullable: true)
        explicitContentFilter = try object.field("explicit_content_filter", RawValue<ApplicationExplicitContentFilter>.self)
        conjureProjectID = try object.field("conjure_project_id", ApplicationProjectID.self)
        vibegrationsProjectID = try object.field("vibegrations_project_id", ApplicationProjectID.self)
        eligibleOAuth2Scopes = try object.field("eligible_oauth2_scopes", [String].self)
        if case .value(let digits) = flagsNew {
            guard !digits.isEmpty, digits.utf8.allSatisfy({ (48...57).contains($0) })
            else { throw DiscordError.transport(.invalidResponse) }
        }
        rawFields = object.resource.fields
    }
}

/// An explicitly partial bot/owner User referenced by an Application; missing fields are never synthesized.
/// Further User data remains exact in rawFields and does not constitute a full User snapshot.
public struct ApplicationUser: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let id: UserID
    /// Wire `username`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let username: Field<String>
    /// Wire `discriminator`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let discriminator: Field<String>
    /// Wire `global_name`. Optional nullable wire value; omission and explicit null remain distinct.
    public let globalName: Field<String>
    /// Wire `avatar`. Optional nullable wire value; omission and explicit null remain distinct.
    public let avatar: Field<String>
    /// Wire `bot`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let bot: Field<Bool>
    /// Wire `system`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let system: Field<Bool>
    /// Wire `flags`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let flags: Field<UInt64>
    /// Wire `public_flags`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let publicFlags: Field<UInt64>
    /// Complete original object, including unknown fields and exact numeric lexemes; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete immutable API v10 snapshot under limits covering all known and unknown subtrees.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known presence, scalar types and required nested fields are validated.
    ///   - limits: Whole-document byte, depth and node limits, default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or overflowing fields. Parsing is synchronous, performs no I/O, and owns no external resources.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded immutable subtree without recursive reparsing or unrelated-resource hydration.
    /// - Parameters:
    ///   - value: Original object subtree from a successfully bounded root document.
    ///   - limits: Bounds established for that root, reused during exact scalar projection.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; unknown values retain their spelling.
    /// No suspension, resource ownership, credential access or authorization lookup occurs.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", UserID.self)
        username = try object.field("username", String.self)
        discriminator = try object.field("discriminator", String.self)
        globalName = try object.field("global_name", String.self, nullable: true)
        avatar = try object.field("avatar", String.self, nullable: true)
        bot = try object.field("bot", Bool.self)
        system = try object.field("system", Bool.self)
        flags = try object.field("flags", UInt64.self)
        publicFlags = try object.field("public_flags", UInt64.self)
        rawFields = object.resource.fields
    }
}

/// An explicitly partial associated Guild referenced by an Application, without membership or permission inference.
public struct ApplicationGuild: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let id: GuildID
    /// Wire `name`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let name: Field<String>
    /// Wire `icon`. Optional nullable wire value; omission and explicit null remain distinct.
    public let icon: Field<String>
    /// Wire `description`. Optional nullable wire value; omission and explicit null remain distinct.
    public let descriptionText: Field<String>
    /// Wire `features`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let features: Field<[String]>
    /// Complete original object, including unknown fields and exact numeric lexemes; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete immutable API v10 snapshot under limits covering all known and unknown subtrees.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known presence, scalar types and required nested fields are validated.
    ///   - limits: Whole-document byte, depth and node limits, default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or overflowing fields. Parsing is synchronous, performs no I/O, and owns no external resources.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded immutable subtree without recursive reparsing or unrelated-resource hydration.
    /// - Parameters:
    ///   - value: Original object subtree from a successfully bounded root document.
    ///   - limits: Bounds established for that root, reused during exact scalar projection.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; unknown values retain their spelling.
    /// No suspension, resource ownership, credential access or authorization lookup occurs.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", GuildID.self)
        name = try object.field("name", String.self)
        icon = try object.field("icon", String.self, nullable: true)
        descriptionText = try object.field("description", String.self, nullable: true)
        features = try object.field("features", [String].self)
        rawFields = object.resource.fields
    }
}

/// Application-owned default OAuth2 install settings; permissions are exact arbitrary-width decimal text.
/// Response scopes are forward compatible; outgoing validated settings use ApplicationInstallParamsRequest.
public struct ApplicationInstallParams: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `scopes`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let scopes: [String]
    /// Wire `permissions`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let permissions: String
    /// Complete original object, including unknown fields and exact numeric lexemes; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete immutable API v10 snapshot under limits covering all known and unknown subtrees.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known presence, scalar types and required nested fields are validated.
    ///   - limits: Whole-document byte, depth and node limits, default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or overflowing fields. Parsing is synchronous, performs no I/O, and owns no external resources.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded immutable subtree without recursive reparsing or unrelated-resource hydration.
    /// - Parameters:
    ///   - value: Original object subtree from a successfully bounded root document.
    ///   - limits: Bounds established for that root, reused during exact scalar projection.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; unknown values retain their spelling.
    /// No suspension, resource ownership, credential access or authorization lookup occurs.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        scopes = try object.required("scopes", [String].self)
        permissions = try object.required("permissions", String.self)
        guard !permissions.isEmpty, permissions.utf8.allSatisfy({ (48...57).contains($0) })
        else { throw DiscordError.transport(.invalidResponse) }
        rawFields = object.resource.fields
    }
}

/// Application-owned installation-context configuration; absent OAuth2 parameters do not mean disabled context.
public struct ApplicationIntegrationTypeConfiguration: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `oauth2_install_params`. Optional nested projection preserving absence.
    public let oauth2InstallParams: Field<ApplicationInstallParams>
    /// Complete original object, including unknown fields and exact numeric lexemes; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete immutable API v10 snapshot under limits covering all known and unknown subtrees.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known presence, scalar types and required nested fields are validated.
    ///   - limits: Whole-document byte, depth and node limits, default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or overflowing fields. Parsing is synchronous, performs no I/O, and owns no external resources.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded immutable subtree without recursive reparsing or unrelated-resource hydration.
    /// - Parameters:
    ///   - value: Original object subtree from a successfully bounded root document.
    ///   - limits: Bounds established for that root, reused during exact scalar projection.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; unknown values retain their spelling.
    /// No suspension, resource ownership, credential access or authorization lookup occurs.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        oauth2InstallParams = try object.messageField("oauth2_install_params", ApplicationInstallParams.self)
        rawFields = object.resource.fields
    }
}

/// Complete developer-team fields owned by the Application response; no team-management HTTP operations are implied.
public struct ApplicationTeam: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let id: ApplicationTeamID
    /// Wire `icon`. Required nullable icon hash; explicit null means no team icon is set.
    public let icon: Nullable<String>
    /// Wire `name`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let name: String
    /// Wire `owner_user_id`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let ownerUserID: UserID
    /// Wire `members`. Ordered nested projections; all entries are validated and unknown fields are retained.
    public let members: [ApplicationTeamMember]
    /// Complete original object, including unknown fields and exact numeric lexemes; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete immutable API v10 snapshot under limits covering all known and unknown subtrees.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known presence, scalar types and required nested fields are validated.
    ///   - limits: Whole-document byte, depth and node limits, default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or overflowing fields. Parsing is synchronous, performs no I/O, and owns no external resources.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded immutable subtree without recursive reparsing or unrelated-resource hydration.
    /// - Parameters:
    ///   - value: Original object subtree from a successfully bounded root document.
    ///   - limits: Bounds established for that root, reused during exact scalar projection.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; unknown values retain their spelling.
    /// No suspension, resource ownership, credential access or authorization lookup occurs.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ApplicationTeamID.self)
        icon = try object.required("icon", Nullable<String>.self)
        name = try object.required("name", String.self)
        ownerUserID = try object.required("owner_user_id", UserID.self)
        members = try object.messageModels("members", ApplicationTeamMember.self)
        rawFields = object.resource.fields
    }
}

/// Developer-team member; role is optional for compatibility with the written Application example.
/// Legacy permissions are retained when supplied; the current Team reference defines roles and ownerUserID.
public struct ApplicationTeamMember: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `membership_state`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let membershipState: RawValue<ApplicationTeamMembershipState>
    /// Wire `team_id`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let teamID: ApplicationTeamID
    /// Wire `user`. Required nested projection preserving unknown fields.
    public let user: MessageAuthor
    /// Wire `role`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let role: Field<RawValue<ApplicationTeamRole>>
    /// Wire `permissions`. Optional nonnull wire value; omission remains distinct from an empty value.
    public let permissions: Field<[String]>
    /// Complete original object, including unknown fields and exact numeric lexemes; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete immutable API v10 snapshot under limits covering all known and unknown subtrees.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known presence, scalar types and required nested fields are validated.
    ///   - limits: Whole-document byte, depth and node limits, default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or overflowing fields. Parsing is synchronous, performs no I/O, and owns no external resources.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded immutable subtree without recursive reparsing or unrelated-resource hydration.
    /// - Parameters:
    ///   - value: Original object subtree from a successfully bounded root document.
    ///   - limits: Bounds established for that root, reused during exact scalar projection.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; unknown values retain their spelling.
    /// No suspension, resource ownership, credential access or authorization lookup occurs.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        membershipState = try object.required("membership_state", RawValue<ApplicationTeamMembershipState>.self)
        teamID = try object.required("team_id", ApplicationTeamID.self)
        user = try object.messageModel("user", MessageAuthor.self)
        role = try object.field("role", RawValue<ApplicationTeamRole>.self)
        permissions = try object.field("permissions", [String].self)
        rawFields = object.resource.fields
    }
}

/// Complete serialized Application activity instance; this finite response neither connects a user nor starts an activity.
/// launchID follows the written snowflake contract even though the OpenAPI preview weakens it to an arbitrary string.
public struct ApplicationActivityInstance: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `application_id`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let applicationID: ApplicationID
    /// Wire `instance_id`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let instanceID: String
    /// Wire `launch_id`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let launchID: ApplicationActivityLaunchID
    /// Wire `location`. Required nested projection preserving unknown fields.
    public let location: ApplicationActivityLocation
    /// Wire `users`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let users: [UserID]
    /// Complete original object, including unknown fields and exact numeric lexemes; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete immutable API v10 snapshot under limits covering all known and unknown subtrees.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known presence, scalar types and required nested fields are validated.
    ///   - limits: Whole-document byte, depth and node limits, default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or overflowing fields. Parsing is synchronous, performs no I/O, and owns no external resources.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded immutable subtree without recursive reparsing or unrelated-resource hydration.
    /// - Parameters:
    ///   - value: Original object subtree from a successfully bounded root document.
    ///   - limits: Bounds established for that root, reused during exact scalar projection.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; unknown values retain their spelling.
    /// No suspension, resource ownership, credential access or authorization lookup occurs.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        applicationID = try object.required("application_id", ApplicationID.self)
        instanceID = try object.required("instance_id", String.self)
        launchID = try object.required("launch_id", ApplicationActivityLaunchID.self)
        location = try object.messageModel("location", ApplicationActivityLocation.self)
        users = try object.required("users", [UserID].self)
        rawFields = object.resource.fields
    }
}

/// Activity location with forward-compatible kinds and optional nullable guild context from the written reference.
/// Unknown location-kind semantics are preserved; a channel ID does not establish channel visibility or membership.
public struct ApplicationActivityLocation: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Wire `id`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let id: String
    /// Wire `kind`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let kind: RawValue<ApplicationActivityLocationKind>
    /// Wire `channel_id`. Required, nonnull wire value; exact unknown sibling fields remain available.
    public let channelID: ChannelID
    /// Wire `guild_id`. Optional nullable wire value; omission and explicit null remain distinct.
    public let guildID: Field<GuildID>
    /// Complete original object, including unknown fields and exact numeric lexemes; diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses a complete immutable API v10 snapshot under limits covering all known and unknown subtrees.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known presence, scalar types and required nested fields are validated.
    ///   - limits: Whole-document byte, depth and node limits, default 1 MiB/64/100,000.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for missing, forbidden-null,
    ///   malformed or overflowing fields. Parsing is synchronous, performs no I/O, and owns no external resources.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded immutable subtree without recursive reparsing or unrelated-resource hydration.
    /// - Parameters:
    ///   - value: Original object subtree from a successfully bounded root document.
    ///   - limits: Bounds established for that root, reused during exact scalar projection.
    /// - Throws: Sanitized invalid-response errors for incompatible known fields; unknown values retain their spelling.
    /// No suspension, resource ownership, credential access or authorization lookup occurs.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", String.self)
        kind = try object.required("kind", RawValue<ApplicationActivityLocationKind>.self)
        channelID = try object.required("channel_id", ChannelID.self)
        guildID = try object.field("guild_id", GuildID.self, nullable: true)
        rawFields = object.resource.fields
    }
}
