// File: Sources/DiscordHTTP/Resources/InteractionEndpoints.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Foundation

/// All eight API v10 interaction-response operations, verified against the official receiving/responding
/// reference on 2026-10-16. They require a dedicated client carrying the exact InteractionToken and a stable
/// opaque per-token RateLimitIdentity shared by cooperating callers. Authorization headers are omitted.
/// These operations are exempt from the application's global REST limit and retain webhook bucket admission.
/// Initial responses must arrive within three seconds; tokens last fifteen minutes. No deadline/acknowledgement
/// state machine, signature verifier, ingress server or handler router is provided by these REST descriptors.
public enum InteractionEndpoints {
    /// Acknowledges an interaction with the strict empty HTTP 204 result contract.
    /// - Parameters:
    ///   - interactionID: Exact interaction snowflake from the received event.
    ///   - token: Path-carried continuation token; the executing client must carry the same typed secret.
    ///   - response: Validated callback variant; initial acknowledgement is single-use and never generically retried.
    ///   - interactionType: Optional triggering kind for local callback-compatibility validation.
    ///   - files: Up to ten replayable bounded uploads, only for message/update callbacks.
    ///   - uploadLimits: Per-file, complete-request and chunk bounds; default caps are documented by MessageUpload.
    /// - Returns: Unsafe POST /interactions/{interaction.id}/{interaction.token}/callback with no Authorization header.
    /// - Throws: Local callback/path/upload errors now; expired/already-acknowledged/API/rate/transport errors during execution.
    ///   Ambiguous submission remains indeterminate; callers must not retry assuming the acknowledgement was rejected.
    public static func createResponse(interactionID: InteractionID, token: InteractionToken,
        response: InteractionResponse, interactionType: InteractionType? = nil,
        files: [MessageUploadFile] = [], uploadLimits: MessageUploadLimits = .default) throws -> Endpoint<EmptyResponse> {
        try callback(interactionID: interactionID, token: token, response: response, interactionType: interactionType,
            files: files, uploadLimits: uploadLimits, withResponse: false, decode: { try EmptyResponse(data: $0) })
    }

    /// Acknowledges an interaction and requests the typed callback metadata/resource result in HTTP 200.
    /// - Parameters:
    ///   - interactionID: Exact interaction snowflake, preserving all 64 bits.
    ///   - token: Exact interaction-scoped path secret, matching the executing client's typed credential.
    ///   - response: Callback message/defer/update/autocomplete/modal/Activity variant, including PONG and deprecated premium.
    ///   - interactionType: Optional triggering kind for local callback-type compatibility checks.
    ///   - files: At most ten replayable upload sources, opened lazily only by transmitted attempts.
    ///   - uploadLimits: Positive per-file/request/chunk limits, with complete requests capped at 25 MiB.
    /// - Returns: Unsafe POST with with_response=true, accepting only HTTP 200 InteractionCallbackResponse.
    /// - Throws: Local callback/upload/descriptor errors now; API, cancellation, malformed-result or indeterminate-send errors later.
    ///   Activity eligibility and the three-second initial-response deadline remain caller/server responsibilities.
    public static func createResponseWithResult(interactionID: InteractionID, token: InteractionToken,
        response: InteractionResponse, interactionType: InteractionType? = nil,
        files: [MessageUploadFile] = [], uploadLimits: MessageUploadLimits = .default) throws -> Endpoint<InteractionCallbackResponse> {
        try callback(interactionID: interactionID, token: token, response: response, interactionType: interactionType,
            files: files, uploadLimits: uploadLimits, withResponse: true, decode: { try InteractionCallbackResponse(data: $0) })
    }

