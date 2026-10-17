import DiscordCore
import Foundation

/// Interaction identifiers share the existing message-interaction snowflake domain.
public typealias InteractionID = MessageInteractionID
/// Marker for user/message targets selected by a context-menu command.
public enum InteractionTargetTag: Sendable {}
/// Exact context-menu target identifier; its user/message domain is determined by command type.
public typealias InteractionTargetID = Snowflake<InteractionTargetTag>

/// API v10 incoming interaction kinds; response wrappers retain future integral values.
public enum InteractionType: Int, Sendable, CaseIterable {
    case ping = 1, applicationCommand = 2, messageComponent = 3, applicationCommandAutocomplete = 4, modalSubmit = 5
}

/// API v10 callback kinds, including the deprecated premium-required response.
public enum InteractionCallbackType: Int, Sendable, CaseIterable {
    case pong = 1, channelMessageWithSource = 4, deferredChannelMessageWithSource = 5
    case deferredUpdateMessage = 6, updateMessage = 7, applicationCommandAutocompleteResult = 8
    case modal = 9
    /// Deprecated by Discord; use premium-style message buttons for purchases instead.
    @available(*, deprecated, message: "Use premium-style message buttons instead of the premium-required callback.")
    case premiumRequired = 10
    case launchActivity = 12

    /// Every written callback kind in ascending wire order, including the deprecated premium-required kind.
    /// Explicit enumeration preserves complete wire-value discovery when a deprecated case prevents synthesis;
    /// callers should use premium-style message buttons instead of constructing the deprecated callback.
    public static let allCases: [Self] = [.pong, .channelMessageWithSource, .deferredChannelMessageWithSource,
        .deferredUpdateMessage, .updateMessage, .applicationCommandAutocompleteResult, .modal, .premiumRequired,
        .launchActivity]
}

/// Partial resources resolved by an interaction. Partial messages/members/channels deliberately
/// retain their complete exact objects instead of requiring unrelated full-resource fields.
public struct InteractionResolvedData: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let users: Field<[String: MessageAuthor]>
    public let members: Field<[String: MessageRelatedResource]>
    public let roles: Field<[String: MessageRelatedResource]>
    public let channels: Field<[String: MessageRelatedResource]>
    public let messages: Field<[String: MessageRelatedResource]>
    public let attachments: Field<[String: MessageAttachment]>
    public let rawFields: [String: JSONValue]

    /// Parses one bounded resolved-data dictionary without fetching related resources.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; known maps require decimal snowflake keys and typed values.
    ///   - limits: Whole-document byte, depth and node limits, including unknown values.
    /// - Throws: JSON bounds/syntax or sanitized schema errors for malformed known dictionaries.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a bounded subtree, preserving partial resource fields and unknown dictionary categories.
    /// - Parameters:
    ///   - value: Object from the already bounded outer document.
    ///   - limits: Bounds applied at that document root.
    /// - Throws: Sanitized invalid-response errors for incompatible known values or map keys.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        users = try object.messageDictionary("users", MessageAuthor.self)
        members = try object.messageDictionary("members", MessageRelatedResource.self)
        roles = try object.messageDictionary("roles", MessageRelatedResource.self)
        channels = try object.messageDictionary("channels", MessageRelatedResource.self)
        messages = try object.messageDictionary("messages", MessageRelatedResource.self)
        attachments = try object.messageDictionary("attachments", MessageAttachment.self)
        rawFields = object.resource.fields
    }
}

