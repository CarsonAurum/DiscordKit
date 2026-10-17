import DiscordCore
import Foundation

/// Marker for role, user, channel and documented guild-derived permission constants.
public enum ApplicationCommandPermissionTargetTag: Sendable {}
/// Exact 64-bit permission target. The @everyone constant equals guild_id; all channels equals guild_id - 1.
public typealias ApplicationCommandPermissionTargetID = Snowflake<ApplicationCommandPermissionTargetTag>

/// Complete written API v10 ApplicationCommand projection with localized preview fields, verified 2026-10-16.
/// Unknown fields/enum values survive; parsing does not establish current permissions or registration state.
/// Source: https://docs.discord.com/developers/interactions/application-commands.
public struct ApplicationCommand: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact `id` wire projection; omission and permitted null remain distinct where applicable.
    public let id: ApplicationCommandID
    /// Exact `type` wire projection; omission and permitted null remain distinct where applicable.
    public let type: Field<RawValue<ApplicationCommandType>>
    /// Exact `application_id` wire projection; omission and permitted null remain distinct where applicable.
    public let applicationID: ApplicationID
    /// Exact `guild_id` wire projection; omission and permitted null remain distinct where applicable.
    public let guildID: Field<GuildID>
    /// Exact `name` wire projection; omission and permitted null remain distinct where applicable.
    public let name: String
    /// Exact `name_localizations` wire projection; omission and permitted null remain distinct where applicable.
    public let nameLocalizations: Field<[String: String]>
    /// Exact `name_localized` wire projection; omission and permitted null remain distinct where applicable.
    public let nameLocalized: Field<String>
    /// Exact `description` wire projection; omission and permitted null remain distinct where applicable.
    public let commandDescription: String
    /// Exact `description_localizations` wire projection; omission and permitted null remain distinct where applicable.
    public let descriptionLocalizations: Field<[String: String]>
    /// Exact `description_localized` wire projection; omission and permitted null remain distinct where applicable.
    public let descriptionLocalized: Field<String>
    /// Exact `options` wire projection; omission and permitted null remain distinct where applicable.
    public let options: Field<[ApplicationCommandOption]>
    /// Exact `default_member_permissions` wire projection; omission and permitted null remain distinct where applicable.
    public let defaultMemberPermissions: Nullable<String>
    /// Exact `dm_permission` wire projection; omission and permitted null remain distinct where applicable.
    public let dmPermission: Field<Bool>
    /// Exact `default_permission` wire projection; omission and permitted null remain distinct where applicable.
    public let defaultPermission: Field<Bool>
    /// Exact `nsfw` wire projection; omission and permitted null remain distinct where applicable.
    public let nsfw: Field<Bool>
    /// Exact `integration_types` wire projection; omission and permitted null remain distinct where applicable.
    public let integrationTypes: Field<[RawValue<ApplicationIntegrationType>]>
    /// Exact `contexts` wire projection; omission and permitted null remain distinct where applicable.
    public let contexts: Field<[RawValue<InteractionContextType>]>
    /// Exact `version` wire projection; omission and permitted null remain distinct where applicable.
    public let version: ApplicationCommandID
    /// Exact `handler` wire projection; omission and permitted null remain distinct where applicable.
    public let handler: Field<RawValue<ApplicationCommandHandler>>
    /// Complete original fields, including future values and exact numeric spellings; ordinary diagnostics redact them.
    public let rawFields: [String: JSONValue]

    /// Parses one bounded complete object synchronously without I/O, tasks or hydration.
    /// - Parameters:
    ///   - data: UTF-8 JSON object; duplicate keys and trailing documents are rejected.
    ///   - limits: Complete-document bytes/depth/nodes, default 1 MiB/64/100,000, including unknown subtrees.
    /// - Throws: JSON syntax/bounds or sanitized invalid-response errors for missing, null or mistyped known fields.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree after the containing document has passed all parser limits.
    /// - Parameters:
    ///   - value: Original bounded object; response-only combinations and future values are retained.
    ///   - limits: The containing document's bounds, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for incompatible fields; no mutation constraints are imposed.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ApplicationCommandID.self)
        type = try object.field("type", RawValue<ApplicationCommandType>.self)
        applicationID = try object.required("application_id", ApplicationID.self)
        guildID = try object.field("guild_id", GuildID.self)
        name = try object.required("name", String.self)
        nameLocalizations = try object.field("name_localizations", [String: String].self, nullable: true)
        nameLocalized = try object.field("name_localized", String.self)
        commandDescription = try object.required("description", String.self)
        descriptionLocalizations = try object.field("description_localizations", [String: String].self, nullable: true)
        descriptionLocalized = try object.field("description_localized", String.self)
        options = try object.messageArray("options", ApplicationCommandOption.self)
        defaultMemberPermissions = try object.required("default_member_permissions", Nullable<String>.self)
        dmPermission = try object.field("dm_permission", Bool.self)
        defaultPermission = try object.field("default_permission", Bool.self, nullable: true)
        nsfw = try object.field("nsfw", Bool.self)
        integrationTypes = try object.field("integration_types", [RawValue<ApplicationIntegrationType>].self)
        contexts = try object.field("contexts", [RawValue<InteractionContextType>].self, nullable: true)
        version = try object.required("version", ApplicationCommandID.self)
        handler = try object.field("handler", RawValue<ApplicationCommandHandler>.self)
        rawFields = object.resource.fields
    }
}

