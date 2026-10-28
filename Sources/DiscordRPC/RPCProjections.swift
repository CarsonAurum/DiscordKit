// File: Sources/DiscordRPC/RPCProjections.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Resource tag for desktop entitlement identities; distinct from REST and server verification authority.
public enum RPCEntitlementTag: Sendable {}

/// Resource tag for desktop SKU identities; a local SKU notification does not establish ownership.
public enum RPCSKUTag: Sendable {}

/// Partial desktop user; this does not require the full REST User baseline.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCUser: RPCPayload {
    /// Typed `id` wire field.
    public let id: UserID
    /// Typed `username` wire field; omission and explicit null remain distinct.
    public let username: Field<String>
    /// Typed `discriminator` wire field; omission and explicit null remain distinct.
    public let discriminator: Field<String>
    /// Typed `global_name` wire field; omission and explicit null remain distinct.
    public let globalName: Field<String>
    /// Typed `avatar` wire field; omission and explicit null remain distinct.
    public let avatar: Field<String>
    /// Typed `avatar_decoration_data` wire field; omission and explicit null remain distinct.
    public let avatarDecorationData: Field<JSONValue>
    /// Typed `bot` wire field; omission and explicit null remain distinct.
    public let bot: Field<Bool>
    /// Typed `flags` wire field; omission and explicit null remain distinct.
    public let flags: Field<JSONNumber>
    /// Typed `premium_type` wire field; omission and explicit null remain distinct.
    public let premiumType: Field<Int>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        id = try RPCObject.identifier(object.required("id"))
        username = try object.field("username", RPCObject.string)
        discriminator = try object.field("discriminator", RPCObject.string)
        globalName = try object.field("global_name", nullable: true, RPCObject.string)
        avatar = try object.field("avatar", nullable: true, RPCObject.string)
        avatarDecorationData = try object.field("avatar_decoration_data", nullable: true, { value in
            _ = try RPCObject(value)
            return value
        })
        bot = try object.field("bot", RPCObject.bool)
        flags = try object.field("flags", RPCObject.number)
        premiumType = try object.field("premium_type", RPCObject.integer)
        rawFields = object.fields
    }
}

/// Partial desktop guild. Deprecated members remain preserved without inferring full member availability.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCGuild: RPCPayload {
    /// Typed `id` wire field.
    public let id: GuildID
    /// Typed `name` wire field; omission and explicit null remain distinct.
    public let name: Field<String>
    /// Typed `icon_url` wire field; omission and explicit null remain distinct.
    public let iconURL: Field<String>
    /// Typed `members` wire field; omission and explicit null remain distinct.
    public let members: Field<[JSONValue]>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        id = try RPCObject.identifier(object.required("id"))
        name = try object.field("name", RPCObject.string)
        iconURL = try object.field("icon_url", nullable: true, RPCObject.string)
        members = try object.field("members", { value in guard case .array(let values) = value else { throw RPCCatalogError.invalidPayload }; return values })
        rawFields = object.fields
    }
}

