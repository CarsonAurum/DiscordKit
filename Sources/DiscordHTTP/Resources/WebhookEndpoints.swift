// File: Sources/DiscordHTTP/Resources/WebhookEndpoints.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation

/// Native webhook execution distinguishes unconfirmed acceptance from a persisted message returned by wait=true.
public enum WebhookExecutionResponse: Sendable, Equatable {
    /// Empty 204 when wait=false; Discord explicitly does not guarantee unsaved-message errors in this mode.
    case unconfirmed
    /// Server-confirmed message when wait=true, including the normal partial related-resource projections.
    case message(Message)
}

/// Complete written API v10 webhook routes, verified 2026-10-16 against the Webhook Resource and official preview.
/// Management uses bot authentication/MANAGE_WEBHOOKS unless an owned-webhook exception applies. Token routes
/// omit Authorization and require a matching `.webhook(id, token)` RESTClient credential, stable token identity,
/// and an explicit shared outbound-IP egress scope. They retain IP-global admission and per-webhook buckets.
/// Possessing a token grants only the documented webhook operations; it does not prove ownership or channel type.
/// Mutations are conservatively unsafe; rejected 429 responses alone may be replayed within caller policy.
public enum WebhookEndpoints {
    /// Creates an incoming webhook and fires Webhooks Update; requires MANAGE_WEBHOOKS.
    /// - Parameters:
    ///   - channelID: Destination channel and major rate partition.
    ///   - request: Validated name and optional nullable avatar.
    ///   - auditReason: Optional control-free audit reason, at most 512 scalars.
    /// - Returns: Unsafe POST descriptor expecting HTTP 200 webhook, with scoped catalog invalidation.
    /// - Throws: Bounded JSON/body/descriptor errors now; API/transport/cancellation or indeterminate outcomes later.
    public static func create(channelID: ChannelID, request: WebhookCreate, auditReason: String? = nil) throws -> Endpoint<Webhook> {
        try Endpoint(method: "POST", path: ["channels", channelID.description, "webhooks"],
            route: "/channels/{channel.id}/webhooks", authentication: .bot, majorParameter: channelID.description,
            auditReason: auditReason, body: guildJSON(request.jsonValue()), invalidates: webhookTags,
            decode: { try Webhook(data: $0) })
    }