/// One recursive application-command argument, preserving exact numeric values and autocomplete focus.
public struct InteractionCommandOption: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let name: String
    public let type: RawValue<ApplicationCommandOptionType>
    public let value: Field<JSONValue>
    public let options: Field<[InteractionCommandOption]>
    public let focused: Field<Bool>
    public let rawFields: [String: JSONValue]

    /// Parses an argument tree within a single bounded document, without coercing numeric strings.
    /// - Parameters:
    ///   - data: Complete option object with required name/type.
    ///   - limits: Complete-tree byte/depth/node limits; recursion is bounded by the parser.
    /// - Throws: JSON syntax/bounds or sanitized errors for malformed known scalar/container fields.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a bounded option and enforces mutually exclusive argument/subcommand forms.
    /// - Parameters:
    ///   - value: Original object from an already bounded tree.
    ///   - limits: Root-document limits reused by exact scalar decoding.
    /// - Throws: Invalid-response for simultaneous value/options or a mismatched known argument scalar.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        name = try object.required("name", String.self)
        type = try object.required("type", RawValue<ApplicationCommandOptionType>.self)
        self.value = try object.nested("value") { scalar in
            switch scalar {
            case .string, .number, .bool: return scalar
            default: throw DiscordError.transport(.invalidResponse)
            }
        }
        options = try object.messageArray("options", InteractionCommandOption.self)
        focused = try object.field("focused", Bool.self)
        if case .value = self.value, case .value = options { throw DiscordError.transport(.invalidResponse) }
        if case .value(let scalar) = self.value, let kind = type.knownValue {
            switch (kind, scalar) {
            case (.string, .string), (.boolean, .bool), (.number, .number): break
            case (.user, .string(let identifier)), (.channel, .string(let identifier)), (.role, .string(let identifier)),
                 (.mentionable, .string(let identifier)), (.attachment, .string(let identifier)):
                guard !identifier.isEmpty, identifier.utf8.allSatisfy({ (48...57).contains($0) }), UInt64(identifier) != nil
                else { throw DiscordError.transport(.invalidResponse) }
            case (.integer, .number(let number)):
                guard !number.rawValue.contains("."), !number.rawValue.lowercased().contains("e")
                else { throw DiscordError.transport(.invalidResponse) }
            default: throw DiscordError.transport(.invalidResponse)
            }
        }
        rawFields = object.resource.fields
    }
}

/// Variant-aware interaction data. Unknown outer kinds retain their uninterpreted exact object.
public enum InteractionData: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case command(InteractionCommandData)
    case component(InteractionComponentData)
    case modal(InteractionModalData)
    case unknown(JSONValue)

    /// Conceals submitted values and unknown payload fields from ordinary formatting.
    public var description: String { "InteractionData(redacted)" }
    /// Uses the same safe marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflective traversal from exposing retained user input.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Invoked command identity, optional partial autocomplete arguments and resolved target resources.
public struct InteractionCommandData: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let id: ApplicationCommandID
    public let name: String
    public let type: RawValue<ApplicationCommandType>
    public let resolved: Field<InteractionResolvedData>
    public let options: Field<[InteractionCommandOption]>
    public let guildID: Field<GuildID>
    /// Decimal target ID, preserving the command's user/message target domain distinction externally.
    public let targetID: Field<InteractionTargetID>
    public let rawFields: [String: JSONValue]

    /// Parses one command-data object without command lookup, option completion or hydration.
    /// - Parameters:
    ///   - data: Complete command-data JSON, including partial autocomplete options.
    ///   - limits: Whole-document byte/depth/node bounds.
    /// - Throws: JSON bounds/syntax or sanitized invalid-response errors for malformed known fields.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one previously bounded command subtree and retains future command/option values.
    /// - Parameters:
    ///   - value: Exact bounded object.
    ///   - limits: Bounds established at the complete document root.
    /// - Throws: Sanitized schema errors for absent required identity/name/type or malformed children.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", ApplicationCommandID.self)
        name = try object.required("name", String.self)
        type = try object.required("type", RawValue<ApplicationCommandType>.self)
        resolved = try object.messageField("resolved", InteractionResolvedData.self)
        options = try object.messageArray("options", InteractionCommandOption.self)
        guildID = try object.field("guild_id", GuildID.self)
        targetID = try object.field("target_id", InteractionTargetID.self)
        rawFields = object.resource.fields
    }
}