/// Complete written API v10 ApplicationCommandOption projection with localized preview fields, verified 2026-10-16.
/// Unknown fields/enum values survive; parsing does not establish current permissions or registration state.
/// Source: https://docs.discord.com/developers/interactions/application-commands.
public struct ApplicationCommandOption: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact `type` wire projection; omission and permitted null remain distinct where applicable.
    public let type: RawValue<ApplicationCommandOptionType>
    /// Exact `name` wire projection; omission and permitted null remain distinct where applicable.
    public let name: String
    /// Exact `name_localizations` wire projection; omission and permitted null remain distinct where applicable.
    public let nameLocalizations: Field<[String: String]>
    /// Exact `name_localized` wire projection; omission and permitted null remain distinct where applicable.
    public let nameLocalized: Field<String>
    /// Exact `description` wire projection; omission and permitted null remain distinct where applicable.
    public let optionDescription: String
    /// Exact `description_localizations` wire projection; omission and permitted null remain distinct where applicable.
    public let descriptionLocalizations: Field<[String: String]>
    /// Exact `description_localized` wire projection; omission and permitted null remain distinct where applicable.
    public let descriptionLocalized: Field<String>
    /// Exact `required` wire projection; omission and permitted null remain distinct where applicable.
    public let required: Field<Bool>
    /// Exact `choices` wire projection; omission and permitted null remain distinct where applicable.
    public let choices: Field<[ApplicationCommandChoice]>
    /// Exact `options` wire projection; omission and permitted null remain distinct where applicable.
    public let options: Field<[ApplicationCommandOption]>
    /// Exact `channel_types` wire projection; omission and permitted null remain distinct where applicable.
    public let channelTypes: Field<[RawValue<ChannelType>]>
    /// Exact `min_value` wire projection; omission and permitted null remain distinct where applicable.
    public let minValue: Field<JSONNumber>
    /// Exact `max_value` wire projection; omission and permitted null remain distinct where applicable.
    public let maxValue: Field<JSONNumber>
    /// Exact `min_length` wire projection; omission and permitted null remain distinct where applicable.
    public let minLength: Field<Int>
    /// Exact `max_length` wire projection; omission and permitted null remain distinct where applicable.
    public let maxLength: Field<Int>
    /// Exact `autocomplete` wire projection; omission and permitted null remain distinct where applicable.
    public let autocomplete: Field<Bool>
    /// Exact `file_types` wire projection; omission and permitted null remain distinct where applicable.
    public let fileTypes: Field<[String]>
    /// Complete original fields, including future values and exact numeric spellings; ordinary diagnostics redact them.
    public let rawFields: [String: JSONValue]

    /// Parses one bounded complete object synchronously without I/O, tasks or hydration.
    /// - Parameters:
    ///   - data: UTF-8 JSON object; duplicate keys and trailing documents are rejected.
    ///   - limits: Complete-document bytes/depth/nodes, default 1 MiB/64/100,000, including unknown subtrees.
    /// - Throws: JSON syntax/bounds or sanitized invalid-response errors for missing, null or mistyped known fields.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree after the containing document has passed all parser limits.
    /// - Parameters:
    ///   - value: Original bounded object; response-only combinations and future values are retained.
    ///   - limits: The containing document's bounds, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for incompatible fields; no mutation constraints are imposed.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        type = try object.required("type", RawValue<ApplicationCommandOptionType>.self)
        name = try object.required("name", String.self)
        nameLocalizations = try object.field("name_localizations", [String: String].self, nullable: true)
        nameLocalized = try object.field("name_localized", String.self)
        optionDescription = try object.required("description", String.self)
        descriptionLocalizations = try object.field("description_localizations", [String: String].self, nullable: true)
        descriptionLocalized = try object.field("description_localized", String.self)
        required = try object.field("required", Bool.self)
        choices = try object.messageArray("choices", ApplicationCommandChoice.self)
        options = try object.messageArray("options", ApplicationCommandOption.self)
        channelTypes = try object.field("channel_types", [RawValue<ChannelType>].self)
        minValue = try object.nested("min_value") { value in
            guard case .number(let number) = value else { throw DiscordError.transport(.invalidResponse) }
            return number
        }
        maxValue = try object.nested("max_value") { value in
            guard case .number(let number) = value else { throw DiscordError.transport(.invalidResponse) }
            return number
        }
        minLength = try object.field("min_length", Int.self)
        maxLength = try object.field("max_length", Int.self)
        autocomplete = try object.field("autocomplete", Bool.self)
        fileTypes = try object.field("file_types", [String].self)
        rawFields = object.resource.fields
    }
}

