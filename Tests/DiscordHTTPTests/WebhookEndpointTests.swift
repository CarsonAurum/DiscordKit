import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Complete webhook descriptor and snapshot workflow contracts without network or real credentials.
@Suite struct WebhookEndpointTests {
    /// All 15 route families and native/compatibility wait variants declare exact HTTP, route and credential contracts.
    /// - Throws: Unexpected fixture/descriptor/decoder errors fail the test.
    @Test func completeCatalog() throws {
        let entries = try Self.catalog()
        #expect(entries.count == 18)
        let methods = ["POST", "GET", "GET", "GET", "GET", "PATCH", "PATCH", "DELETE", "DELETE", "POST", "POST", "POST", "POST", "POST", "POST", "GET", "PATCH", "DELETE"]
        let paths = ["channels/2/webhooks", "channels/2/webhooks", "guilds/3/webhooks", "webhooks/18446744073709551615",
            "webhooks/18446744073709551615/private-token", "webhooks/18446744073709551615", "webhooks/18446744073709551615/private-token",
            "webhooks/18446744073709551615", "webhooks/18446744073709551615/private-token",
            "webhooks/18446744073709551615/private-token", "webhooks/18446744073709551615/private-token",
            "webhooks/18446744073709551615/private-token/slack", "webhooks/18446744073709551615/private-token/slack",
            "webhooks/18446744073709551615/private-token/github", "webhooks/18446744073709551615/private-token/github",
            "webhooks/18446744073709551615/private-token/messages/4", "webhooks/18446744073709551615/private-token/messages/4",
            "webhooks/18446744073709551615/private-token/messages/4"]
        let statuses = [200, 200, 200, 200, 200, 200, 200, 204, 204, 204, 200, 200, 200, 204, 204, 200, 200, 204]
        for (index, item) in entries.enumerated() {
            let endpoint = item.0
            let reading = [1, 2, 3, 4, 15].contains(index)
            #expect(endpoint.method == methods[index])
            #expect(endpoint.path.joined(separator: "/") == paths[index])
            #expect(endpoint.successStatuses == [statuses[index]])
            #expect(endpoint.usesGlobalLimit)
            #expect(endpoint.majorParameter == (index < 2 ? "2" : index == 2 ? "3" : "18446744073709551615"))
            #expect(endpoint.retrySafety == (reading ? .safe : .unsafe))
            #expect((endpoint.readPolicy != nil) == reading)
            #expect(endpoint.invalidates == (reading ? [] : ["webhook-catalog"]))
            #expect(!endpoint.route.contains("private-token"))
            #expect(!String(reflecting: endpoint).contains("private-token"))
            if endpoint.authentication == .none {
                #expect(endpoint.pathCredential != nil)
                #expect(endpoint.route.contains("{webhook.token}"))
            } else { #expect(endpoint.pathCredential == nil && endpoint.authentication == .bot) }
            #expect(try endpoint.decode(item.1) == item.1)
            let request = try endpoint.makeRequest(credential: Self.credential(endpoint), userAgent: "test")
            #expect(request.url.absoluteString.hasPrefix("https://discord.com/api/v10/" + paths[index]))
            #expect(request.headers.contains { $0.name.lowercased() == "authorization" } == (endpoint.authentication == .bot))
        }
    }

    /// Token descriptors demand exact credential type, webhook ID and token before headers/body ownership are created.
    /// - Throws: Unexpected fixture/descriptor errors fail this test; wrong credentials and unsafe path tokens are asserted.
    @Test func credentialBindingPoliciesAndPaths() throws {
        for (endpoint, _) in try Self.catalog() where endpoint.authentication == .none {
            for credential in [Credential.none, .bot(try BotToken("private-token")),
                               .bearer(try BearerToken("private-token")), .interaction(try InteractionToken("private-token")),
                               .webhook(.init(rawValue: 1), try WebhookToken("private-token")),
                               .webhook(.init(rawValue: UInt64.max), try WebhookToken("other"))] {
                #expect(throws: DiscordError.validation(.missingValue)) { try endpoint.makeRequest(credential: credential, userAgent: "test") }
            }
        }
        for value in [".", "..", "a/b", "a\\b"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookEndpoints.getWithToken(webhookID: .init(rawValue: 1), token: WebhookToken(value)) }
        }
        let id = WebhookID(rawValue: UInt64.max), token = try WebhookToken("private-token")
        let read = try WebhookEndpoints.getWithToken(webhookID: id, token: token,
            readPolicy: ReadPolicy(coalescing: false, timeToLive: .seconds(2), tags: ["caller"]))
        #expect(read.readPolicy?.coalescing == false && read.readPolicy?.timeToLive == .seconds(2))
        #expect(read.readPolicy?.tags == ["caller", "webhook-catalog"])
        #expect(try WebhookEndpoints.get(webhookID: id, readPolicy: nil).readPolicy == nil)
        #expect(try WebhookEndpoints.channel(channelID: .init(rawValue: 1), readPolicy: nil).readPolicy == nil)
        #expect(try WebhookEndpoints.guild(guildID: .init(rawValue: 1), readPolicy: nil).readPolicy == nil)
        #expect(throws: DiscordError.validation(.invalidValue)) { try WebhookEndpoints.getWithToken(webhookID: id, token: token, readPolicy: ReadPolicy(timeToLive: .zero)) }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try WebhookEndpoints.modifyWithToken(webhookID: id, token: token, request: WebhookModify(channelID: .value(.init(rawValue: 1))))
        }
    }

    /// Wait=false and compatibility acknowledgements preserve their real status/body contracts and exact query spellings.
    /// - Throws: Unexpected valid descriptors fail this test; mismatched response bodies are asserted.
    @Test func waitCompatibilityAndThreadQueries() throws {
        let id = WebhookID(rawValue: UInt64.max), token = try WebhookToken("private-token")
        let ordinary = try WebhookExecute(message: MessageCreate(content: .value("hello")))
        let noWait = try WebhookEndpoints.execute(webhookID: id, token: token, request: ordinary)
        #expect(noWait.query == [.init(name: "wait", value: "false"), .init(name: "with_components", value: "false")])
        #expect(try noWait.decode(Data()) == .unconfirmed)
        #expect(throws: DiscordError.transport(.invalidResponse)) { try noWait.decode(Self.message) }
        let waited = try WebhookEndpoints.execute(webhookID: id, token: token, request: ordinary, wait: true,
            threadID: .init(rawValue: UInt64.max), isForumOrMedia: true)
        #expect(waited.query == [.init(name: "wait", value: "true"), .init(name: "thread_id", value: "18446744073709551615"), .init(name: "with_components", value: "false")])
        if case .message(let message) = try waited.decode(Self.message) { #expect(message.content == "hello") }
        else { Issue.record("Expected a confirmed message") }
        #expect(throws: (any Error).self) { try waited.decode(Data()) }
        let slack = try WebhookEndpoints.executeSlack(webhookID: id, token: token, request: WebhookSlackExecute(text: .value("hello")))
        #expect(slack.query == [.init(name: "wait", value: "true")])
        #expect(try slack.decode(Data("null".utf8)) == .null)
        #expect(try slack.decode(Data(#""ok""#.utf8)) == .value("ok"))
        for value in ["{}", "[]", "true", "1"] { #expect(throws: DiscordError.transport(.invalidResponse)) { try slack.decode(Data(value.utf8)) } }
        let github = try WebhookEndpoints.executeGitHub(webhookID: id, token: token, event: .push, request: Self.github())
        #expect(github.query == [.init(name: "wait", value: "true")])
        #expect(github.headers == [.init(name: "X-GitHub-Event", value: "push")])
        #expect(throws: DiscordError.transport(.invalidResponse)) { try github.decode(Self.message) }
        #expect(try WebhookEndpoints.message(webhookID: id, token: token, messageID: .init(rawValue: 4), threadID: .init(rawValue: 8)).query == [.init(name: "thread_id", value: "8")])
    }

    /// Snapshot helpers skip exact requested name/channel/null-avatar changes but always submit nonnull image uploads.
    /// - Throws: Unexpected valid requests fail this test; illegal token channel movement and audit reasons are asserted.
    @Test func snapshotReconciliation() throws {
        let current = try Webhook(data: Data(Self.webhook.utf8)), token = try WebhookToken("private-token")
        for request in [try WebhookModify(), try WebhookModify(name: .value("private-name")), try WebhookModify(avatar: .null)] {
            #expect(try WebhookOperations.modifyIfChanged(current: current, request: request) == nil)
            #expect(try WebhookOperations.modifyWithTokenIfChanged(current: current, token: token, request: request) == nil)
        }
        for request in [try WebhookModify(name: .value("changed")), try WebhookModify(avatar: .value("YQ=="))] {
            #expect(try WebhookOperations.modifyIfChanged(current: current, request: request) != nil)
            #expect(try WebhookOperations.modifyWithTokenIfChanged(current: current, token: token, request: request) != nil)
        }
        var fields = current.withUnsafeFields { $0 }
        fields["avatar"] = .string("YQ==")
        let misleading = try Webhook(data: JSONValue.object(fields).serialized())
        #expect(try WebhookOperations.modifyIfChanged(current: misleading, request: WebhookModify(avatar: .value("YQ=="))) != nil)
        #expect(try WebhookOperations.modifyWithTokenIfChanged(current: misleading, token: token, request: WebhookModify(avatar: .value("YQ=="))) != nil)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try WebhookOperations.modifyWithTokenIfChanged(current: current, token: token, request: WebhookModify(channelID: .value(.init(rawValue: 2))))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try WebhookOperations.modifyIfChanged(current: current, request: WebhookModify(), auditReason: String(repeating: "x", count: 513))
        }
    }

    /// Builds every current route plus all wait variants with independent status-appropriate response fixtures.
    /// - Returns: Stable 18-item catalog retaining each production typed decoder through type erasure.
    /// - Throws: Fixture/request/descriptor errors; no I/O, tasks or body producers start here.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let id = WebhookID(rawValue: UInt64.max), token = try WebhookToken("private-token"), bytes = Data(webhook.utf8)
        let request = try WebhookExecute(message: MessageCreate(content: .value("hello")))
        return [
            (try erase(WebhookEndpoints.create(channelID: .init(rawValue: 2), request: WebhookCreate(name: "created"), auditReason: "reason + audit")), bytes),
            (try erase(WebhookEndpoints.channel(channelID: .init(rawValue: 2))), Data(("[" + webhook + "]").utf8)),
            (try erase(WebhookEndpoints.guild(guildID: .init(rawValue: 3))), Data("[]".utf8)),
            (try erase(WebhookEndpoints.get(webhookID: id)), bytes),
            (try erase(WebhookEndpoints.getWithToken(webhookID: id, token: token)), bytes),
            (try erase(WebhookEndpoints.modify(webhookID: id, request: WebhookModify(name: .value("changed")), auditReason: "reason + audit")), bytes),
            (try erase(WebhookEndpoints.modifyWithToken(webhookID: id, token: token, request: WebhookModify(avatar: .null))), bytes),
            (try erase(WebhookEndpoints.delete(webhookID: id, auditReason: "reason + audit")), Data()),
            (try erase(WebhookEndpoints.deleteWithToken(webhookID: id, token: token)), Data()),
            (try erase(WebhookEndpoints.execute(webhookID: id, token: token, request: request)), Data()),
            (try erase(WebhookEndpoints.execute(webhookID: id, token: token, request: request, wait: true)), message),
            (try erase(WebhookEndpoints.executeSlack(webhookID: id, token: token, request: WebhookSlackExecute(text: .value("hello")))), Data(#""ok""#.utf8)),
            (try erase(WebhookEndpoints.executeSlack(webhookID: id, token: token, request: WebhookSlackExecute(text: .value("hello")), wait: false)), Data("null".utf8)),
            (try erase(WebhookEndpoints.executeGitHub(webhookID: id, token: token, event: .push, request: github())), Data()),
            (try erase(WebhookEndpoints.executeGitHub(webhookID: id, token: token, event: .issues, request: github(), wait: false)), Data()),
            (try erase(WebhookEndpoints.message(webhookID: id, token: token, messageID: .init(rawValue: 4))), message),
            (try erase(WebhookEndpoints.editMessage(webhookID: id, token: token, messageID: .init(rawValue: 4), request: WebhookMessageEdit(content: .value("hello")))), message),
            (try erase(WebhookEndpoints.deleteMessage(webhookID: id, token: token, messageID: .init(rawValue: 4))), Data()),
        ]
    }

    /// Constructs a minimal valid typed GitHub delivery with exact integer sender identity and URI metadata.
    /// - Returns: Sender-only request; event-dependent eligibility remains a server check.
    /// - Throws: Unexpected static fixture validation errors.
    static func github() throws -> WebhookGitHubExecute {
        try WebhookGitHubExecute(sender: WebhookGitHubUser(id: 1, login: "sender", htmlURL: "https://github.com/sender", avatarURL: "https://example.com/avatar"))
    }

    /// Returns matching synthetic credentials for either bot management or path-token descriptors.
    /// - Parameter endpoint: Catalog item with production auth/path policy retained.
    /// - Returns: Bot token or exact webhook credential; no production token is used.
    /// - Throws: Unexpected synthetic credential construction errors.
    static func credential<T>(_ endpoint: Endpoint<T>) throws -> Credential {
        if let credential = endpoint.pathCredential { return credential }
        return .bot(try BotToken("synthetic"))
    }

    /// Retains exact production policy and validates the original decoder before returning response bytes.
    /// - Parameter endpoint: Immutable typed production descriptor.
    /// - Returns: Byte-returning descriptor with path credential, status and rate/read/mutation semantics preserved.
    /// - Throws: Descriptor metadata validation errors during faithful reconstruction.
    static func erase<T>(_ endpoint: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, pathCredential: endpoint.pathCredential, successStatuses: endpoint.successStatuses,
            majorParameter: endpoint.majorParameter, usesGlobalLimit: endpoint.usesGlobalLimit,
            auditReason: endpoint.auditReason, body: endpoint.body, headers: endpoint.headers,
            retrySafety: endpoint.retrySafety, readPolicy: endpoint.readPolicy, invalidates: endpoint.invalidates,
            bulk: endpoint.bulk, decode: { _ = try endpoint.decode($0); return $0 })
    }

    /// Independent incoming webhook fixture includes all required nullable keys and an intentionally private token.
    static let webhook = #"{"id":"18446744073709551615","type":1,"channel_id":"2","name":"private-name","avatar":null,"application_id":null,"token":"private-token"}"#
    /// Independent complete Message fixture avoids any live API request or hidden related-resource hydration.
    static let message = Data(#"{"id":"4","channel_id":"2","author":{"id":"1","username":"author","discriminator":"0","avatar":null},"content":"hello","timestamp":"2026-10-16T00:00:00Z","edited_timestamp":null,"tts":false,"mention_everyone":false,"mentions":[],"mention_roles":[],"attachments":[],"embeds":[],"pinned":false,"type":0}"#.utf8)
}