    /// Lists all channel webhooks with MANAGE_WEBHOOKS; no pagination or per-item hydration occurs.
    /// - Parameters:
    ///   - channelID: Channel and major rate partition.
    ///   - readPolicy: Explicit scoped read reuse, default coalescing without completed caching; nil disables reuse.
    /// - Returns: Safe HTTP 200 GET preserving server order and empty lists.
    /// - Throws: Descriptor/policy errors now; API/transport or malformed webhook-array errors during execution.
    public static func channel(channelID: ChannelID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[Webhook]> {
        try webhookList(path: ["channels", channelID.description, "webhooks"], route: "/channels/{channel.id}/webhooks",
            major: channelID.description, readPolicy: readPolicy)
    }

    /// Lists all guild webhooks with MANAGE_WEBHOOKS; no list pagination is invented.
    /// - Parameters:
    ///   - guildID: Guild and major rate partition.
    ///   - readPolicy: Optional bounded scoped reuse, default coalesces without caching.
    /// - Returns: Safe HTTP 200 GET of the complete current webhook array, including empty.
    /// - Throws: Descriptor/policy errors now; API/transport or malformed-array errors later.
    public static func guild(guildID: GuildID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[Webhook]> {
        try webhookList(path: ["guilds", guildID.description, "webhooks"], route: "/guilds/{guild.id}/webhooks",
            major: guildID.description, readPolicy: readPolicy)
    }

    /// Gets a webhook with bot authentication; MANAGE_WEBHOOKS is waived for the owning application.
    /// - Parameters:
    ///   - webhookID: Exact webhook and major rate partition.
    ///   - readPolicy: Optional scoped read reuse, default no completed cache.
    /// - Returns: Safe HTTP 200 GET decoding all written webhook fields.
    /// - Throws: Descriptor/policy errors now; permission/API/transport or schema errors at execution.
    public static func get(webhookID: WebhookID, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Webhook> {
        try webhookDescriptor("GET", webhookID: webhookID, reading: true, readPolicy: readPolicy) { try Webhook(data: $0) }
    }

    /// Gets a webhook with its token and no Authorization header; Discord omits the creator user.
    /// - Parameters:
    ///   - webhookID: Exact webhook and major rate partition.
    ///   - token: Secret matching the dedicated RESTClient webhook credential.
    ///   - readPolicy: Optional token-scoped reuse; stable per-token identity and shared egress are required at execution.
    /// - Returns: Safe HTTP 200 GET; normalized rate routes and diagnostics conceal tokens.
    /// - Throws: Token/path/policy errors now; credential mismatch, API/transport or schema errors later.
    public static func getWithToken(webhookID: WebhookID, token: WebhookToken,
                                    readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Webhook> {
        try webhookDescriptor("GET", webhookID: webhookID, token: token, reading: true, readPolicy: readPolicy) { try Webhook(data: $0) }
    }

    /// Modifies name/avatar/channel with bot authentication and MANAGE_WEBHOOKS; emits Webhooks Update.
    /// - Parameters:
    ///   - webhookID: Exact webhook major partition.
    ///   - request: Validated optional metadata changes; empty changes are transmitted explicitly.
    ///   - auditReason: Optional at-most-512-scalar audit reason.
    /// - Returns: Unsafe PATCH descriptor expecting updated HTTP 200 webhook.
    /// - Throws: Body/descriptor errors now; API/transport/cancellation or uncertain-mutation errors later.
    public static func modify(webhookID: WebhookID, request: WebhookModify, auditReason: String? = nil) throws -> Endpoint<Webhook> {
        try webhookDescriptor("PATCH", webhookID: webhookID, body: guildJSON(request.jsonValue()), auditReason: auditReason) { try Webhook(data: $0) }
    }

    /// Modifies only name/avatar with a path token; channel movement is forbidden and creator user is omitted.
    /// - Parameters:
    ///   - webhookID: Webhook major partition.
    ///   - token: Secret matching the dedicated client credential.
    ///   - request: Validated metadata without channelID; avatar null explicitly removes the avatar.
    /// - Returns: Unsafe HTTP 200 PATCH without Authorization or audit-reason headers.
    /// - Throws: Invalid-value for supplied channel changes; bounded body/descriptor errors or execution failures.
    public static func modifyWithToken(webhookID: WebhookID, token: WebhookToken, request: WebhookModify) throws -> Endpoint<Webhook> {
        guard case .absent = request.channelID else { throw DiscordError.validation(.invalidValue) }
        return try webhookDescriptor("PATCH", webhookID: webhookID, token: token, body: guildJSON(request.jsonValue())) { try Webhook(data: $0) }
    }

    /// Permanently deletes a webhook with MANAGE_WEBHOOKS and fires Webhooks Update.
    /// - Parameters:
    ///   - webhookID: Exact target major partition.
    ///   - auditReason: Optional validated audit reason.
    /// - Returns: Unsafe DELETE expecting empty HTTP 204; associated messages are not implicitly fetched.
    /// - Throws: Descriptor errors now; API/transport/cancellation or indeterminate-deletion failures later.
    public static func delete(webhookID: WebhookID, auditReason: String? = nil) throws -> Endpoint<EmptyResponse> {
        try webhookDescriptor("DELETE", webhookID: webhookID, successStatuses: [204], auditReason: auditReason, decode: EmptyResponse.init)
    }

    /// Permanently deletes a webhook using its path token without bot authorization.
    /// - Parameters:
    ///   - webhookID: Exact target major partition.
    ///   - token: Matching client webhook credential; token lifetime and validity remain server decisions.
    /// - Returns: Unsafe DELETE expecting exactly empty HTTP 204.
    /// - Throws: Descriptor errors now; credential/API/transport/cancellation or uncertain outcomes later.
    public static func deleteWithToken(webhookID: WebhookID, token: WebhookToken) throws -> Endpoint<EmptyResponse> {
        try webhookDescriptor("DELETE", webhookID: webhookID, token: token, successStatuses: [204], decode: EmptyResponse.init)
    }

    /// Sends a native webhook message or creates a forum/media thread with explicitly bounded uploads.
    /// - Parameters:
    ///   - webhookID: Destination webhook major partition.
    ///   - token: Matching dedicated client webhook credential; no Authorization header is sent.
    ///   - request: Validated message fields plus optional username/avatar/thread overrides.
    ///   - wait: False default yields unconfirmed 204; true waits for a persisted HTTP 200 Message.
    ///   - threadID: Optional existing thread, automatically unarchived by Discord; conflicts with threadName.
    ///   - isForumOrMedia: True validates that either threadID or threadName was supplied; false cannot infer actual type.
    ///   - ownership: Incoming by default; explicit application-owned evidence allows interactive components.
    ///   - withComponents: False default; incoming component submissions require true to prevent silent field loss.
    ///   - files: At most ten replayable uploads, opened only when transmitted; IDs must match attachment metadata.
    ///   - limits: Default 20 MiB/file, 25 MiB complete request and 64 KiB chunks; explicit lower bounds are supported.
    /// - Returns: Unsafe POST with a status/decoder fixed by wait; unconfirmed responses never synthesize a Message.
    /// - Throws: Payload/thread/component/upload/descriptor validation errors before file ownership; execution preserves
    ///   API failures, cancellation, source cleanup and indeterminate submissions. V2 forbids traditional fields/files.
    public static func execute(webhookID: WebhookID, token: WebhookToken, request: WebhookExecute, wait: Bool = false,
                               threadID: ChannelID? = nil, isForumOrMedia: Bool = false,
                               ownership: WebhookComponentOwnership = .incoming, withComponents: Bool = false,
                               files: [MessageUploadFile] = [], limits: MessageUploadLimits = .default) throws -> Endpoint<WebhookExecutionResponse> {
        let payload = try request.jsonValue(uploadIDs: files.map(\.id), threadID: threadID, isForumOrMedia: isForumOrMedia,
            ownership: ownership, withComponents: withComponents)
        return try webhookDescriptor("POST", webhookID: webhookID, token: token,
            query: webhookQuery(wait: wait, threadID: threadID, withComponents: withComponents), successStatuses: [wait ? 200 : 204],
            body: MessageUpload.body(payload: payload, files: files, limits: limits)) { bytes in
                if wait { return .message(try Message(data: bytes)) }
                _ = try EmptyResponse(data: bytes); return .unconfirmed
            }
    }

    /// Sends Slack-compatible fields; this adapter acknowledges with JSON string/null rather than a Message.
    /// - Parameters:
    ///   - webhookID: Exact target webhook major partition.
    ///   - token: Matching client webhook secret.
    ///   - request: Validated Slack text/username/icon/attachments; unsupported channel/icon_emoji/mrkdwn options have no API.
    ///   - wait: True by default per the written compatibility reference; false permits unreported unsaved messages.
    ///   - threadID: Optional thread receiving the converted message.
    /// - Returns: Unsafe HTTP 200 descriptor decoding the official preview's nullable string acknowledgement.
    /// - Throws: Bounded body/descriptor errors now; credential/API/transport, malformed acknowledgements or uncertain sends later.
    public static func executeSlack(webhookID: WebhookID, token: WebhookToken, request: WebhookSlackExecute,
                                    wait: Bool = true, threadID: ChannelID? = nil) throws -> Endpoint<Nullable<String>> {
        try webhookDescriptor("POST", webhookID: webhookID, token: token, suffix: ["slack"],
            query: webhookQuery(wait: wait, threadID: threadID), body: guildJSON(request.jsonValue())) { bytes in
                switch try JSONValue.parse(bytes) {
                case .null: return .null
                case .string(let value): return .value(value)
                default: throw DiscordError.transport(.invalidResponse)
                }
            }
    }

    /// Sends a supported GitHub delivery through Discord's compatibility adapter; no Message body is promised.
    /// - Parameters:
    ///   - webhookID: Exact webhook major partition.
    ///   - token: Matching client webhook secret.
    ///   - event: One of the 18 documented GitHub events, transmitted in X-GitHub-Event.
    ///   - request: Validated typed GitHub sender and optional event-specific objects.
    ///   - wait: True default per prose; the official preview defines empty HTTP 204 for this adapter.
    ///   - threadID: Optional destination thread.
    /// - Returns: Unsafe HTTP 204 POST, preserving server event filtering without synthesizing message confirmation.
    /// - Throws: Bounded body/descriptor errors now; credential/API/transport/cancellation or uncertain sends later.
    public static func executeGitHub(webhookID: WebhookID, token: WebhookToken, event: WebhookGitHubEvent,
                                     request: WebhookGitHubExecute, wait: Bool = true,
                                     threadID: ChannelID? = nil) throws -> Endpoint<EmptyResponse> {
        try webhookDescriptor("POST", webhookID: webhookID, token: token, suffix: ["github"],
            query: webhookQuery(wait: wait, threadID: threadID), successStatuses: [204], body: guildJSON(request.jsonValue()),
            headers: [HTTPHeader(name: "X-GitHub-Event", value: event.rawValue)], decode: EmptyResponse.init)
    }

    /// Gets a previously sent message belonging to the same webhook token.
    /// - Parameters:
    ///   - webhookID: Webhook major partition.
    ///   - token: Matching dedicated client credential.
    ///   - messageID: Message identifier; original interaction aliases are handled by InteractionEndpoints instead.
    ///   - threadID: Required when the message is in a thread; omission remains distinct.
    ///   - readPolicy: Explicit scoped read reuse, default coalescing without caching.
    /// - Returns: Safe HTTP 200 GET with Message's documented related-resource projection limits.
    /// - Throws: Descriptor/policy errors now; credential/API/transport/schema failures later.
    public static func message(webhookID: WebhookID, token: WebhookToken, messageID: MessageID,
                               threadID: ChannelID? = nil, readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Message> {
        try webhookDescriptor("GET", webhookID: webhookID, token: token, suffix: ["messages", messageID.description],
            query: webhookQuery(threadID: threadID), reading: true, readPolicy: readPolicy) { try Message(data: $0) }
    }

    /// Edits the token's message with complete API v10 attachment retention and rebuilt mention parsing.
    /// - Parameters:
    ///   - webhookID: Webhook major partition.
    ///   - token: Matching dedicated client secret.
    ///   - messageID: Previously sent message identifier.
    ///   - request: Presence-aware fields; omitted allowed_mentions uses Discord edit defaults.
    ///   - threadID: Optional containing thread.
    ///   - ownership: Incoming default; application ownership permits interactive components.
    ///   - withComponents: Incoming component edits require explicit true; false preserves upstream default.
    ///   - files: Replayable new uploads; request attachments lists all retained and new IDs. Existing V2 messages
    ///     support files referenced by components; first migration to V2 clears traditional fields before new uploads.
    ///   - limits: Per-file and total bounded upload/framing limits, default 20/25 MiB.
    /// - Returns: Unsafe HTTP 200 PATCH with updated Message and token-scoped invalidation.
    /// - Throws: Field/retention/component/upload/descriptor errors now; API/transport/cancellation or uncertain edits later.
    public static func editMessage(webhookID: WebhookID, token: WebhookToken, messageID: MessageID,
                                   request: WebhookMessageEdit, threadID: ChannelID? = nil,
                                   ownership: WebhookComponentOwnership = .incoming, withComponents: Bool = false,
                                   files: [MessageUploadFile] = [], limits: MessageUploadLimits = .default) throws -> Endpoint<Message> {
        let payload = try request.jsonValue(uploadIDs: files.map(\.id), ownership: ownership, withComponents: withComponents)
        return try webhookDescriptor("PATCH", webhookID: webhookID, token: token, suffix: ["messages", messageID.description],
            query: webhookQuery(threadID: threadID, withComponents: withComponents),
            body: MessageUpload.body(payload: payload, files: files, limits: limits)) { try Message(data: $0) }
    }

    /// Deletes a message created by the same webhook token.
    /// - Parameters:
    ///   - webhookID: Exact webhook major partition.
    ///   - token: Matching client credential; no bot authorization is attached.
    ///   - messageID: Previously sent message identifier.
    ///   - threadID: Optional containing thread; the caller supplies known thread context.
    /// - Returns: Unsafe DELETE expecting empty HTTP 204 and invalidating token-scoped webhook reads.
    /// - Throws: Descriptor errors now; credential/API/transport/cancellation or indeterminate deletion failures later.
    public static func deleteMessage(webhookID: WebhookID, token: WebhookToken, messageID: MessageID,
                                     threadID: ChannelID? = nil) throws -> Endpoint<EmptyResponse> {
        try webhookDescriptor("DELETE", webhookID: webhookID, token: token, suffix: ["messages", messageID.description],
            query: webhookQuery(threadID: threadID), successStatuses: [204], decode: EmptyResponse.init)
    }
}

/// Broad authentication-scoped invalidation covers webhook objects/lists/messages without retaining unbounded IDs.
private let webhookTags: Set<String> = ["webhook-catalog"]

/// Constructs complete webhook lists through normal bot policy without pagination or hidden reads.
/// - Parameters:
///   - path: Channel/guild collection segments.
///   - route: Token-free normalized route template.
///   - major: Exact channel or guild partition.
///   - readPolicy: Optional caller-controlled read reuse.
/// - Returns: Safe HTTP 200 descriptor with webhook-scoped read tags.
/// - Throws: Descriptor/policy errors now; bounded list/item schema errors when decoding.
private func webhookList(path: [String], route: String, major: String, readPolicy: ReadPolicy?) throws -> Endpoint<[Webhook]> {
    try Endpoint(method: "GET", path: path, route: route, authentication: .bot, majorParameter: major,
        retrySafety: .safe, readPolicy: expressionReadPolicy(readPolicy, tags: webhookTags),
        decode: { try guildArray($0) { try Webhook(data: $0) } })
}

/// Builds management/execution/message descriptors while keeping path secrets out of rate routes and diagnostics.
/// - Parameters:
///   - method: Explicit GET/POST/PATCH/DELETE method.
///   - webhookID: Exact major partition, never a secret.
///   - token: Optional path credential; nil uses bot authorization instead.
///   - suffix: Literal adapter/messages route suffix, empty for webhook management/native execution.
///   - query: Explicit ordered fields, empty by default.
///   - successStatuses: Exact accepted statuses, default HTTP 200.
///   - reading: Explicit safe read policy, false for every mutation.
///   - readPolicy: Caller opt-in reuse only for reading descriptors.
///   - body: Optional already bounded replayable JSON/multipart body.
///   - auditReason: Optional bot-management reason, nil for token operations.
///   - headers: Representation/delivery headers, empty by default.
///   - decode: Exact typed decoder; synchronous and bounded by the client response collector.
/// - Returns: Immutable descriptor with per-token identity validation and IP-global admission where applicable.
/// - Throws: Unsafe path/policy/header/metadata errors; no network I/O or upload sources are opened.
private func webhookDescriptor<T: Sendable>(_ method: String, webhookID: WebhookID, token: WebhookToken? = nil,
    suffix: [String] = [], query: [QueryItem] = [], successStatuses: Set<Int> = [200], reading: Bool = false,
    readPolicy: ReadPolicy? = nil, body: RequestBody? = nil, auditReason: String? = nil,
    headers: [HTTPHeader] = [], decode: @escaping @Sendable (Data) throws -> T) throws -> Endpoint<T> {
    let path = ["webhooks", webhookID.description] + (token.map { $0.withUnsafeValue { [$0] } } ?? []) + suffix
    let normalizedSuffix = suffix.first == "messages" ? ["messages", "{message.id}"] : suffix
    return try Endpoint(method: method, path: path,
        route: "/webhooks/{webhook.id}" + (token == nil ? "" : "/{webhook.token}") + (normalizedSuffix.isEmpty ? "" : "/" + normalizedSuffix.joined(separator: "/")),
        query: query, authentication: token == nil ? .bot : .none,
        pathCredential: token.map { .webhook(webhookID, $0) }, successStatuses: successStatuses,
        majorParameter: webhookID.description, auditReason: auditReason, body: body, headers: headers,
        retrySafety: reading ? .safe : .unsafe,
        readPolicy: reading ? expressionReadPolicy(readPolicy, tags: webhookTags) : nil,
        invalidates: reading ? [] : webhookTags, decode: decode)
}

/// Encodes explicit webhook query context once, without changing default wait behavior across adapters.
/// - Parameters:
///   - wait: Optional wait setting; nil omits it for message routes.
///   - threadID: Optional exact destination/containing thread snowflake.
///   - withComponents: Optional component opt-in, nil for routes that do not support it.
/// - Returns: Ordered wait/thread_id/with_components query fields with lowercase boolean spellings.
private func webhookQuery(wait: Bool? = nil, threadID: ChannelID? = nil, withComponents: Bool? = nil) -> [QueryItem] {
    var result: [QueryItem] = []
    if let wait { result.append(.init(name: "wait", value: String(wait))) }
    if let threadID { result.append(.init(name: "thread_id", value: threadID.description)) }
    if let withComponents { result.append(.init(name: "with_components", value: String(withComponents))) }
    return result
}
