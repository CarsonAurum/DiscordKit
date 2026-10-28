// File: Tests/DiscordGameServicesTests/PartnerAccountTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordHTTP
import DiscordModels
import DiscordOAuth
import Foundation
import Testing
@testable import DiscordGameServices

/// Offline published partner wire contracts, input bounds and secret redaction.
@Suite struct PartnerAccountTests {
    static let tokenJSON = #"{"access_token":"partner-access-sensitive","id_token":"identity-sensitive","token_type":"Bearer","expires_in":3600,"scope":"sdk.social_layer","future":{"x":true}}"#

    /// Bot creation retains exact external IDs and optional names, uses API v10 and rejects unrelated credential kinds.
    /// - Throws: Unexpected descriptor/encoding failures fail the test.
    @Test func botProvisioning() throws {
        for name in [nil, "Player 雪"] as [String?] {
            let endpoint = try PartnerAccountEndpoints.provisionalBot(externalUserID: "external/雪?value", preferredGlobalName: name)
            #expect(endpoint.method == "POST" && endpoint.path == ["partner-sdk", "token", "bot"])
            #expect(endpoint.authentication == .bot && endpoint.retrySafety == .unsafe && endpoint.readPolicy == nil)
            var expected: [String: JSONValue] = ["external_user_id": .string("external/雪?value")]
            if let name { expected["preferred_global_name"] = .string(name) }
            #expect(try JSONValue.parse(#require(endpoint.body?.storedBodyBytes)) == .object(expected))
            let request = try endpoint.makeRequest(credential: .bot(try BotToken("synthetic")), userAgent: "tests")
            #expect(request.url.absoluteString == "https://discord.com/api/v10/partner-sdk/token/bot")
            #expect(throws: DiscordError.validation(.missingValue)) {
                try endpoint.makeRequest(credential: .bearer(try BearerToken("synthetic")), userAgent: "tests")
            }
        }
    }

    /// External exchange/unmerge and publisher exchange place every credential in bounded redacted bodies.
    /// - Throws: Unexpected descriptor/request/parser failures fail the test.
    @Test func externalPublisherAndUnmergeContracts() throws {
        let app = ApplicationID(rawValue: UInt64.max), secret = try ClientSecret("client-sensitive")
        let proof = try ExternalAccountToken("external-sensitive")
        let external = try PartnerAccountEndpoints.provisionalExternal(applicationID: app, clientSecret: secret,
            externalAuthType: "FUTURE_PROVIDER", externalAuthToken: proof)
        let unmerge = try PartnerAccountEndpoints.unmergeExternal(applicationID: app, clientSecret: secret,
            externalAuthType: "FUTURE_PROVIDER", externalAuthToken: proof)
        #expect(external.path == ["partner-sdk", "token"] && external.authentication == .none)
        #expect(unmerge.path == ["partner-sdk", "provisional-accounts", "unmerge"] && unmerge.authentication == .none)
        #expect(external.body?.storedBodyBytes == unmerge.body?.storedBodyBytes)
        #expect(try JSONValue.parse(#require(external.body?.storedBodyBytes)) == .object([
            "client_id": .string(app.description), "client_secret": .string("client-sensitive"),
            "external_auth_type": .string("FUTURE_PROVIDER"), "external_auth_token": .string("external-sensitive")]))
        let child = try PartnerAccountEndpoints.publisherChild(parentAccessToken: .init("parent-sensitive"),
            childApplicationID: app, parentClientSecret: secret)
        #expect(child.path == ["partner-sdk", "child-token"] && child.authentication == .none)
        #expect(try JSONValue.parse(#require(child.body?.storedBodyBytes)) == .object([
            "parent_access_token": .string("parent-sensitive"), "child_application_id": .string(app.description),
            "parent_client_secret": .string("client-sensitive")]))
        let request = try child.makeRequest(credential: .none, userAgent: "tests")
        #expect(!request.headers.contains { $0.name.lowercased() == "authorization" })
        #expect(try child.decode(Data(Self.tokenJSON.utf8)).token.refreshToken == nil)
        let refreshing = Data(#"{"access_token":"synthetic","refresh_token":"refresh-sensitive","token_type":"Bearer","expires_in":60,"scope":"sdk.social_layer"}"#.utf8)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try child.decode(refreshing) }
        #expect(try external.decode(refreshing).token.refreshToken != nil)
        let botUnmerge = try PartnerAccountEndpoints.unmergeBot(externalUserID: "account-key")
        #expect(botUnmerge.path == ["partner-sdk", "provisional-accounts", "unmerge", "bot"])
        #expect(botUnmerge.authentication == .bot && botUnmerge.successStatuses == Set(200...299))
        #expect(try botUnmerge.decode(Data()).value == nil)
        #expect(try botUnmerge.decode(Data(#"{"accepted":true}"#.utf8)).value == .object(["accepted": .bool(true)]))
        #expect(throws: JSONValueError.self) { try botUnmerge.decode(Data("malformed".utf8)) }
        for value in [String(describing: external), String(reflecting: external), String(describing: child.body),
                      String(reflecting: Mirror(reflecting: child))] {
            for sensitive in ["client-sensitive", "external-sensitive", "parent-sensitive"] { #expect(!value.contains(sensitive)) }
        }
    }

    /// Required token fields and optional redacted identity tokens reject malformed/null/oversized JSON.
    /// - Throws: Unexpected token parser errors fail the test.
    @Test func tokenAndAcknowledgementParsing() throws {
        let response = try PartnerTokenResponse(data: Data(Self.tokenJSON.utf8))
        #expect(response.identityToken?.withUnsafeValue { $0 } == "identity-sensitive")
        let child = try PartnerTokenResponse(data: Data(#"{"access_token":"child","token_type":"Bearer","expires_in":60,"scope":"sdk.social_layer"}"#.utf8))
        #expect(child.identityToken == nil)
        for invalid in ["[]", "{}", "null", Self.tokenJSON.replacingOccurrences(of: #""identity-sensitive""#, with: "null"),
                        Self.tokenJSON.replacingOccurrences(of: #""identity-sensitive""#, with: #""bad token""#)] {
            #expect(throws: (any Error).self) { try PartnerTokenResponse(data: Data(invalid.utf8)) }
        }
        #expect(throws: JSONValueError.maximumBytesExceeded) {
            try PartnerTokenResponse(data: Data(String(repeating: " ", count: 65_537).utf8))
        }
        let acknowledgement = try PartnerAccountAcknowledgement(data: Data(#"{"private":"ack-sensitive"}"#.utf8))
        for value in [String(describing: response), String(reflecting: response), String(describing: acknowledgement),
                      String(reflecting: acknowledgement)] {
            #expect(!value.contains("identity-sensitive") && !value.contains("partner-access-sensitive") && !value.contains("ack-sensitive"))
        }
        #expect(Mirror(reflecting: response).children.count == 1 && Mirror(reflecting: acknowledgement).children.count == 1)
    }

    /// Console merge uses the published device grant and percent-encodes external access proofs once in a redacted form.
    /// - Throws: Unexpected form/descriptor/decoder failures fail the test.
    @Test func deviceMerge() throws {
        let endpoint = try PartnerAccountEndpoints.mergeDeviceCode(applicationID: .init(rawValue: 1),
            clientSecret: .init("secret"), deviceCode: .init("device+code"),
            externalAuthType: "DISCORD_BOT_ISSUED_ACCESS_TOKEN", externalAuthToken: .init("access+token&proof"))
        #expect(endpoint.path == ["oauth2", "token"] && endpoint.authentication == .none && endpoint.retrySafety == .unsafe)
        let form = String(decoding: try #require(endpoint.body?.storedBodyBytes), as: UTF8.self)
        #expect(form.contains("grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Adevice_code"))
        #expect(form.contains("device_code=device%2Bcode") && form.contains("external_auth_token=access%2Btoken%26proof"))
        #expect(!form.contains("external_user_id"))
        _ = try endpoint.decode(Data(Self.tokenJSON.utf8))
    }

    /// Input boundaries reject empty/controls/oversized values before retaining or executing a partner request.
    /// - Throws: Unexpected setup failures fail the test.
    @Test func localValidation() throws {
        for external in ["", "bad\nidentity", String(repeating: "x", count: 4_097)] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try PartnerAccountEndpoints.provisionalBot(externalUserID: external) }
            #expect(throws: DiscordError.validation(.invalidValue)) { try PartnerAccountEndpoints.unmergeBot(externalUserID: external) }
        }
        for name in ["", "bad\nname", String(repeating: "x", count: 33)] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try PartnerAccountEndpoints.provisionalBot(externalUserID: "id", preferredGlobalName: name)
            }
        }
        _ = try PartnerAccountEndpoints.provisionalBot(externalUserID: String(repeating: "x", count: 4_096),
            preferredGlobalName: String(repeating: "x", count: 32))
        for provider in ["", "x\n", String(repeating: "x", count: 129)] {
            #expect(throws: DiscordError.validation(.invalidValue)) {
                try PartnerAccountEndpoints.provisionalExternal(applicationID: .init(rawValue: 1), clientSecret: .init("secret"),
                    externalAuthType: provider, externalAuthToken: .init("token"))
            }
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try PartnerAccountEndpoints.publisherChild(parentAccessToken: .init(String(repeating: "x", count: 32_769)),
                childApplicationID: .init(rawValue: 1), parentClientSecret: .init("secret"))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try PartnerAccountEndpoints.provisionalExternal(applicationID: .init(rawValue: 0), clientSecret: .init("secret"),
                externalAuthType: "OIDC", externalAuthToken: .init("proof"))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try PartnerAccountEndpoints.unmergeExternal(applicationID: .init(rawValue: 0), clientSecret: .init("secret"),
                externalAuthType: "OIDC", externalAuthToken: .init("proof"))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try PartnerAccountEndpoints.publisherChild(parentAccessToken: .init("parent"), childApplicationID: .init(rawValue: 0),
                parentClientSecret: .init("secret"))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try PartnerAccountEndpoints.mergeDeviceCode(applicationID: .init(rawValue: 0), clientSecret: .init("secret"),
                deviceCode: .init("device"), externalAuthType: "OIDC", externalAuthToken: .init("proof"))
        }
    }

}