/// Message-component input, preserving unknown component kinds and exact resolved resource dictionaries.
public struct InteractionComponentData: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let customID: String
    public let componentType: RawValue<ComponentType>
    public let id: Field<UInt32>
    public let values: Field<[String]>
    public let resolved: Field<InteractionResolvedData>
    public let rawFields: [String: JSONValue]

    /// Parses component input without executing handlers or trusting retained permissions.
    /// - Parameters:
    ///   - data: Complete UTF-8 object, including custom_id/component_type.
    ///   - limits: Bounds covering the complete object and unknown nested fields.
    /// - Throws: JSON syntax/bounds or sanitized malformed-field errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects bounded input and requires the selected-value array for documented select kinds.
    /// - Parameters:
    ///   - value: Original bounded component-data object.
    ///   - limits: Root-document parser limits.
    /// - Throws: Invalid-response for missing identity/type, malformed fields or missing select values.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        customID = try object.required("custom_id", String.self)
        componentType = try object.required("component_type", RawValue<ComponentType>.self)
        id = try object.field("id", UInt32.self)
        values = try object.field("values", [String].self)
        resolved = try object.messageField("resolved", InteractionResolvedData.self)
        if [3, 5, 6, 7, 8].contains(componentType.rawValue), case .absent = values {
            throw DiscordError.transport(.invalidResponse)
        }
        rawFields = object.resource.fields
    }
}

/// Submitted modal values, including labels, file uploads, selects, radio and checkbox components.
public struct InteractionModalData: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let customID: String
    public let components: [MessageComponent]
    public let resolved: Field<InteractionResolvedData>
    public let rawFields: [String: JSONValue]

    /// Parses a complete modal submission without applying outgoing-definition requirements to input.
    /// - Parameters:
    ///   - data: Complete UTF-8 modal-data object; partial child components are supported.
    ///   - limits: Complete-document byte/depth/node bounds.
    /// - Throws: JSON syntax/bounds or sanitized malformed-field/child-component errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects already bounded submitted values without copying/reparsing each child tree.
    /// - Parameters:
    ///   - value: Exact bounded object containing custom_id/components.
    ///   - limits: Root-document parser limits.
    /// - Throws: Invalid-response for missing required fields, forbidden nulls or malformed known components.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        customID = try object.required("custom_id", String.self)
        components = try object.messageModels("components", MessageComponent.self)
        resolved = try object.messageField("resolved", InteractionResolvedData.self)
        rawFields = object.resource.fields
    }
}

/// An API v10 interaction snapshot; it performs no signature verification, ingress routing or acknowledgement.
/// Initial callbacks must reach Discord within three seconds; continuation tokens expire after fifteen minutes.
/// Applications own those deadlines and must use an interaction-scoped HTTP client; never log rawFields/token.
public struct Interaction: MessageResponseValue, MessageTreeProjectable {
    public let id: InteractionID
    public let applicationID: ApplicationID
    public let type: RawValue<InteractionType>
    public let data: Field<InteractionData>
    public let guild: Field<MessageRelatedResource>
    public let guildID: Field<GuildID>
    public let channel: Field<MessageRelatedResource>
    public let channelID: Field<ChannelID>
    public let member: Field<MessageRelatedResource>
    public let user: Field<MessageAuthor>
    public let token: InteractionToken
    public let version: Int
    public let message: Field<Message>
    public let appPermissions: Field<String>
    public let locale: Field<String>
    public let guildLocale: Field<String>
    public let entitlements: Field<[MessageRelatedResource]>
    public let authorizingIntegrationOwners: Field<[String: String]>
    public let context: Field<RawValue<InteractionContextType>>
    public let attachmentSizeLimit: Field<Int>
    public let rawFields: [String: JSONValue]