/// Partial desktop message, including ID-only MESSAGE_DELETE projections and future message fields.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCMessage: RPCPayload {
    /// Typed `id` wire field.
    public let id: MessageID
    /// Typed `content` wire field; omission and explicit null remain distinct.
    public let content: Field<String>
    /// Typed `author` wire field; omission and explicit null remain distinct.
    public let author: Field<RPCUser>
    /// Typed `blocked` wire field; omission and explicit null remain distinct.
    public let blocked: Field<Bool>
    /// Typed `content_parsed` wire field; omission and explicit null remain distinct.
    public let contentParsed: Field<[JSONValue]>
    /// Typed `author_color` wire field; omission and explicit null remain distinct.
    public let authorColor: Field<String>
    /// Typed `timestamp` wire field; omission and explicit null remain distinct.
    public let timestamp: Field<String>
    /// Typed `edited_timestamp` wire field; omission and explicit null remain distinct.
    public let editedTimestamp: Field<String>
    /// Typed `tts` wire field; omission and explicit null remain distinct.
    public let tts: Field<Bool>
    /// Typed `mentions` wire field; omission and explicit null remain distinct.
    public let mentions: Field<[RPCUser]>
    /// Typed `mention_roles` wire field; omission and explicit null remain distinct.
    public let mentionRoles: Field<[String]>
    /// Typed `mention_everyone` wire field; omission and explicit null remain distinct.
    public let mentionEveryone: Field<Bool>
    /// Typed `embeds` wire field; omission and explicit null remain distinct.
    public let embeds: Field<[JSONValue]>
    /// Typed `attachments` wire field; omission and explicit null remain distinct.
    public let attachments: Field<[JSONValue]>
    /// Typed `type` wire field; omission and explicit null remain distinct.
    public let type: Field<Int>
    /// Typed `pinned` wire field; omission and explicit null remain distinct.
    public let pinned: Field<Bool>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        id = try RPCObject.identifier(object.required("id"))
        content = try object.field("content", RPCObject.string)
        author = try object.field("author", RPCUser.init(value:))
        blocked = try object.field("blocked", RPCObject.bool)
        contentParsed = try object.field("content_parsed", { value in guard case .array(let values) = value else { throw RPCCatalogError.invalidPayload }; return values })
        authorColor = try object.field("author_color", nullable: true, RPCObject.string)
        timestamp = try object.field("timestamp", RPCObject.string)
        editedTimestamp = try object.field("edited_timestamp", nullable: true, RPCObject.string)
        tts = try object.field("tts", RPCObject.bool)
        mentions = try object.field("mentions", { value in guard case .array(let values) = value else { throw RPCCatalogError.invalidPayload }; return try values.map(RPCUser.init(value:)) })
        mentionRoles = try object.field("mention_roles", { value in guard case .array(let values) = value else { throw RPCCatalogError.invalidPayload }; return try values.map(RPCObject.string) })
        mentionEveryone = try object.field("mention_everyone", RPCObject.bool)
        embeds = try object.field("embeds", { value in guard case .array(let values) = value else { throw RPCCatalogError.invalidPayload }; return values })
        attachments = try object.field("attachments", { value in guard case .array(let values) = value else { throw RPCCatalogError.invalidPayload }; return values })
        type = try object.field("type", RPCObject.integer)
        pinned = try object.field("pinned", RPCObject.bool)
        rawFields = object.fields
    }
}

/// Desktop channel voice-state flags. These are local RPC data and do not authorize Gateway voice operations.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCVoiceFlags: RPCPayload {
    /// Typed `mute` wire field.
    public let mute: Bool
    /// Typed `deaf` wire field.
    public let deaf: Bool
    /// Typed `self_mute` wire field.
    public let selfMute: Bool
    /// Typed `self_deaf` wire field.
    public let selfDeaf: Bool
    /// Typed `suppress` wire field.
    public let suppress: Bool
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        mute = try RPCObject.bool(object.required("mute"))
        deaf = try RPCObject.bool(object.required("deaf"))
        selfMute = try RPCObject.bool(object.required("self_mute"))
        selfDeaf = try RPCObject.bool(object.required("self_deaf"))
        suppress = try RPCObject.bool(object.required("suppress"))
        rawFields = object.fields
    }
}

/// Desktop voice participant state with local mix controls and an independently projected user.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCVoiceState: RPCPayload {
    /// Typed `voice_state` wire field.
    public let voiceState: RPCVoiceFlags
    /// Typed `user` wire field.
    public let user: RPCUser
    /// Typed `nick` wire field; omission and explicit null remain distinct.
    public let nick: Field<String>
    /// Typed `volume` wire field; omission and explicit null remain distinct.
    public let volume: Field<JSONNumber>
    /// Typed `mute` wire field; omission and explicit null remain distinct.
    public let mute: Field<Bool>
    /// Typed `pan` wire field; omission and explicit null remain distinct.
    public let pan: Field<RPCPan>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        voiceState = try RPCVoiceFlags.init(value:)(object.required("voice_state"))
        user = try RPCUser.init(value:)(object.required("user"))
        nick = try object.field("nick", nullable: true, RPCObject.string)
        volume = try object.field("volume", RPCObject.number)
        mute = try object.field("mute", RPCObject.bool)
        pan = try object.field("pan", RPCPan.init(value:))
        rawFields = object.fields
    }
}