    /// Retrieves the initial interaction response, including ephemeral responses when Discord permits.
    /// - Parameters:
    ///   - applicationID: Application owning the received interaction.
    ///   - token: Unexpired continuation token, matching the dedicated executing client's credential.
    ///   - readPolicy: Optional token-identity-scoped coalescing/freshness policy; default coalesces without completed caching.
    /// - Returns: Safe HTTP 200 GET /webhooks/{application.id}/{interaction.token}/messages/@original.
    /// - Throws: Descriptor errors now; token expiry, missing response, API/transport/cancellation/schema errors later.
    ///   A snapshot does not extend the fifteen-minute token lifetime or establish current access rights.
    public static func getOriginalResponse(applicationID: ApplicationID, token: InteractionToken,
        readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Message> {
        try responseEndpoint("GET", applicationID: applicationID, token: token, message: "@original",
            readPolicy: readPolicy, decode: { try Message(data: $0) })
    }

    /// Edits the initial response; this is the supported route for editing an ephemeral original or completing a defer.
    /// - Parameters:
    ///   - applicationID: Owning application identifier.
    ///   - token: Exact path secret from the original interaction, matching the executing client's credential.
    ///   - request: Presence-aware body; creating a poll requires explicit deferred-response evidence.
    ///   - files: New bounded replayable uploads; request metadata must enumerate every retained/new attachment.
    ///   - uploadLimits: Independent per-file, complete request and chunk caps, default MessageUpload limits.
    /// - Returns: Unsafe HTTP 200 PATCH and updated Message; EPHEMERAL state cannot be changed after creation.
    /// - Throws: Local payload/upload errors now; expiry/API/rate/transport/schema or indeterminate mutation errors later.
    public static func editOriginalResponse(applicationID: ApplicationID, token: InteractionToken,
        request: InteractionMessageEdit, files: [MessageUploadFile] = [],
        uploadLimits: MessageUploadLimits = .default) throws -> Endpoint<Message> {
        try responseEndpoint("PATCH", applicationID: applicationID, token: token, message: "@original",
            body: upload(request: request, files: files, limits: uploadLimits), decode: { try Message(data: $0) })
    }

    /// Deletes the original response without treating an absent/already-deleted response as invented success.
    /// - Parameters:
    ///   - applicationID: Owning application's exact identifier.
    ///   - token: Unexpired interaction path credential, matching the executing client's typed secret.
    /// - Returns: Unsafe DELETE requiring strictly empty HTTP 204 success and invalidating token-scoped response reads.
    /// - Throws: Descriptor errors now; expiry, missing response, API/transport/cancellation or indeterminate deletion later.
    public static func deleteOriginalResponse(applicationID: ApplicationID, token: InteractionToken) throws -> Endpoint<EmptyResponse> {
        try responseEndpoint("DELETE", applicationID: applicationID, token: token, message: "@original",
            successStatuses: [204], decode: { try EmptyResponse(data: $0) })
    }

    /// Creates one follow-up message; Discord always waits and returns its Message rather than an empty response.
    /// - Parameters:
    ///   - applicationID: Application owning the interaction and continuation credential.
    ///   - token: Exact continuation token, valid for fifteen minutes and matching the dedicated client credential.
    ///   - request: Validated follow-up fields; username/avatar/thread overrides are deliberately unavailable.
    ///   - files: At most ten bounded replayable uploads, with actual placeholder associations validated before I/O.
    ///   - uploadLimits: Per-file/request/chunk caps, default MessageUpload limits; account/channel allowances are explicit caller input.
    /// - Returns: Unsafe HTTP 200 POST /webhooks/{application.id}/{interaction.token}; no wait override is exposed.
    /// - Throws: Local payload/upload errors now; expired token, user-install five-follow-up quota, API/transport or indeterminate errors later.
    ///   Directly following a deferred-channel response this route has deprecated edit-original behavior; use editOriginalResponse explicitly.
    public static func createFollowup(applicationID: ApplicationID, token: InteractionToken,
        request: InteractionMessageCreate, files: [MessageUploadFile] = [],
        uploadLimits: MessageUploadLimits = .default) throws -> Endpoint<Message> {
        guard Set(files.map(\.id)).count == files.count else { throw DiscordError.validation(.invalidValue) }
        let payload = try request.jsonValue(uploadIDs: files.map(\.id), uploadContentTypes: Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.contentType) }))
        return try responseEndpoint("POST", applicationID: applicationID, token: token,
            body: MessageUpload.body(payload: payload, files: files, limits: uploadLimits), decode: { try Message(data: $0) })
    }

    /// Retrieves one follow-up using the originating interaction token and Discord's current message-access checks.
    /// - Parameters:
    ///   - applicationID: Owning application identifier.
    ///   - token: Exact continuation path credential matching the executing client.
    ///   - messageID: Exact follow-up snowflake; no original-message alias or hidden lookup is performed.
    ///   - readPolicy: Optional token-scoped read policy, default in-flight coalescing without completed caching.
    /// - Returns: Safe HTTP 200 GET and complete Message projection.
    /// - Throws: Descriptor errors now; expired token, inaccessible/missing response, API/transport/cancellation/schema failures later.
    public static func getFollowup(applicationID: ApplicationID, token: InteractionToken, messageID: MessageID,
        readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Message> {
        try responseEndpoint("GET", applicationID: applicationID, token: token, message: messageID.description,
            readPolicy: readPolicy, decode: { try Message(data: $0) })
    }

    /// Edits one follow-up while preserving explicit attachment-retention and nullable field semantics.
    /// - Parameters:
    ///   - applicationID: Application owning the interaction continuation.
    ///   - token: Exact unexpired path secret, matching the executing client's typed credential.
    ///   - messageID: Follow-up message identifier; original response editing has a separate explicit operation.
    ///   - request: Validated partial update; deferredResponse=true is rejected because only originals complete defers.
    ///   - files: New bounded replayable uploads, all explicitly listed in attachment metadata.
    ///   - uploadLimits: Independent file/request/chunk limits, default MessageUpload bounds.
    /// - Returns: Unsafe HTTP 200 PATCH with updated Message and token-scoped response-read invalidation.
    /// - Throws: Local payload/upload/context errors now; expiry/access/missing/API/transport/indeterminate errors later.
    public static func editFollowup(applicationID: ApplicationID, token: InteractionToken, messageID: MessageID,
        request: InteractionMessageEdit, files: [MessageUploadFile] = [],
        uploadLimits: MessageUploadLimits = .default) throws -> Endpoint<Message> {
        guard !request.deferredResponse else { throw DiscordError.validation(.invalidValue) }
        return try responseEndpoint("PATCH", applicationID: applicationID, token: token, message: messageID.description,
            body: upload(request: request, files: files, limits: uploadLimits), decode: { try Message(data: $0) })
    }

    /// Deletes one follow-up, including an ephemeral follow-up, using its valid originating interaction token.
    /// Discord added ephemeral original/follow-up deletion on 2022-10-20; ambiguous mutations remain indeterminate.
    /// - Parameters:
    ///   - applicationID: Owning application identifier, used as the webhook major-resource partition.
    ///   - token: Unexpired interaction continuation credential matching the dedicated client.
    ///   - messageID: Exact follow-up message snowflake.
    /// - Returns: Unsafe DELETE requiring strictly empty HTTP 204 success.
    /// - Throws: Descriptor errors now; token expiry, inaccessible/missing response or API/transport/indeterminate errors later.
    public static func deleteFollowup(applicationID: ApplicationID, token: InteractionToken, messageID: MessageID) throws -> Endpoint<EmptyResponse> {
        try responseEndpoint("DELETE", applicationID: applicationID, token: token, message: messageID.description,
            successStatuses: [204], decode: { try EmptyResponse(data: $0) })
    }

    /// Constructs the shared initial-callback route, ensuring only normalized placeholders reach rate-limit metadata.
    /// - Parameters:
    ///   - interactionID: Exact received interaction identifier.
    ///   - token: Typed path secret and required matching execution credential.
    ///   - response: Callback envelope validated against optional triggering-kind context.
    ///   - interactionType: Optional triggering kind; nil performs payload-only validation.
    ///   - files: Finite replayable upload sources; duplicate placeholders fail before dictionary construction.
    ///   - uploadLimits: Complete bounded upload policy.
    ///   - withResponse: False selects empty 204; true adds with_response=true and selects typed 200.
    ///   - decode: Exact complete-body decoder for the selected result contract.
    /// - Returns: Globally exempt, unsafe callback descriptor without Authorization or cache eligibility.
    /// - Throws: Safe duplicate-file, payload, upload or descriptor validation errors before opening file sources.
    private static func callback<T: Sendable>(interactionID: InteractionID, token: InteractionToken,
        response: InteractionResponse, interactionType: InteractionType?, files: [MessageUploadFile],
        uploadLimits: MessageUploadLimits, withResponse: Bool,
        decode: @escaping @Sendable (Data) throws -> T) throws -> Endpoint<T> {
        guard Set(files.map(\.id)).count == files.count else { throw DiscordError.validation(.invalidValue) }
        let payload = try response.jsonValue(interactionType: interactionType, uploadIDs: files.map(\.id),
            uploadContentTypes: Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.contentType) }))
        return try token.withUnsafeValue { raw in
            try Endpoint(method: "POST", path: ["interactions", interactionID.description, raw, "callback"],
                route: "/interactions/{interaction.id}/{interaction.token}/callback",
                query: withResponse ? [.init(name: "with_response", value: "true")] : [],
                authentication: .none, pathCredential: .interaction(token), successStatuses: withResponse ? [200] : [204],
                usesGlobalLimit: false, body: MessageUpload.body(payload: payload, files: files, limits: uploadLimits),
                retrySafety: .unsafe, decode: decode)
        }
    }

    /// Builds an original/follow-up descriptor with token-scoped read reduction and conservative mutation ordering.
    /// - Parameters:
    ///   - method: GET, POST, PATCH or DELETE; only GET is safe/reusable.
    ///   - applicationID: Owning application in the webhook route's major resource position.
    ///   - token: Typed path credential required by the executing client.
    ///   - message: Nil selects follow-up creation; @original selects original, otherwise an exact message snowflake.
    ///   - body: Already validated bounded body; nil for reads/deletion.
    ///   - successStatuses: Exact expected statuses, default HTTP 200.
    ///   - readPolicy: Optional read reuse, wrapped with credential-scoped response invalidation tags.
    ///   - decode: Synchronous complete-body typed response decoder.
    /// - Returns: Versioned descriptor, globally exempt and carrying no Authorization header or secret rate/cache labels.
    /// - Throws: Descriptor/read-policy validation errors before any task, I/O or admission reservation is created.
    private static func responseEndpoint<T: Sendable>(_ method: String, applicationID: ApplicationID, token: InteractionToken,
        message: String? = nil, body: RequestBody? = nil, successStatuses: Set<Int> = [200],
        readPolicy: ReadPolicy? = nil, decode: @escaping @Sendable (Data) throws -> T) throws -> Endpoint<T> {
        let suffix = message.map { ["messages", $0] } ?? []
        let route = "/webhooks/{application.id}/{interaction.token}" +
            (message == nil ? "" : message == "@original" ? "/messages/@original" : "/messages/{message.id}")
        let tags: Set<String> = ["interaction-responses:\(applicationID)"]
        return try token.withUnsafeValue { raw in
            try Endpoint(method: method, path: ["webhooks", applicationID.description, raw] + suffix, route: route,
                authentication: .none, pathCredential: .interaction(token), successStatuses: successStatuses,
                majorParameter: applicationID.description, usesGlobalLimit: false, body: body,
                retrySafety: method == "GET" ? .safe : .unsafe,
                readPolicy: method == "GET" ? readPolicy.map { ReadPolicy(coalescing: $0.coalescing, timeToLive: $0.timeToLive, tags: $0.tags.union(tags)) } : nil,
                invalidates: method == "GET" ? [] : tags, decode: decode)
        }
    }

    /// Validates upload associations for a partial update before constructing replayable bounded multipart framing.
    /// - Parameters:
    ///   - request: Complete explicit retained/new attachment metadata and nullable edit fields.
    ///   - files: Finite replayable new files; duplicate IDs fail before dictionary creation.
    ///   - limits: Positive independent file/request/chunk bounds.
    /// - Returns: JSON-only or lazy multipart body owned by each transmitted attempt.
    /// - Throws: Safe file/attachment/payload/bounds errors without opening any file source.
    private static func upload(request: InteractionMessageEdit, files: [MessageUploadFile], limits: MessageUploadLimits) throws -> RequestBody {
        guard Set(files.map(\.id)).count == files.count else { throw DiscordError.validation(.invalidValue) }
        let payload = try request.jsonValue(uploadIDs: files.map(\.id),
            uploadContentTypes: Dictionary(uniqueKeysWithValues: files.map { ($0.id, $0.contentType) }))
        return try MessageUpload.body(payload: payload, files: files, limits: limits)
    }
}
