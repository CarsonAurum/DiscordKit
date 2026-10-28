// File: Tests/DiscordHTTPTests/InteractionEndpointTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Verifies all eight documented interaction operations and both strict initial-callback result contracts.
@Suite struct InteractionEndpointTests {
    /// Every descriptor uses API v10, the exact path credential, safe normalized rate metadata and explicit result status.
    /// Token endpoints never send an Authorization header and all interaction operations opt out of global limits.
    /// - Parameter index: Stable index in the complete nine-descriptor catalog.
    /// - Throws: Unexpected descriptor/wire/decode failures fail the test.
    @Test(arguments: 0..<9) func catalogDescriptors(index: Int) throws {
        let (endpoint, bytes) = try Self.catalog()[index]
        let credential = Credential.interaction(try Self.token())
        let request = try endpoint.makeRequest(credential: credential, userAgent: "DiscordBot (https://example.test, 1)")
        let methods = ["POST", "POST", "GET", "PATCH", "DELETE", "POST", "GET", "PATCH", "DELETE"]
        let paths = ["interactions/18446744073709551615/\(Self.tokenText)/callback", "interactions/18446744073709551615/\(Self.tokenText)/callback",
                     "webhooks/9007199254740993/\(Self.tokenText)/messages/@original", "webhooks/9007199254740993/\(Self.tokenText)/messages/@original",
                     "webhooks/9007199254740993/\(Self.tokenText)/messages/@original", "webhooks/9007199254740993/\(Self.tokenText)",
                     "webhooks/9007199254740993/\(Self.tokenText)/messages/18446744073709551615",
                     "webhooks/9007199254740993/\(Self.tokenText)/messages/18446744073709551615",
                     "webhooks/9007199254740993/\(Self.tokenText)/messages/18446744073709551615"]
        #expect(endpoint.method == methods[index])
        #expect(request.url.path == "/api/v10/" + paths[index])
        #expect(request.url.host == "discord.com")
        #expect(request.url.scheme == "https")
        #expect(request.url.absoluteString.contains("synthetic-interaction%25token%3F%2Bsecret"))
        #expect(endpoint.authentication == .none)
        #expect(!request.headers.contains { $0.name.lowercased() == "authorization" })
        #expect(!endpoint.usesGlobalLimit)
        #expect(!endpoint.route.contains(Self.tokenText))
        #expect(endpoint.route.contains("{interaction.token}"))
        #expect(endpoint.majorParameter == (index < 2 ? nil : "9007199254740993"))
        #expect(endpoint.retrySafety == (methods[index] == "GET" ? .safe : .unsafe))
        #expect(endpoint.successStatuses == ([0, 4, 8].contains(index) ? [204] : [200]))
        #expect(endpoint.readPolicy == nil || methods[index] == "GET")
        #expect(endpoint.invalidates.isEmpty == (methods[index] == "GET" || index < 2))
        #expect(endpoint.query == (index == 1 ? [.init(name: "with_response", value: "true")] : []))
        #expect(try endpoint.decode(bytes) == bytes)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try endpoint.decode(Data("null".utf8)) }
        #expect(!String(describing: endpoint).contains(Self.tokenText))
        #expect(!String(reflecting: endpoint).contains(Self.tokenText))
        #expect(endpoint.customMirror.children.count == 1)
    }