/// Partial RPC channel, preserving the documented distinction between text and voice fields.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCChannel: RPCPayload {
    /// Typed `id` wire field.
    public let id: ChannelID
    /// Typed `guild_id` wire field; omission and explicit null remain distinct.
    public let guildID: Field<GuildID>
    /// Typed `name` wire field; omission and explicit null remain distinct.
    public let name: Field<String>
    /// Typed `type` wire field; omission and explicit null remain distinct.
    public let type: Field<Int>
    /// Typed `topic` wire field; omission and explicit null remain distinct.
    public let topic: Field<String>
    /// Typed `bitrate` wire field; omission and explicit null remain distinct.
    public let bitrate: Field<Int>
    /// Typed `user_limit` wire field; omission and explicit null remain distinct.
    public let userLimit: Field<Int>
    /// Typed `position` wire field; omission and explicit null remain distinct.
    public let position: Field<Int>
    /// Typed `voice_states` wire field; omission and explicit null remain distinct.
    public let voiceStates: Field<[RPCVoiceState]>
    /// Typed `messages` wire field; omission and explicit null remain distinct.
    public let messages: Field<[RPCMessage]>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        id = try RPCObject.identifier(object.required("id"))
        guildID = try object.field("guild_id", nullable: true, RPCObject.identifier)
        name = try object.field("name", nullable: true, RPCObject.string)
        type = try object.field("type", RPCObject.integer)
        topic = try object.field("topic", nullable: true, RPCObject.string)
        bitrate = try object.field("bitrate", RPCObject.integer)
        userLimit = try object.field("user_limit", RPCObject.integer)
        position = try object.field("position", RPCObject.integer)
        voiceStates = try object.field("voice_states", { value in guard case .array(let values) = value else { throw RPCCatalogError.invalidPayload }; return try values.map(RPCVoiceState.init(value:)) })
        messages = try object.field("messages", { value in guard case .array(let values) = value else { throw RPCCatalogError.invalidPayload }; return try values.map(RPCMessage.init(value:)) })
        rawFields = object.fields
    }
}

/// RPC READY server configuration. Endpoint strings are informational and never automatically followed.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCServerConfiguration: RPCPayload {
    /// Typed `cdn_host` wire field.
    public let cdnHost: String
    /// Typed `api_endpoint` wire field.
    public let apiEndpoint: String
    /// Typed `environment` wire field.
    public let environment: String
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        cdnHost = try RPCObject.string(object.required("cdn_host"))
        apiEndpoint = try RPCObject.string(object.required("api_endpoint"))
        environment = try RPCObject.string(object.required("environment"))
        rawFields = object.fields
    }
}

/// RPC READY data, delivered after a successful v1 desktop handshake before command use.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCReady: RPCPayload {
    /// Typed `v` wire field.
    public let version: Int
    /// Typed `config` wire field.
    public let configuration: RPCServerConfiguration
    /// Typed `user` wire field.
    public let user: RPCUser
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        version = try RPCObject.integer(object.required("v"))
        configuration = try RPCServerConfiguration.init(value:)(object.required("config"))
        user = try RPCUser.init(value:)(object.required("user"))
        rawFields = object.fields
    }
}

