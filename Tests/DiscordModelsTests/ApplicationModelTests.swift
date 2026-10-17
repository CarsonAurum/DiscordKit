import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Application-owned written schemas, preview extensions and forward compatibility use finite offline fixtures.
@Suite struct ApplicationModelTests {
    /// Every field checks required/optional/nullability and wrong roots independently, including nested ownership.
    /// - Throws: Unexpected trusted fixture parsing errors fail this test; sanitized schema failures are asserted.
    @Test func everyFieldContract() throws {
        for (text, fields, parse) in Self.schemas {
            guard case .object(let fixture) = try JSONValue.parse(text) else { Issue.record("Expected fixture object"); continue }
            for (key, optional, nullable) in fields {
                var changed = fixture
                changed[key] = nil
                let omitted = try JSONValue.object(changed).serialized()
                if optional { #expect(try parse(omitted, .default).rawFields[key] == nil) }
                else { #expect(throws: DiscordError.transport(.invalidResponse)) { try parse(omitted, .default) } }
                changed[key] = .null
                let null = try JSONValue.object(changed).serialized()
                if nullable { #expect(try parse(null, .default).rawFields[key] == .null) }
                else { #expect(throws: DiscordError.transport(.invalidResponse)) { try parse(null, .default) } }
                changed[key] = .bool(true)
                if fixture[key] == .bool(true) || fixture[key] == .bool(false) { changed[key] = .string("wrong") }
                #expect(throws: DiscordError.transport(.invalidResponse)) {
                    try parse(JSONValue.object(changed).serialized(), .default)
                }
            }
        }
    }

    /// All model public parsers enforce complete document bounds, preserve exact unknown values and redact diagnostics.
    /// - Throws: Unexpected fixture errors fail this test; malformed roots, parser limits and syntax errors are asserted.
    @Test func boundsRawFieldsAndDiagnostics() throws {
        for (text, _, parse) in Self.schemas {
            let bytes = Data(text.utf8)
            let value = try parse(bytes, .default)
            #expect(value.jsonValue() == (try JSONValue.parse(bytes)))
            #expect(!String(describing: value).contains("private"))
            #expect(!String(reflecting: value).contains("private"))
            #expect(Mirror(reflecting: value).children.count == 1)
            #expect(throws: JSONValueError.maximumBytesExceeded) { try parse(bytes, JSONLimits(maximumBytes: 1)) }
            #expect(throws: JSONValueError.maximumNodesExceeded) { try parse(bytes, JSONLimits(maximumNodes: 1)) }
            #expect(throws: JSONValueError.self) { try parse(Data("{".utf8), .default) }
            for wrong in ["null", "[]", "1", "true"] {
                #expect(throws: DiscordError.transport(.invalidResponse)) { try parse(Data(wrong.utf8), .default) }
            }
            guard case .object(var fields) = try JSONValue.parse(bytes) else { continue }
            fields["future"] = try JSONValue.parse(#"{"number":1.2300,"huge":123456789012345678901234567890}"#)
            let retained = try parse(JSONValue.object(fields).serialized(), .default)
            let raw = try #require(retained.rawFields["future"])
            #expect(String(decoding: try raw.serialized(), as: UTF8.self).contains("1.2300"))
            #expect(String(decoding: try raw.serialized(), as: UTF8.self).contains("123456789012345678901234567890"))
            #expect(throws: JSONValueError.maximumDepthExceeded) {
                try parse(JSONValue.object(fields).serialized(), JSONLimits(maximumDepth: 1))
            }
        }
    }

    /// Complete Application values expose all current written fields and explicit preview additions without narrowing IDs/flags.
    /// - Throws: Unexpected model/fixture failures fail this test.
    @Test func completeApplicationAndOwnedValues() throws {
        let value = try Application(data: Data(Self.application.utf8))
        #expect(value.id.rawValue == .max && value.name == "private-app")
        #expect(value.icon == .null && value.applicationDescription == "private-description")
        #expect(value.botPublic && !value.botRequireCodeGrant && value.verifyKey == "public-key")
        #expect(value.rpcOrigins == .value(["https://example.test"]))
        #expect(value.termsOfServiceURL == .value("https://example.test/terms"))
        #expect(value.privacyPolicyURL == .value("https://example.test/privacy"))
        #expect(value.guildID == .value(.init(rawValue: UInt64.max)))
        #expect(value.primarySKUID == .value(.init(rawValue: UInt64.max)))
        #expect(value.slug == .value("private-slug") && value.coverImage == .value("hash"))
        #expect(value.flags == .value(8192))
        #expect(value.flagsNew == .value("340282366920938463463374607431768211455"))
        #expect(value.approximateGuildCount == .value(4) && value.approximateUserInstallCount == .value(5))
        #expect(value.approximateUserAuthorizationCount == .value(6))
        #expect(value.redirectURIs == .value(["https://example.test/redirect"]))
        #expect(value.interactionsEndpointURL == .null && value.roleConnectionsVerificationURL == .null && value.eventWebhooksURL == .null)
        #expect(value.eventWebhooksStatus == .value(.init(.disabled)))
        #expect(value.eventWebhooksTypes == .value(["APPLICATION_AUTHORIZED"]) && value.tags == .value(["utility"]))
        #expect(value.customInstallURL == .value("https://example.test/install"))
        #expect(value.type == .value(.init(.guildRoleSubscriptions)) && value.maxParticipants == .null)
        #expect(value.explicitContentFilter == .value(.init(.inherit)))
        #expect(value.conjureProjectID == .value(.init(rawValue: 1)) && value.vibegrationsProjectID == .value(.init(rawValue: 2)))
        #expect(value.eligibleOAuth2Scopes == .value(["identify", "future"]))
        guard case .value(let bot) = value.bot, case .value(let owner) = value.owner,
              case .value(let guild) = value.guild, case .value(let install) = value.installParams,
              case .value(let configs) = value.integrationTypesConfig, case .value(let team) = value.teamDetails else {
            Issue.record("Expected all populated nested values"); return
        }
        #expect(bot.username == .value("private-user") && owner.id.rawValue == .max)
        #expect(guild.id.rawValue == .max && guild.name == .value("private-guild") && guild.icon == .null)
        #expect(install.scopes == ["applications.commands", "bot"] && install.permissions.count > 20)
        #expect(configs["99"]?.oauth2InstallParams == .absent)
        #expect(configs["0"]?.oauth2InstallParams == .value(install))
        #expect(team.id.rawValue == .max && team.icon == .null && team.name == "private-team")
        #expect(team.ownerUserID.rawValue == .max && team.members.count == 1)
        #expect(team.members.first?.membershipState == .init(.accepted))
        #expect(team.members.first?.teamID == team.id && team.members.first?.user.id == team.ownerUserID)
        #expect(team.members.first?.role == .value(.init(.developer)))
        #expect(team.members.first?.permissions == .value(["*"]))
        #expect(value.team == .value(team.jsonValue()))
        #expect(value == (try Application(data: Data(Self.application.utf8))))
        #expect(try ApplicationUser(data: Data(#"{"id":"1"}"#.utf8)).username == .absent)
        #expect(try ApplicationIntegrationTypeConfiguration(data: Data("{}".utf8)).oauth2InstallParams == .absent)
    }

    /// Future raw enum values, installation contexts, unlimited-width bit strings and location kinds survive exactly.
    /// Malformed flag/permission digits, fractional enums and invalid nested arrays fail with safe errors.
    /// - Throws: Unexpected trusted fixture errors fail this test.
    @Test func futureAndMalformedValues() throws {
        var fields = try Self.object(Self.application)
        fields["type"] = .number(try JSONNumber(rawValue: "99"))
        fields["event_webhooks_status"] = .number(try JSONNumber(rawValue: "99"))
        fields["explicit_content_filter"] = .number(try JSONNumber(rawValue: "99"))
        fields["flags_new"] = .string(String(repeating: "9", count: 1000))
        let future = try Application(data: JSONValue.object(fields).serialized())
        #expect(future.type == .value(.init(rawValue: 99)))
        #expect(future.eventWebhooksStatus == .value(.init(rawValue: 99)))
        #expect(future.explicitContentFilter == .value(.init(rawValue: 99)))
        #expect(future.flagsNew == .value(String(repeating: "9", count: 1000)))
        for digits in ["", "-1", "+1", "1.0", "1e2", " 1", "١"] {
            fields["flags_new"] = .string(digits)
            #expect(throws: DiscordError.transport(.invalidResponse)) { try Application(data: JSONValue.object(fields).serialized()) }
            #expect(throws: DiscordError.transport(.invalidResponse)) {
                try ApplicationInstallParams(data: JSONValue.object(["scopes": .array([]), "permissions": .string(digits)]).serialized())
            }
        }
        for key in ["type", "event_webhooks_status", "approximate_user_authorization_count", "flags"] {
            var changed = try Self.object(Self.application)
            changed[key] = .number(try JSONNumber(rawValue: "1.00000000000000001"))
            #expect(throws: DiscordError.transport(.invalidResponse)) { try Application(data: JSONValue.object(changed).serialized()) }
        }
        let instance = try ApplicationActivityInstance(data: Data(Self.activity.utf8))
        #expect(instance.applicationID.rawValue == .max && instance.launchID.rawValue == .max)
        #expect(instance.instanceID == "opaque-instance" && instance.users.map(\.rawValue) == [UInt64.max])
        #expect(instance.location.kind.knownValue == .guildChannel)
        #expect(instance.location.guildID == .value(.init(rawValue: UInt64.max)))
        for kind in ["pc", "party", "future"] {
            let location = try ApplicationActivityLocation(data: JSONValue.object([
                "id": .string("private"), "kind": .string(kind), "channel_id": .string("1"), "guild_id": .null]).serialized())
            #expect(location.kind.rawValue == kind && location.guildID == .null)
        }
        #expect(try ApplicationActivityLocation(data: Data(#"{"id":"dm","kind":"pc","channel_id":"1"}"#.utf8)).guildID == .absent)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try Application(data: Data(Self.application.replacingOccurrences(of: "\"members\":[{", with: "\"members\":[null,{").utf8)) }
    }

    /// Named legacy flag combinations preserve unknown bits; writable filtering is independently tested in requests.
    @Test func knownFlagsAndEnums() {
        let values: [ApplicationFlags] = [.autoModerationRuleCreateBadge, .gatewayPresence, .gatewayPresenceLimited,
            .gatewayGuildMembers, .gatewayGuildMembersLimited, .verificationPendingGuildLimit, .embedded,
            .gatewayMessageContent, .gatewayMessageContentLimited, .applicationCommandBadge]
        #expect(values.map(\.rawValue) == [6, 12, 13, 14, 15, 16, 17, 18, 19, 23].map { UInt64(1) << $0 })
        #expect(ApplicationFlags(rawValue: UInt64.max).contains(.gatewayPresenceLimited))
        #expect(ApplicationIntegrationType.allCases.map(\.rawValue) == [0, 1])
        #expect(ApplicationTeamRole(rawValue: "read_only") == .readOnly)
        #expect(ApplicationTeamMembershipState(rawValue: 1) == .invited)
        #expect(ApplicationActivityLocationKind(rawValue: "party") == .party)
    }

    /// Parses one independently authored trusted fixture object for controlled schema mutations.
    /// - Parameter text: Complete fixture JSON object string.
    /// - Returns: Exact object fields without normalization.
    /// - Throws: Fixture syntax errors or safe invalid-response errors for an accidental nonobject fixture.
    private static func object(_ text: String) throws -> [String: JSONValue] {
        guard case .object(let fields) = try JSONValue.parse(text) else { throw DiscordError.transport(.invalidResponse) }
        return fields
    }

    /// Independent complete Application resource fixture, including optional preview fields.
    static let application = #"{"id":"18446744073709551615","name":"private-app","icon":null,"description":"private-description","bot_public":true,"bot_require_code_grant":false,"verify_key":"public-key","team":{"id":"18446744073709551615","icon":null,"name":"private-team","owner_user_id":"18446744073709551615","members":[{"membership_state":2,"team_id":"18446744073709551615","user":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null,"bot":true,"system":false,"flags":64,"public_flags":1024},"role":"developer","permissions":["*"]}]},"rpc_origins":["https://example.test"],"bot":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null,"bot":true,"system":false,"flags":64,"public_flags":1024},"terms_of_service_url":"https://example.test/terms","privacy_policy_url":"https://example.test/privacy","owner":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null,"bot":true,"system":false,"flags":64,"public_flags":1024},"guild_id":"18446744073709551615","guild":{"id":"18446744073709551615","name":"private-guild","icon":null,"description":null,"features":["COMMUNITY"]},"primary_sku_id":"18446744073709551615","slug":"private-slug","cover_image":"hash","flags":8192,"flags_new":"340282366920938463463374607431768211455","approximate_guild_count":4,"approximate_user_install_count":5,"approximate_user_authorization_count":6,"redirect_uris":["https://example.test/redirect"],"interactions_endpoint_url":null,"role_connections_verification_url":null,"event_webhooks_url":null,"event_webhooks_status":1,"event_webhooks_types":["APPLICATION_AUTHORIZED"],"tags":["utility"],"install_params":{"scopes":["applications.commands","bot"],"permissions":"340282366920938463463374607431768211455"},"integration_types_config":{"0":{"oauth2_install_params":{"scopes":["applications.commands","bot"],"permissions":"340282366920938463463374607431768211455"}},"99":{}},"custom_install_url":"https://example.test/install","type":4,"max_participants":null,"explicit_content_filter":0,"conjure_project_id":"1","vibegrations_project_id":"2","eligible_oauth2_scopes":["identify","future"]}"#

    /// Independent complete finite Activity instance fixture.
    static let activity = #"{"application_id":"18446744073709551615","instance_id":"opaque-instance","launch_id":"18446744073709551615","location":{"id":"gc-private","kind":"gc","channel_id":"18446744073709551615","guild_id":"18446744073709551615"},"users":["18446744073709551615"]}"#

    /// Schema fixtures and field-presence expectations authored separately from production parsing.
    static let schemas: [(String, [(String, Bool, Bool)], @Sendable (Data, JSONLimits) throws -> any MessageResponseValue)] = [
        (#"{"id":"18446744073709551615","name":"private-app","icon":null,"description":"private-description","bot_public":true,"bot_require_code_grant":false,"verify_key":"public-key","team":{"id":"18446744073709551615","icon":null,"name":"private-team","owner_user_id":"18446744073709551615","members":[{"membership_state":2,"team_id":"18446744073709551615","user":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null,"bot":true,"system":false,"flags":64,"public_flags":1024},"role":"developer","permissions":["*"]}]},"rpc_origins":["https://example.test"],"bot":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null,"bot":true,"system":false,"flags":64,"public_flags":1024},"terms_of_service_url":"https://example.test/terms","privacy_policy_url":"https://example.test/privacy","owner":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null,"bot":true,"system":false,"flags":64,"public_flags":1024},"guild_id":"18446744073709551615","guild":{"id":"18446744073709551615","name":"private-guild","icon":null,"description":null,"features":["COMMUNITY"]},"primary_sku_id":"18446744073709551615","slug":"private-slug","cover_image":"hash","flags":8192,"flags_new":"340282366920938463463374607431768211455","approximate_guild_count":4,"approximate_user_install_count":5,"approximate_user_authorization_count":6,"redirect_uris":["https://example.test/redirect"],"interactions_endpoint_url":null,"role_connections_verification_url":null,"event_webhooks_url":null,"event_webhooks_status":1,"event_webhooks_types":["APPLICATION_AUTHORIZED"],"tags":["utility"],"install_params":{"scopes":["applications.commands","bot"],"permissions":"340282366920938463463374607431768211455"},"integration_types_config":{"0":{"oauth2_install_params":{"scopes":["applications.commands","bot"],"permissions":"340282366920938463463374607431768211455"}},"99":{}},"custom_install_url":"https://example.test/install","type":4,"max_participants":null,"explicit_content_filter":0,"conjure_project_id":"1","vibegrations_project_id":"2","eligible_oauth2_scopes":["identify","future"]}"#, [("id", false, false), ("name", false, false), ("icon", false, true), ("description", false, false), ("bot_public", false, false), ("bot_require_code_grant", false, false), ("verify_key", false, false), ("team", false, true), ("rpc_origins", true, false), ("bot", true, false), ("terms_of_service_url", true, false), ("privacy_policy_url", true, false), ("owner", true, false), ("guild_id", true, false), ("guild", true, false), ("primary_sku_id", true, false), ("slug", true, false), ("cover_image", true, false), ("flags", true, false), ("flags_new", true, false), ("approximate_guild_count", true, false), ("approximate_user_install_count", true, false), ("approximate_user_authorization_count", true, false), ("redirect_uris", true, false), ("interactions_endpoint_url", true, true), ("role_connections_verification_url", true, true), ("event_webhooks_url", true, true), ("event_webhooks_status", true, false), ("event_webhooks_types", true, false), ("tags", true, false), ("install_params", true, false), ("integration_types_config", true, false), ("custom_install_url", true, false), ("type", true, true), ("max_participants", true, true), ("explicit_content_filter", true, false), ("conjure_project_id", true, false), ("vibegrations_project_id", true, false), ("eligible_oauth2_scopes", true, false)], { try Application(data: $0, limits: $1) }),
        (#"{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null,"bot":true,"system":false,"flags":64,"public_flags":1024}"#, [("id", false, false), ("username", true, false), ("discriminator", true, false), ("global_name", true, true), ("avatar", true, true), ("bot", true, false), ("system", true, false), ("flags", true, false), ("public_flags", true, false)], { try ApplicationUser(data: $0, limits: $1) }),
        (#"{"id":"18446744073709551615","name":"private-guild","icon":null,"description":null,"features":["COMMUNITY"]}"#, [("id", false, false), ("name", true, false), ("icon", true, true), ("description", true, true), ("features", true, false)], { try ApplicationGuild(data: $0, limits: $1) }),
        (#"{"scopes":["applications.commands","bot"],"permissions":"340282366920938463463374607431768211455"}"#, [("scopes", false, false), ("permissions", false, false)], { try ApplicationInstallParams(data: $0, limits: $1) }),
        (#"{"oauth2_install_params":{"scopes":["applications.commands","bot"],"permissions":"340282366920938463463374607431768211455"}}"#, [("oauth2_install_params", true, false)], { try ApplicationIntegrationTypeConfiguration(data: $0, limits: $1) }),
        (#"{"id":"18446744073709551615","icon":null,"name":"private-team","owner_user_id":"18446744073709551615","members":[{"membership_state":2,"team_id":"18446744073709551615","user":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null,"bot":true,"system":false,"flags":64,"public_flags":1024},"role":"developer","permissions":["*"]}]}"#, [("id", false, false), ("icon", false, true), ("name", false, false), ("owner_user_id", false, false), ("members", false, false)], { try ApplicationTeam(data: $0, limits: $1) }),
        (#"{"membership_state":2,"team_id":"18446744073709551615","user":{"id":"18446744073709551615","username":"private-user","discriminator":"0","global_name":null,"avatar":null,"bot":true,"system":false,"flags":64,"public_flags":1024},"role":"developer","permissions":["*"]}"#, [("membership_state", false, false), ("team_id", false, false), ("user", false, false), ("role", true, false), ("permissions", true, false)], { try ApplicationTeamMember(data: $0, limits: $1) }),
        (#"{"application_id":"18446744073709551615","instance_id":"opaque-instance","launch_id":"18446744073709551615","location":{"id":"gc-private","kind":"gc","channel_id":"18446744073709551615","guild_id":"18446744073709551615"},"users":["18446744073709551615"]}"#, [("application_id", false, false), ("instance_id", false, false), ("launch_id", false, false), ("location", false, false), ("users", false, false)], { try ApplicationActivityInstance(data: $0, limits: $1) }),
        (#"{"id":"gc-private","kind":"gc","channel_id":"18446744073709551615","guild_id":"18446744073709551615"}"#, [("id", false, false), ("kind", false, false), ("channel_id", false, false), ("guild_id", true, true)], { try ApplicationActivityLocation(data: $0, limits: $1) }),
    ]
}
