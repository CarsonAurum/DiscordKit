import DiscordCore
import DiscordHTTP
import DiscordModels
import DiscordTestSupport
import DiscordTransport
import Foundation
import Testing
@testable import DiscordSocial

/// Synthetic HTTP integration verifies public user grants stay distinct from application-bot authority.
@Suite(.timeLimit(.minutes(1))) struct SocialHTTPProviderTests {
    static let user = #"{"id":"18446744073709551615","username":"player","discriminator":"0","global_name":null,"avatar":null}"#
    static let lobby = #"{"id":"18446744073709551615","application_id":"1","metadata":null,"members":[]}"#
    static let message = #"{"id":"18446744073709551615","type":0,"content":"hello","lobby_id":"18446744073709551615","channel_id":"18446744073709551615","author":{"id":"1","username":"player","discriminator":"0","global_name":null,"avatar":null},"flags":0,"application_id":"1","lobby_member":{"additional_name":"Player"}}"#

    /// All user operations retain exact routes, bounded bodies, maximum snowflakes and bearer authentication.
    /// Construction remains inert and the wrapper never closes application-owned HTTP authorities.
    /// - Throws: Unexpected fixture, descriptor or response failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func userOperations() async throws {
        let methods = ["GET", "PUT", "PATCH", "PATCH", "POST", "GET", "POST", "DELETE"]
        let paths = ["/users/@me", "/lobbies", "/lobbies/18446744073709551615/channel-linking",
            "/lobbies/18446744073709551615/channel-linking", "/lobbies/18446744073709551615/messages",
            "/lobbies/18446744073709551615/messages", "/lobbies/18446744073709551615/members/@me/invites",
            "/lobbies/18446744073709551615/members/@me"]
        let bodies = [Self.user, Self.lobby, Self.lobby, Self.lobby, Self.message, "[\(Self.message)]", #"{"code":"one-use"}"#, ""]
        let transport = try ScriptedHTTPTransport(steps: paths.indices.map { index in { request in
            #expect(request.method == methods[index])
            #expect(request.url.path == "/api/v10" + paths[index])
            #expect(request.headers.contains { $0.name.lowercased() == "authorization" && $0.value == "Bearer user-grant" })
            if index == 1 {
                let data = try await ResponseBody.collect(request.body, maximumBytes: 4096)
                #expect(try JSONValue.parse(data) == .object(["secret": .string("lobby-secret")]))
            }
            if index == 2 {
                let data = try await ResponseBody.collect(request.body, maximumBytes: 4096)
                #expect(try JSONValue.parse(data) == .object(["channel_id": .string("18446744073709551615")]))
            }
            if index == 3 {
                let data = try await ResponseBody.collect(request.body, maximumBytes: 4096)
                #expect(try JSONValue.parse(data) == .object([:]))
            }
            if index == 5 { #expect(request.url.query == "limit=200") }
            return try Self.response(bodies[index], status: index == 4 ? 201 : index == 7 ? 204 : 200,
                                     bucket: request.method + request.url.path)
        } })
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bearer(try BearerToken("user-grant")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock)
        let provider = SocialHTTPProvider(client: client)
        #expect(provider.profileRequirements == .init(scopes: ["identify"]))
        #expect(provider.lobbyRequirements == .init(scopes: ["sdk.social_layer"]))
        #expect(await transport.executionCount == 0)
        let context = TransportContext(clock: clock), id = LobbyID(rawValue: .max)
        #expect(try await provider.currentProfile(context: context).id.rawValue == .max)
        #expect(try await provider.createOrJoinLobby(.init(secret: "lobby-secret"), context: context).id == id)
        #expect(try await provider.linkChannel(lobbyID: id, channelID: .init(rawValue: .max), context: context).id == id)
        #expect(try await provider.unlinkChannel(lobbyID: id, context: context).id == id)
        #expect(try await provider.sendLobbyMessage(lobbyID: id, request: .init(content: "hello"), context: context).content == "hello")
        #expect(try await provider.lobbyMessages(lobbyID: id, limit: 200, context: context).count == 1)
        #expect(try await provider.createLinkedChannelInvite(lobbyID: id, context: context).code == "one-use")
        try await provider.leaveLobby(id, context: context)
        #expect(await transport.executionCount == 8)
        #expect(await coordinator.snapshot().activeCount == 0)
        await coordinator.close()
    }

    /// Ordinary bot credentials cannot satisfy the user-profile or lobby bearer contract, even though
    /// the underlying current-user REST endpoint independently permits bot accounts.
    /// - Throws: Unexpected fixture construction failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func botNeverSubstitutesForUserConsent() async throws {
        let transport = try ScriptedHTTPTransport(steps: [])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("application-bot")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock)
        let provider = SocialHTTPProvider(client: client), context = TransportContext(clock: clock)
        await #expect(throws: DiscordError.validation(.missingValue)) { try await provider.currentProfile(context: context) }
        await #expect(throws: DiscordError.validation(.missingValue)) {
            try await provider.createOrJoinLobby(.init(secret: "secret"), context: context)
        }
        await #expect(throws: DiscordError.validation(.invalidValue)) {
            try await provider.lobbyMessages(lobbyID: .init(rawValue: 1), limit: 201, context: context)
        }
        #expect(await transport.executionCount == 0)
        await coordinator.close()
    }

    /// Identity/profile equivalents retain bot-only authentication, exact external keys and nullable updates.
    /// Both lookup routes are separate from account linking, and deletes target one explicitly selected key.
    /// - Throws: Unexpected valid execution or decoding failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func applicationIdentityOperations() async throws {
        let paths = ["/users/2/application-identities/1", "/applications/1/application-identities/NONE/external-key",
            "/applications/1/users/2/identities/external-key/profile", "/applications/1/users/2/identities/external-key/profile",
            "/users/2/application-identities/1/NONE/external-key/delete"]
        let methods = ["GET", "GET", "GET", "PATCH", "POST"]
        let transport = try ScriptedHTTPTransport(steps: paths.indices.map { index in { request in
            #expect(request.url.path == "/api/v10" + paths[index])
            #expect(request.method == methods[index])
            #expect(request.headers.contains { $0.name.lowercased() == "authorization" && $0.value == "Bot application-bot" })
            if index == 3 {
                let bytes = try await ResponseBody.collect(request.body, maximumBytes: 4096)
                #expect(try JSONValue.parse(bytes) == .object(["username": .string("New name")]))
            }
            return try Self.response(index < 2 ? #"{"identities":[]}"# : index == 2 ? #"{"username":null,"metadata":null,"data":null}"# : "",
                                     status: index >= 3 ? 204 : 200, bucket: request.method + request.url.path)
        } })
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bot(try BotToken("application-bot")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock)
        let provider = SocialHTTPApplicationProvider(applicationID: .init(rawValue: 1), client: client)
        #expect(provider.applicationID.rawValue == 1)
        #expect(provider.identityRequirements == .init(scopes: ["application_identities.write"]))
        let context = TransportContext(clock: clock), userID = UserID(rawValue: 2)
        let key = try ApplicationIdentityKey(providerType: "NONE", providerIssuedUserID: "external-key")
        #expect(try await provider.identities(userID: userID, context: context).identities.isEmpty)
        #expect(try await provider.identities(key: key, context: context).identities.isEmpty)
        #expect(try await provider.profile(userID: userID, providerIssuedUserID: "external-key", context: context).username == .null)
        #expect(try await provider.updateProfile(userID: userID, providerIssuedUserID: "external-key",
            request: .init(username: .value("New name")), context: context) == .null)
        try await provider.deleteIdentity(userID: userID, key: key, context: context)
        #expect(await transport.executionCount == 5)
        await coordinator.close()
    }

    /// Expired deadlines, cancellation, malformed responses and forbidden bot endpoints do not become successes.
    /// The user wrapper preserves the existing pipeline's finite, nonreplaying failure behavior.
    /// - Throws: Unexpected fixture or task failures fail the test.
    @available(macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2, *)
    @Test func failureBoundaries() async throws {
        let transport = try ScriptedHTTPTransport(steps: [{ _ in try Self.response("{}") }])
        let clock = ManualClock()
        let coordinator = RateLimitCoordinator(clock: clock)
        let client = RESTClient(credential: .bearer(try BearerToken("user-grant")), identity: RateLimitIdentity(),
            transport: transport, coordinator: coordinator, clock: clock)
        let provider = SocialHTTPProvider(client: client)
        await #expect(throws: TransportFailure.deadlineExceeded) {
            try await provider.currentProfile(context: .init(clock: clock, deadline: clock.now))
        }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await provider.currentProfile(context: .init(clock: clock))
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.executionCount == 0)
        await #expect(throws: DiscordError.transport(.invalidResponse)) {
            try await provider.currentProfile(context: .init(clock: clock))
        }
        let application = SocialHTTPApplicationProvider(applicationID: .init(rawValue: 1), client: client)
        await #expect(throws: DiscordError.validation(.missingValue)) {
            try await application.identities(userID: .init(rawValue: 2), context: .init(clock: clock))
        }
        #expect(await transport.executionCount == 1)
        await coordinator.close()
    }

    /// Materializes one bounded response stream; no fixture contacts Discord or owns hidden background work.
    /// - Parameters:
    ///   - text: Exact UTF-8 response, including empty body for 204.
    ///   - status: Explicit synthetic HTTP status, default 200.
    ///   - bucket: Stable method/route-specific synthetic hash; distinct routes must not create false bucket merges.
    /// - Returns: A fresh single-consumer response body.
    /// - Throws: Request-body validation errors for a malformed fixture configuration.
    private static func response(_ text: String, status: Int = 200, bucket: String = "synthetic-social-bucket") throws -> HTTPResponse {
        HTTPResponse(status: status, headers: [
            .init(name: "X-RateLimit-Bucket", value: bucket),
            .init(name: "X-RateLimit-Limit", value: "100"),
            .init(name: "X-RateLimit-Remaining", value: "99"),
            .init(name: "X-RateLimit-Reset-After", value: "1")],
            body: try RequestBody(bytes: Data(text.utf8), contentType: "application/json").makeStream())
    }
}