    /// Parses one complete interaction under explicit bounds without any network, deadline timer or signature check.
    /// - Parameters:
    ///   - data: Complete JSON from a previously authenticated ingress or trusted Gateway dispatch.
    ///   - limits: Complete document byte/depth/node bounds, including unknown fields and nested data.
    /// - Throws: JSON syntax/bounds or sanitized invalid-response errors; malformed token diagnostics stay redacted.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects variant-specific input while preserving future interaction kinds and minimal PING payloads.
    /// - Parameters:
    ///   - value: Complete bounded original interaction object.
    ///   - limits: Bounds established at the original document root.
    /// - Throws: Invalid-response for malformed required fields, wrong version, known non-PING interactions without
    ///   data or required context metadata, invalid permissions/owner snowflakes, negative attachment limits or
    ///   malformed optional fields. Minimal PING and future kinds may omit contextual metadata. No I/O occurs.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", InteractionID.self)
        applicationID = try object.required("application_id", ApplicationID.self)
        let kind = try object.required("type", RawValue<InteractionType>.self)
        type = kind
        data = try object.nested("data") { subtree in
            switch kind.knownValue {
            case .applicationCommand, .applicationCommandAutocomplete: return .command(try InteractionCommandData(value: subtree, limits: limits))
            case .messageComponent: return .component(try InteractionComponentData(value: subtree, limits: limits))
            case .modalSubmit: return .modal(try InteractionModalData(value: subtree, limits: limits))
            default:
                guard case .object = subtree else { throw DiscordError.transport(.invalidResponse) }
                return .unknown(subtree)
            }
        }
        if let known = kind.knownValue, known != .ping, case .absent = data { throw DiscordError.transport(.invalidResponse) }
        guild = try object.messageField("guild", MessageRelatedResource.self)
        guildID = try object.field("guild_id", GuildID.self)
        channel = try object.messageField("channel", MessageRelatedResource.self)
        channelID = try object.field("channel_id", ChannelID.self)
        member = try object.messageField("member", MessageRelatedResource.self)
        user = try object.messageField("user", MessageAuthor.self)
        do { token = try InteractionToken(object.required("token", String.self)) }
        catch { throw DiscordError.transport(.invalidResponse) }
        version = try object.required("version", Int.self)
        guard version == 1 else { throw DiscordError.transport(.invalidResponse) }
        message = try object.messageField("message", Message.self)
        appPermissions = try object.field("app_permissions", String.self)
        if case .value(let permissions) = appPermissions {
            guard !permissions.isEmpty, permissions.utf8.allSatisfy({ (48...57).contains($0) })
            else { throw DiscordError.transport(.invalidResponse) }
        }
        locale = try object.field("locale", String.self)
        guildLocale = try object.field("guild_locale", String.self)
        entitlements = try object.messageArray("entitlements", MessageRelatedResource.self)
        authorizingIntegrationOwners = try object.field("authorizing_integration_owners", [String: String].self)
        if case .value(let owners) = authorizingIntegrationOwners {
            guard owners.values.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy({ (48...57).contains($0) }) && UInt64($0) != nil })
            else { throw DiscordError.transport(.invalidResponse) }
        }
        context = try object.field("context", RawValue<InteractionContextType>.self)
        attachmentSizeLimit = try object.field("attachment_size_limit", Int.self)
        if case .value(let count) = attachmentSizeLimit, count < 0 { throw DiscordError.transport(.invalidResponse) }
        if let known = kind.knownValue, known != .ping {
            guard case .value = appPermissions, case .value = entitlements,
                  case .value = authorizingIntegrationOwners, case .value = attachmentSizeLimit
            else { throw DiscordError.transport(.invalidResponse) }
        }
        rawFields = object.resource.fields
    }
}