    /// Wrong credential categories and different secrets fail before request construction even though the header policy is none.
    /// - Parameter index: All callback/original/follow-up operations.
    /// - Throws: Unexpected descriptor/fixture setup failures fail the test.
    @Test(arguments: 0..<9) func exactPathCredentialRequired(index: Int) throws {
        let endpoint = try Self.catalog()[index].0
        for credential in [Credential.none, .bot(try BotToken("bot")), .bearer(try BearerToken("bearer")),
                           .interaction(try InteractionToken("other")), .webhook(.init(rawValue: 9), try WebhookToken(Self.tokenText))] {
            #expect(throws: DiscordError.validation(.missingValue)) {
                try endpoint.makeRequest(credential: credential, userAgent: "DiscordBot (https://example.test, 1)")
            }
        }
    }

    /// Reads preserve explicit coalescing/TTL/custom tags and nil disables reuse; mutations share response invalidation.
    /// Context-incompatible deferred-original poll edits cannot be sent through follow-up routes.
    /// - Throws: Unexpected descriptor/fixture construction errors fail the test.
    @Test func readPolicyAndContext() throws {
        let token = try Self.token(), app = ApplicationID(rawValue: 5)
        let read = try InteractionEndpoints.getOriginalResponse(applicationID: app, token: token,
            readPolicy: ReadPolicy(coalescing: false, timeToLive: .seconds(2), tags: ["custom"]))
        #expect(read.readPolicy?.coalescing == false)
        #expect(read.readPolicy?.timeToLive == .seconds(2))
        #expect(read.readPolicy?.tags == ["custom", "interaction-responses:5"])
        #expect(try InteractionEndpoints.getOriginalResponse(applicationID: app, token: token, readPolicy: nil).readPolicy == nil)
        #expect(try InteractionEndpoints.getFollowup(applicationID: app, token: token, messageID: .init(rawValue: 1), readPolicy: nil).readPolicy == nil)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try InteractionEndpoints.editFollowup(applicationID: app, token: token, messageID: .init(rawValue: 1),
                request: InteractionMessageEdit(deferredResponse: true))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try InteractionEndpoints.createResponse(interactionID: .init(rawValue: 1), token: token, response: .pong, interactionType: .applicationCommand)
        }
        for unsafe in ["a/b", "a\\b", ".", ".."] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try InteractionEndpoints.getOriginalResponse(applicationID: app, token: InteractionToken(unsafe))
            }
        }
    }

    /// Callback, original edit and follow-up bodies use bounded replayable multipart with the correct nested envelope.
    /// Sources are opened lazily by attempts, and file bytes remain outside payload_json.
    /// - Parameter kind: Callback empty/result, original edit, follow-up create or follow-up edit.
    /// - Throws: Unexpected fixture/body/collection failures fail the test.
    @Test(arguments: 0..<5) func multipartBodies(kind: Int) async throws {
        let file = try MessageUploadFile(id: 0, filename: "upload.txt", bytes: Data("file payload".utf8))
        let metadata = try MessageAttachmentRequest(id: .upload(0), filename: "upload.txt", description: "description")
        let create = try InteractionMessageCreate(attachments: .value([metadata]), flags: .value(.ephemeral))
        let edit = try InteractionMessageEdit(attachments: .value([metadata]))
        let token = try Self.token(), app = ApplicationID(rawValue: 2)
        let endpoint: Endpoint<Data>
        switch kind {
        case 0: endpoint = try Self.erase(InteractionEndpoints.createResponse(interactionID: .init(rawValue: 1), token: token, response: .message(create), files: [file]))
        case 1: endpoint = try Self.erase(InteractionEndpoints.createResponseWithResult(interactionID: .init(rawValue: 1), token: token, response: .message(create), files: [file]))
        case 2: endpoint = try Self.erase(InteractionEndpoints.editOriginalResponse(applicationID: app, token: token, request: edit, files: [file]))
        case 3: endpoint = try Self.erase(InteractionEndpoints.createFollowup(applicationID: app, token: token, request: create, files: [file]))
        default: endpoint = try Self.erase(InteractionEndpoints.editFollowup(applicationID: app, token: token, messageID: .init(rawValue: 3), request: edit, files: [file]))
        }
        let body = try #require(endpoint.body)
        #expect(body.isStreaming)
        #expect(body.contentType.hasPrefix("multipart/form-data; boundary="))
        let first = try await ResponseBody.collect(body.makeStream(), maximumBytes: body.accountedBytes)
        let second = try await ResponseBody.collect(body.makeStream(), maximumBytes: body.accountedBytes)
        #expect(first == second)
        #expect(first.count <= body.accountedBytes)
        let text = try #require(String(data: first, encoding: .utf8))
        #expect(text.contains("name=\"payload_json\""))
        #expect(text.contains("name=\"files[0]\"; filename=\"upload.txt\""))
        #expect(text.contains("file payload"))
        #expect(text.contains("\"attachments\":[{\"description\":\"description\",\"filename\":\"upload.txt\",\"id\":0}]"))
        #expect(text.contains("\"data\":") == (kind < 2))
        #expect(text.contains("\"flags\":64") == (kind < 2 || kind == 3))
    }

    /// Duplicate/unmatched attachment IDs and admission limits fail synchronously before lazy file producers are opened.
    /// Callbacks without message data cannot attach files, and per-request bounds remain independent of binary length.
    /// - Throws: Unexpected valid setup or laziness failures fail the test.
    @Test func uploadFailuresAndLaziness() throws {
        let token = try Self.token(), app = ApplicationID(rawValue: 2)
        let lazy = try MessageUploadFile(id: 0, filename: "lazy", maximumBytes: 10) { throw TransportFailure.closed }
        let request = try InteractionMessageCreate()
        #expect(try InteractionEndpoints.createFollowup(applicationID: app, token: token, request: request, files: [lazy]).body?.isStreaming == true)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try InteractionEndpoints.createFollowup(applicationID: app, token: token, request: request, files: [lazy, lazy])
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try InteractionEndpoints.createResponse(interactionID: .init(rawValue: 1), token: token, response: .message(request), files: [lazy, lazy])
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try InteractionEndpoints.createResponse(interactionID: .init(rawValue: 1), token: token, response: .deferredMessage(), files: [lazy])
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try InteractionEndpoints.editOriginalResponse(applicationID: app, token: token, request: InteractionMessageEdit(), files: [lazy, lazy])
        }
        #expect(throws: DiscordError.validation(.missingValue)) {
            try InteractionEndpoints.editOriginalResponse(applicationID: app, token: token, request: InteractionMessageEdit(), files: [lazy])
        }
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try InteractionEndpoints.createFollowup(applicationID: app, token: token, request: request, files: [lazy],
                uploadLimits: MessageUploadLimits(maximumFileBytes: 9))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try InteractionEndpoints.createFollowup(applicationID: app, token: token, request: request, files: [lazy],
                uploadLimits: MessageUploadLimits(maximumRequestBytes: 0))
        }
    }

    /// Builds every descriptor in a stable order, retaining each production response decoder in the erased catalog.
    /// - Returns: Callback204/callback200/originalGET/PATCH/DELETE/follow-upPOST/GET/PATCH/DELETE and success fixtures.
    /// - Throws: Descriptor, token or request-model validation errors if the written contracts regress.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let token = try token(), app = ApplicationID(rawValue: 9_007_199_254_740_993)
        let id = InteractionID(rawValue: UInt64.max), message = MessageID(rawValue: UInt64.max)
        let create = try InteractionMessageCreate(content: .value("response"), flags: .value(.ephemeral))
        let edit = try InteractionMessageEdit(content: .value("edited"))
        let bytes = Data(messageJSON.utf8)
        return [
            (try erase(InteractionEndpoints.createResponse(interactionID: id, token: token, response: .message(create), interactionType: .applicationCommand)), Data()),
            (try erase(InteractionEndpoints.createResponseWithResult(interactionID: id, token: token, response: .message(create))),
             Data(#"{"interaction":{"id":"18446744073709551615","type":2}}"#.utf8)),
            (try erase(InteractionEndpoints.getOriginalResponse(applicationID: app, token: token)), bytes),
            (try erase(InteractionEndpoints.editOriginalResponse(applicationID: app, token: token, request: edit)), bytes),
            (try erase(InteractionEndpoints.deleteOriginalResponse(applicationID: app, token: token)), Data()),
            (try erase(InteractionEndpoints.createFollowup(applicationID: app, token: token, request: create)), bytes),
            (try erase(InteractionEndpoints.getFollowup(applicationID: app, token: token, messageID: message)), bytes),
            (try erase(InteractionEndpoints.editFollowup(applicationID: app, token: token, messageID: message, request: edit)), bytes),
            (try erase(InteractionEndpoints.deleteFollowup(applicationID: app, token: token, messageID: message)), Data())]
    }

    /// Erases a typed result for complete catalog-wide pipeline tests while preserving every production policy and decoder.
    /// - Parameter endpoint: Typed immutable production descriptor.
    /// - Returns: Equivalent Data descriptor that validates the original schema before returning exact bytes.
    /// - Throws: Descriptor validation errors if any policy cannot be preserved identically.
    static func erase<T: Sendable>(_ endpoint: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, pathCredential: endpoint.pathCredential, successStatuses: endpoint.successStatuses,
            majorParameter: endpoint.majorParameter, usesGlobalLimit: endpoint.usesGlobalLimit, auditReason: endpoint.auditReason,
            body: endpoint.body, headers: endpoint.headers, retrySafety: endpoint.retrySafety, readPolicy: endpoint.readPolicy,
            invalidates: endpoint.invalidates, bulk: endpoint.bulk, decode: { _ = try endpoint.decode($0); return $0 })
    }

    /// Constructs a synthetic typed token containing reserved URL characters to verify exactly-once path encoding.
    /// - Returns: Finite, nonproduction test credential without whitespace or controls.
    /// - Throws: Credential validation errors if the fixture violates the public secret contract.
    static func token() throws -> InteractionToken { try InteractionToken(tokenText) }
    /// Explicit synthetic token; no test sends it to Discord or another network origin.
    static let tokenText = "synthetic-interaction%token?+secret"
    /// Complete independently authored Message fixture for original/follow-up response decoding.
    static let messageJSON = #"{"id":"18446744073709551615","channel_id":"4","author":{"id":"5","username":"user","discriminator":"0","avatar":null},"content":"response","timestamp":"2026-10-16T12:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":20}"#
}