/// Complete written API v10 ApplicationCommandChoice projection with localized preview fields, verified 2026-10-16.
/// Unknown fields/enum values survive; parsing does not establish current permissions or registration state.
/// Source: https://docs.discord.com/developers/interactions/application-commands.
public struct ApplicationCommandChoice: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact `name` wire projection; omission and permitted null remain distinct where applicable.
    public let name: String
    /// Exact `name_localizations` wire projection; omission and permitted null remain distinct where applicable.
    public let nameLocalizations: Field<[String: String]>
    /// Exact `name_localized` wire projection; omission and permitted null remain distinct where applicable.
    public let nameLocalized: Field<String>
    /// Exact `value` wire projection; omission and permitted null remain distinct where applicable.
    public let value: ApplicationCommandChoiceValue
    /// Complete original fields, including future values and exact numeric spellings; ordinary diagnostics redact them.
    public let rawFields: [String: JSONValue]

    /// Parses one bounded complete object synchronously without I/O, tasks or hydration.
    /// - Parameters:
    ///   - data: UTF-8 JSON object; duplicate keys and trailing documents are rejected.
    ///   - limits: Complete-document bytes/depth/nodes, default 1 MiB/64/100,000, including unknown subtrees.
    /// - Throws: JSON syntax/bounds or sanitized invalid-response errors for missing, null or mistyped known fields.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree after the containing document has passed all parser limits.
    /// - Parameters:
    ///   - value: Original bounded object; response-only combinations and future values are retained.
    ///   - limits: The containing document's bounds, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for incompatible fields; no mutation constraints are imposed.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        name = try object.required("name", String.self)
        nameLocalizations = try object.field("name_localizations", [String: String].self, nullable: true)
        nameLocalized = try object.field("name_localized", String.self)
        self.value = try ApplicationCommandChoiceValue(value: object.resource.fields["value"] ?? .null)
        rawFields = object.resource.fields
    }
}