/// RPC error data. The server message is explicit data but is concealed in normal diagnostics.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCErrorPayload: RPCPayload {
    /// Typed `code` wire field.
    public let code: Int
    /// Typed `message` wire field.
    public let message: String
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        code = try RPCObject.integer(object.required("code"))
        message = try RPCObject.string(object.required("message"))
        rawFields = object.fields
    }
}

/// AUTHORIZE result. The code must be exchanged by a trusted OAuth2 owner and is redacted in diagnostics.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCAuthorization: RPCPayload {
    /// Typed `code` wire field.
    public let code: String
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        code = try RPCObject.string(object.required("code"))
        rawFields = object.fields
    }
}

/// Desktop OAuth2 application projection, distinct from the REST application model.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCApplication: RPCPayload {
    /// Typed `id` wire field.
    public let id: ApplicationID
    /// Typed `description` wire field.
    public let descriptionText: String
    /// Typed `icon` wire field.
    public let icon: Nullable<String>
    /// Typed `rpc_origins` wire field.
    public let rpcOrigins: [String]
    /// Typed `name` wire field.
    public let name: String
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        id = try RPCObject.identifier(object.required("id"))
        descriptionText = try RPCObject.string(object.required("description"))
        icon = try object.nullable("icon", RPCObject.string)
        rpcOrigins = try object.array("rpc_origins").map(RPCObject.string)
        name = try RPCObject.string(object.required("name"))
        rawFields = object.fields
    }
}

/// AUTHENTICATE result; scope names and expiry text remain verbatim and do not imply secure storage.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCAuthentication: RPCPayload {
    /// Typed `user` wire field.
    public let user: RPCUser
    /// Typed `scopes` wire field.
    public let scopes: [String]
    /// Typed `expires` wire field.
    public let expires: String
    /// Typed `application` wire field.
    public let application: RPCApplication
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        user = try RPCUser.init(value:)(object.required("user"))
        scopes = try object.array("scopes").map(RPCObject.string)
        expires = try RPCObject.string(object.required("expires"))
        application = try RPCApplication.init(value:)(object.required("application"))
        rawFields = object.fields
    }
}

/// GET_GUILDS result. Array order and complete response fields are preserved.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCGuildList: RPCPayload {
    /// Typed `guilds` wire field.
    public let guilds: [RPCGuild]
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        guilds = try object.array("guilds").map(RPCGuild.init(value:))
        rawFields = object.fields
    }
}

/// GET_CHANNELS result. Arrays are bounded by the containing JSON document and preserve order.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCChannelList: RPCPayload {
    /// Typed `channels` wire field.
    public let channels: [RPCChannel]
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        channels = try object.array("channels").map(RPCChannel.init(value:))
        rawFields = object.fields
    }
}

/// SET_USER_VOICE_SETTINGS result, retaining optional echoed controls without inventing defaults.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCUserVoiceSettings: RPCPayload {
    /// Typed `user_id` wire field.
    public let userID: UserID
    /// Typed `pan` wire field; omission and explicit null remain distinct.
    public let pan: Field<RPCPan>
    /// Typed `volume` wire field; omission and explicit null remain distinct.
    public let volume: Field<Int>
    /// Typed `mute` wire field; omission and explicit null remain distinct.
    public let mute: Field<Bool>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        userID = try RPCObject.identifier(object.required("user_id"))
        pan = try object.field("pan", RPCPan.init(value:))
        volume = try object.field("volume", RPCObject.integer)
        mute = try object.field("mute", RPCObject.bool)
        rawFields = object.fields
    }
}

/// Read-only available voice-device descriptor. Parsing never opens or enumerates hardware.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCVoiceDevice: RPCPayload {
    /// Typed `id` wire field.
    public let id: String
    /// Typed `name` wire field.
    public let name: String
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        id = try RPCObject.string(object.required("id"))
        name = try RPCObject.string(object.required("name"))
        rawFields = object.fields
    }
}