/// Metadata returned by with_response=true callbacks; it is distinct from the incoming Interaction object.
public struct InteractionCallback: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let id: InteractionID
    public let type: RawValue<InteractionType>
    public let activityInstanceID: Field<String>
    public let responseMessageID: Field<MessageID>
    public let responseMessageLoading: Field<Bool>
    public let responseMessageEphemeral: Field<Bool>
    /// Additional callback context documented by the official API v10 OpenAPI preview.
    public let channelID: Field<ChannelID>
    /// Additional optional callback guild context from the official API v10 OpenAPI preview.
    public let guildID: Field<GuildID>
    public let rawFields: [String: JSONValue]

    /// Parses callback metadata under complete-object bounds without fetching its response resource.
    /// - Parameters:
    ///   - data: Complete JSON callback object.
    ///   - limits: Whole-document parser bounds.
    /// - Throws: JSON bounds/syntax or sanitized invalid-response errors for malformed known fields.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a bounded callback metadata subtree, preserving future interaction types.
    /// - Parameters:
    ///   - value: Exact bounded object.
    ///   - limits: Bounds established by the complete document.
    /// - Throws: Invalid-response for missing identity/type, forbidden null or wrong optional field types.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", InteractionID.self)
        type = try object.required("type", RawValue<InteractionType>.self)
        activityInstanceID = try object.field("activity_instance_id", String.self, nullable: true)
        responseMessageID = try object.field("response_message_id", MessageID.self)
        responseMessageLoading = try object.field("response_message_loading", Bool.self)
        responseMessageEphemeral = try object.field("response_message_ephemeral", Bool.self)
        channelID = try object.field("channel_id", ChannelID.self)
        guildID = try object.field("guild_id", GuildID.self)
        rawFields = object.resource.fields
    }
}

/// Resource produced by a callback: a created/updated message or a launched Activity instance.
public struct InteractionCallbackResource: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let type: RawValue<InteractionCallbackType>
    public let activityInstance: Field<MessageRelatedResource>
    public let message: Field<Message>
    public let rawFields: [String: JSONValue]

    /// Parses one callback resource with complete-document bounds and exact unknown-field retention.
    /// - Parameters:
    ///   - data: Complete JSON resource object.
    ///   - limits: Whole-document byte/depth/node bounds.
    /// - Throws: JSON syntax/bounds or sanitized invalid-response errors for malformed known alternatives.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a bounded resource and enforces required fields of the currently documented alternatives.
    /// - Parameters:
    ///   - value: Original bounded resource object.
    ///   - limits: Complete outer document's parser bounds.
    /// - Throws: Invalid-response for malformed fields or known message/Activity alternatives without their resource.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        type = try object.required("type", RawValue<InteractionCallbackType>.self)
        activityInstance = try object.messageField("activity_instance", MessageRelatedResource.self)
        message = try object.messageField("message", Message.self)
        if type.knownValue == .launchActivity {
            guard case .value(let activity) = activityInstance, case .string = activity.rawFields["id"]
            else { throw DiscordError.transport(.invalidResponse) }
        }
        if type.knownValue == .channelMessageWithSource || type.knownValue == .updateMessage {
            guard case .value = message else { throw DiscordError.transport(.invalidResponse) }
        }
        rawFields = object.resource.fields
    }
}

/// Complete HTTP 200 callback result selected by with_response=true; HTTP 204 uses EmptyResponse instead.
public struct InteractionCallbackResponse: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let interaction: InteractionCallback
    public let resource: Field<InteractionCallbackResource>
    public let rawFields: [String: JSONValue]

    /// Parses a complete callback result without accepting the unrelated incoming-interaction schema.
    /// - Parameters:
    ///   - data: Complete UTF-8 result object containing required interaction metadata.
    ///   - limits: Complete-document byte/depth/node bounds.
    /// - Throws: JSON syntax/bounds or sanitized errors for malformed envelopes and nested alternatives.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded result envelope without reparsing nested resources.
    /// - Parameters:
    ///   - value: Original bounded callback result object.
    ///   - limits: Outer document's bounds.
    /// - Throws: Invalid-response for missing metadata, forbidden null or malformed resource alternatives.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        interaction = try object.messageModel("interaction", InteractionCallback.self)
        resource = try object.messageField("resource", InteractionCallbackResource.self)
        rawFields = object.resource.fields
    }
}