/// Complete written API v10 ApplicationCommandPermission projection with localized preview fields, verified 2026-10-16.
/// Unknown fields/enum values survive; parsing does not establish current permissions or registration state.
/// Source: https://docs.discord.com/developers/interactions/application-commands.
public struct ApplicationCommandPermission: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact `id` wire projection; omission and permitted null remain distinct where applicable.
    public let id: ApplicationCommandPermissionTargetID
    /// Exact `type` wire projection; omission and permitted null remain distinct where applicable.
    public let type: RawValue<ApplicationCommandPermissionType>
    /// Exact `permission` wire projection; omission and permitted null remain distinct where applicable.
    public let permission: Bool
    /// Complete original fields, including future values and exact numeric spellings; ordinary diagnostics redact them.
    public let rawFields: [String: JSONValue]

    /// Parses one bounded complete object synchronously without I/O, tasks or hydration.
    /// - Parameters:
    ///   - data: UTF-8 JSON object; duplicate keys and trailing documents are rejected.
    ///   - limits: Complete-document bytes/depth/nodes, default 1 MiB/64/100,000, including unknown subtrees.
    /// - Throws: JSON syntax/bounds or sanitized invalid-response errors for missing, null or mistyped known fields.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree after the containing document has passed all parser limits.
    /// - Parameters:
    ///   - value: Original bounded object; response-only combinations and future values are retained.
    ///   - limits: The containing document's bounds, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for incompatible fields; no mutation constraints are imposed.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ApplicationCommandPermissionTargetID.self)
        type = try object.required("type", RawValue<ApplicationCommandPermissionType>.self)
        permission = try object.required("permission", Bool.self)
        rawFields = object.resource.fields
    }
}

/// Complete written API v10 GuildApplicationCommandPermissions projection with localized preview fields, verified 2026-10-16.
/// Unknown fields/enum values survive; parsing does not establish current permissions or registration state.
/// Source: https://docs.discord.com/developers/interactions/application-commands.
public struct GuildApplicationCommandPermissions: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact `id` wire projection; omission and permitted null remain distinct where applicable.
    public let id: ApplicationCommandID
    /// Exact `application_id` wire projection; omission and permitted null remain distinct where applicable.
    public let applicationID: ApplicationID
    /// Exact `guild_id` wire projection; omission and permitted null remain distinct where applicable.
    public let guildID: GuildID
    /// Exact `permissions` wire projection; omission and permitted null remain distinct where applicable.
    public let permissions: [ApplicationCommandPermission]
    /// Complete original fields, including future values and exact numeric spellings; ordinary diagnostics redact them.
    public let rawFields: [String: JSONValue]

    /// Parses one bounded complete object synchronously without I/O, tasks or hydration.
    /// - Parameters:
    ///   - data: UTF-8 JSON object; duplicate keys and trailing documents are rejected.
    ///   - limits: Complete-document bytes/depth/nodes, default 1 MiB/64/100,000, including unknown subtrees.
    /// - Throws: JSON syntax/bounds or sanitized invalid-response errors for missing, null or mistyped known fields.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree after the containing document has passed all parser limits.
    /// - Parameters:
    ///   - value: Original bounded object; response-only combinations and future values are retained.
    ///   - limits: The containing document's bounds, reused for exact scalar decoding.
    /// - Throws: Sanitized invalid-response errors for incompatible fields; no mutation constraints are imposed.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ApplicationCommandID.self)
        applicationID = try object.required("application_id", ApplicationID.self)
        guildID = try object.required("guild_id", GuildID.self)
        permissions = try object.messageModels("permissions", ApplicationCommandPermission.self)
        rawFields = object.resource.fields
    }
}