/// Partial desktop voice input/output settings, retaining exact fractional volume spelling.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCVoiceIOSettings: RPCPayload {
    /// Typed `device_id` wire field; omission and explicit null remain distinct.
    public let deviceID: Field<String>
    /// Typed `volume` wire field; omission and explicit null remain distinct.
    public let volume: Field<JSONNumber>
    /// Typed `available_devices` wire field; omission and explicit null remain distinct.
    public let availableDevices: Field<[RPCVoiceDevice]>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        deviceID = try object.field("device_id", RPCObject.string)
        volume = try object.field("volume", RPCObject.number)
        availableDevices = try object.field("available_devices", { value in guard case .array(let values) = value else { throw RPCCatalogError.invalidPayload }; return try values.map(RPCVoiceDevice.init(value:)) })
        rawFields = object.fields
    }
}

/// Push-to-talk shortcut key, retaining future integral device types.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCShortcut: RPCPayload {
    /// Typed `type` wire field.
    public let type: Int
    /// Typed `code` wire field.
    public let code: Int
    /// Typed `name` wire field.
    public let name: String
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        type = try RPCObject.integer(object.required("type"))
        code = try RPCObject.integer(object.required("code"))
        name = try RPCObject.string(object.required("name"))
        rawFields = object.fields
    }
}

/// Partial desktop voice mode. Unknown mode strings and exact threshold/delay numbers survive.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCVoiceMode: RPCPayload {
    /// Typed `type` wire field; omission and explicit null remain distinct.
    public let type: Field<String>
    /// Typed `auto_threshold` wire field; omission and explicit null remain distinct.
    public let autoThreshold: Field<Bool>
    /// Typed `threshold` wire field; omission and explicit null remain distinct.
    public let threshold: Field<JSONNumber>
    /// Typed `shortcut` wire field; omission and explicit null remain distinct.
    public let shortcut: Field<[RPCShortcut]>
    /// Typed `delay` wire field; omission and explicit null remain distinct.
    public let delay: Field<JSONNumber>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        type = try object.field("type", RPCObject.string)
        autoThreshold = try object.field("auto_threshold", RPCObject.bool)
        threshold = try object.field("threshold", RPCObject.number)
        shortcut = try object.field("shortcut", { value in guard case .array(let values) = value else { throw RPCCatalogError.invalidPayload }; return try values.map(RPCShortcut.init(value:)) })
        delay = try object.field("delay", RPCObject.number)
        rawFields = object.fields
    }
}

/// Partial RPC voice settings, accepting the official update fixture that omits mute and deaf.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCVoiceSettings: RPCPayload {
    /// Typed `input` wire field; omission and explicit null remain distinct.
    public let input: Field<RPCVoiceIOSettings>
    /// Typed `output` wire field; omission and explicit null remain distinct.
    public let output: Field<RPCVoiceIOSettings>
    /// Typed `mode` wire field; omission and explicit null remain distinct.
    public let mode: Field<RPCVoiceMode>
    /// Typed `automatic_gain_control` wire field; omission and explicit null remain distinct.
    public let automaticGainControl: Field<Bool>
    /// Typed `echo_cancellation` wire field; omission and explicit null remain distinct.
    public let echoCancellation: Field<Bool>
    /// Typed `noise_suppression` wire field; omission and explicit null remain distinct.
    public let noiseSuppression: Field<Bool>
    /// Typed `qos` wire field; omission and explicit null remain distinct.
    public let qos: Field<Bool>
    /// Typed `silence_warning` wire field; omission and explicit null remain distinct.
    public let silenceWarning: Field<Bool>
    /// Typed `deaf` wire field; omission and explicit null remain distinct.
    public let deaf: Field<Bool>
    /// Typed `mute` wire field; omission and explicit null remain distinct.
    public let mute: Field<Bool>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        input = try object.field("input", RPCVoiceIOSettings.init(value:))
        output = try object.field("output", RPCVoiceIOSettings.init(value:))
        mode = try object.field("mode", RPCVoiceMode.init(value:))
        automaticGainControl = try object.field("automatic_gain_control", RPCObject.bool)
        echoCancellation = try object.field("echo_cancellation", RPCObject.bool)
        noiseSuppression = try object.field("noise_suppression", RPCObject.bool)
        qos = try object.field("qos", RPCObject.bool)
        silenceWarning = try object.field("silence_warning", RPCObject.bool)
        deaf = try object.field("deaf", RPCObject.bool)
        mute = try object.field("mute", RPCObject.bool)
        rawFields = object.fields
    }
}

/// SUBSCRIBE/UNSUBSCRIBE acknowledgement. Successful construction does not mutate runtime subscription state.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCSubscriptionAcknowledgement: RPCPayload {
    /// Typed `evt` wire field.
    public let event: String
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        event = try RPCObject.string(object.required("evt"))
        rawFields = object.fields
    }
}

/// GUILD_STATUS projection. Online count is deprecated upstream and normally zero; raw values are retained.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCGuildStatus: RPCPayload {
    /// Typed `guild` wire field.
    public let guild: RPCGuild
    /// Typed `online` wire field.
    public let online: JSONNumber
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        guild = try RPCGuild.init(value:)(object.required("guild"))
        online = try RPCObject.number(object.required("online"))
        rawFields = object.fields
    }
}

/// VOICE_CHANNEL_SELECT data with required nullable channel and guild identities.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCChannelSelection: RPCPayload {
    /// Typed `channel_id` wire field.
    public let channelID: Nullable<ChannelID>
    /// Typed `guild_id` wire field.
    public let guildID: Nullable<GuildID>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        channelID = try object.nullable("channel_id", RPCObject.identifier)
        guildID = try object.nullable("guild_id", RPCObject.identifier)
        rawFields = object.fields
    }
}

/// Voice connection telemetry. Official prose says integers but its example contains 13.37 ms; exact numbers accept both.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCVoiceConnectionStatus: RPCPayload {
    /// Typed `state` wire field.
    public let state: String
    /// Typed `hostname` wire field.
    public let hostname: String
    /// Typed `pings` wire field.
    public let pings: [JSONNumber]
    /// Typed `average_ping` wire field.
    public let averagePing: JSONNumber
    /// Typed `last_ping` wire field.
    public let lastPing: JSONNumber
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        state = try RPCObject.string(object.required("state"))
        hostname = try RPCObject.string(object.required("hostname"))
        pings = try object.array("pings").map(RPCObject.number)
        averagePing = try RPCObject.number(object.required("average_ping"))
        lastPing = try RPCObject.number(object.required("last_ping"))
        rawFields = object.fields
    }
}

/// MESSAGE_CREATE/UPDATE/DELETE data; deleted messages may contain only their identity.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCMessageEvent: RPCPayload {
    /// Typed `channel_id` wire field.
    public let channelID: ChannelID
    /// Typed `message` wire field.
    public let message: RPCMessage
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        channelID = try RPCObject.identifier(object.required("channel_id"))
        message = try RPCMessage.init(value:)(object.required("message"))
        rawFields = object.fields
    }
}

/// SPEAKING_START/STOP data. Channel scope belongs to the acknowledged subscription.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCSpeaking: RPCPayload {
    /// Typed `user_id` wire field.
    public let userID: UserID
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        userID = try RPCObject.identifier(object.required("user_id"))
        rawFields = object.fields
    }
}

/// NOTIFICATION_CREATE data, requiring rpc.notifications.read; message contents are redacted in diagnostics.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCNotification: RPCPayload {
    /// Typed `channel_id` wire field.
    public let channelID: ChannelID
    /// Typed `message` wire field.
    public let message: RPCMessage
    /// Typed `icon_url` wire field.
    public let iconURL: String
    /// Typed `title` wire field.
    public let title: String
    /// Typed `body` wire field.
    public let body: String
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        channelID = try RPCObject.identifier(object.required("channel_id"))
        message = try RPCMessage.init(value:)(object.required("message"))
        iconURL = try RPCObject.string(object.required("icon_url"))
        title = try RPCObject.string(object.required("title"))
        body = try RPCObject.string(object.required("body"))
        rawFields = object.fields
    }
}

/// Partial received activity. Unknown nested fields remain lossless; these values never prove invite authenticity.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCActivityProjection: RPCPayload {
    /// Typed `application_id` wire field; omission and explicit null remain distinct.
    public let applicationID: Field<ApplicationID>
    /// Typed `name` wire field; omission and explicit null remain distinct.
    public let name: Field<String>
    /// Typed `type` wire field; omission and explicit null remain distinct.
    public let type: Field<Int>
    /// Typed `state` wire field; omission and explicit null remain distinct.
    public let state: Field<String>
    /// Typed `state_url` wire field; omission and explicit null remain distinct.
    public let stateURL: Field<String>
    /// Typed `details` wire field; omission and explicit null remain distinct.
    public let details: Field<String>
    /// Typed `details_url` wire field; omission and explicit null remain distinct.
    public let detailsURL: Field<String>
    /// Typed `timestamps` wire field; omission and explicit null remain distinct.
    public let timestamps: Field<JSONValue>
    /// Typed `assets` wire field; omission and explicit null remain distinct.
    public let assets: Field<JSONValue>
    /// Typed `party` wire field; omission and explicit null remain distinct.
    public let party: Field<JSONValue>
    /// Typed `secrets` wire field; omission and explicit null remain distinct.
    public let secrets: Field<JSONValue>
    /// Typed `instance` wire field; omission and explicit null remain distinct.
    public let instance: Field<Bool>
    /// Typed `buttons` wire field; omission and explicit null remain distinct.
    public let buttons: Field<[JSONValue]>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        applicationID = try object.field("application_id", RPCObject.identifier)
        name = try object.field("name", RPCObject.string)
        type = try object.field("type", RPCObject.integer)
        state = try object.field("state", nullable: true, RPCObject.string)
        stateURL = try object.field("state_url", nullable: true, RPCObject.string)
        details = try object.field("details", nullable: true, RPCObject.string)
        detailsURL = try object.field("details_url", nullable: true, RPCObject.string)
        timestamps = try object.field("timestamps", { value in _ = try RPCObject(value); return value })
        assets = try object.field("assets", { value in _ = try RPCObject(value); return value })
        party = try object.field("party", { value in _ = try RPCObject(value); return value })
        secrets = try object.field("secrets", { value in _ = try RPCObject(value); return value })
        instance = try object.field("instance", RPCObject.bool)
        buttons = try object.field("buttons", { value in guard case .array(let values) = value else { throw RPCCatalogError.invalidPayload }; return values })
        rawFields = object.fields
    }
}

/// ACTIVITY_JOIN/SPECTATE data. Secrets are caller-owned sensitive data and concealed in descriptions.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCActivitySecret: RPCPayload {
    /// Typed `secret` wire field.
    public let secret: String
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        secret = try RPCObject.string(object.required("secret"))
        rawFields = object.fields
    }
}

/// ACTIVITY_JOIN_REQUEST data. User consent remains an explicit host UI decision.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCActivityJoinRequest: RPCPayload {
    /// Typed `user` wire field.
    public let user: RPCUser
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        user = try RPCUser.init(value:)(object.required("user"))
        rawFields = object.fields
    }
}

/// ACTIVITY_INVITE data. Future invite type numbers survive without implying a supported action.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCActivityInvite: RPCPayload {
    /// Typed `type` wire field.
    public let type: Int
    /// Typed `user` wire field.
    public let user: RPCUser
    /// Typed `activity` wire field.
    public let activity: RPCActivityProjection
    /// Typed `channel_id` wire field.
    public let channelID: ChannelID
    /// Typed `message_id` wire field.
    public let messageID: MessageID
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        type = try RPCObject.integer(object.required("type"))
        user = try RPCUser.init(value:)(object.required("user"))
        activity = try RPCActivityProjection.init(value:)(object.required("activity"))
        channelID = try RPCObject.identifier(object.required("channel_id"))
        messageID = try RPCObject.identifier(object.required("message_id"))
        rawFields = object.fields
    }
}

/// Relationship presence with unknown status strings and a required nullable application activity.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCPresence: RPCPayload {
    /// Typed `status` wire field.
    public let status: String
    /// Typed `activity` wire field.
    public let activity: Nullable<RPCActivityProjection>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        status = try RPCObject.string(object.required("status"))
        activity = try object.nullable("activity", RPCActivityProjection.init(value:))
        rawFields = object.fields
    }
}

/// RELATIONSHIP_UPDATE data. Type zero means removed; future relationship types remain observable.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCRelationship: RPCPayload {
    /// Typed `type` wire field.
    public let type: Int
    /// Typed `user` wire field.
    public let user: RPCUser
    /// Typed `presence` wire field.
    public let presence: RPCPresence
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        type = try RPCObject.integer(object.required("type"))
        user = try RPCUser.init(value:)(object.required("user"))
        presence = try RPCPresence.init(value:)(object.required("presence"))
        rawFields = object.fields
    }
}

/// Desktop entitlement projection. It is notification data and must never authorize a server-side purchase or grant.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCEntitlement: RPCPayload {
    /// Typed `id` wire field.
    public let id: Snowflake<RPCEntitlementTag>
    /// Typed `sku_id` wire field.
    public let skuID: Snowflake<RPCSKUTag>
    /// Typed `application_id` wire field.
    public let applicationID: ApplicationID
    /// Typed `user_id` wire field.
    public let userID: UserID
    /// Typed `type` wire field.
    public let type: Int
    /// Typed `deleted` wire field.
    public let deleted: Bool
    /// Typed `starts_at` wire field; omission and explicit null remain distinct.
    public let startsAt: Field<String>
    /// Typed `ends_at` wire field; omission and explicit null remain distinct.
    public let endsAt: Field<String>
    /// Typed `guild_id` wire field; omission and explicit null remain distinct.
    public let guildID: Field<GuildID>
    /// Typed `consumed` wire field; omission and explicit null remain distinct.
    public let consumed: Field<Bool>
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        id = try RPCObject.identifier(object.required("id"))
        skuID = try RPCObject.identifier(object.required("sku_id"))
        applicationID = try RPCObject.identifier(object.required("application_id"))
        userID = try RPCObject.identifier(object.required("user_id"))
        type = try RPCObject.integer(object.required("type"))
        deleted = try RPCObject.bool(object.required("deleted"))
        startsAt = try object.field("starts_at", nullable: true, RPCObject.string)
        endsAt = try object.field("ends_at", nullable: true, RPCObject.string)
        guildID = try object.field("guild_id", nullable: true, RPCObject.identifier)
        consumed = try object.field("consumed", RPCObject.bool)
        rawFields = object.fields
    }
}

/// ENTITLEMENT_CREATE/DELETE wrapper. Server entitlement verification remains a separate Commerce workflow.
/// RPC v1 reference verified 2026-10-17; all unknown fields and numeric lexemes remain in rawFields.
public struct RPCEntitlementEvent: RPCPayload {
    /// Typed `entitlement` wire field.
    public let entitlement: RPCEntitlement
    /// Complete original object, including future fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]
    /// Projects a bounded RPC object without I/O, suspension or mutable resource ownership.
    /// - Parameter value: Immutable object subtree from the bounded envelope parser.
    /// - Throws: Sanitized invalid-payload errors for absent required fields or incompatible modeled types.
    /// Optional fields preserve absence; explicitly nullable fields preserve null. Unknown values are retained.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        entitlement = try RPCEntitlement.init(value:)(object.required("entitlement"))
        rawFields = object.fields
    }
}
