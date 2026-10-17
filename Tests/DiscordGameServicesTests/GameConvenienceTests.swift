import DiscordCore
import DiscordHTTP
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordGameServices

/// Snapshot-based request reduction preserves full stats replacement and silent partial lobby acknowledgements.
@Suite struct GameConvenienceTests {
    /// Equal/absent profile fields make no request; a changed data object remains a complete replacement.
    /// - Throws: Unexpected model/request/descriptor errors fail the test.
    @Test func profileReplacement() throws {
        let profile = try ApplicationIdentityProfile(data: Data(#"{"username":"player","metadata":null,"data":{"primary":{"season":"old"}}}"#.utf8))
        let app = ApplicationID(rawValue: 1), user = UserID(rawValue: 2)
        #expect(try GameServiceOperations.profileIfChanged(applicationID: app, userID: user,
            providerIssuedUserID: "external", current: profile, request: .init()) == nil)
        #expect(try GameServiceOperations.profileIfChanged(applicationID: app, userID: user,
            providerIssuedUserID: "external", current: profile, request: .init(username: .value("player"))) == nil)
        let clear = try #require(try GameServiceOperations.profileIfChanged(applicationID: app, userID: user,
            providerIssuedUserID: "external", current: profile, request: .init(data: .value(.init()))))
        #expect(try JSONValue.parse(#require(clear.body?.storedBodyBytes)) == .object(["data": .object([:])]))
        #expect(clear.authentication == .bot && clear.retrySafety == .unsafe && clear.successStatuses == [201, 204])
        #expect(try clear.decode(Data()) == .null)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GameServiceOperations.profileIfChanged(applicationID: app, userID: user,
                providerIssuedUserID: "../bad", current: profile, request: .init())
        }
    }

    /// Existing matching channel snapshots suppress writes; missing/mismatched channels produce the exact bearer PATCH.
    /// - Throws: Unexpected fixture/descriptor failures fail the test.
    @Test func channelLinkComparison() throws {
        let linked = try Lobby(data: Data(#"{"id":"1","application_id":"2","metadata":null,"members":[],"linked_channel":{"id":"3","type":0}}"#.utf8))
        #expect(try GameServiceOperations.linkIfChanged(current: linked, channelID: .init(rawValue: 3)) == nil)
        let changed = try #require(try GameServiceOperations.linkIfChanged(current: linked, channelID: .init(rawValue: 4)))
        #expect(changed.authentication == .bearer && changed.path == ["lobbies", "1", "channel-linking"])
        #expect(try JSONValue.parse(#require(changed.body?.storedBodyBytes)) == .object(["channel_id": .string("4")]))
        let unlinked = try Lobby(data: Data(#"{"id":"1","application_id":"2","metadata":null,"members":[]}"#.utf8))
        #expect(try GameServiceOperations.linkIfChanged(current: unlinked, channelID: .init(rawValue: 3)) != nil)
    }

    /// The linked-lobby convenience retains server silent drops and never upgrades them into successful membership.
    /// - Throws: Unexpected plan/execution failures fail the test.
    @Test func silentPartialMembers() async throws {
        let members = try [BulkLobbyMemberRequest(id: .init(rawValue: 1)), BulkLobbyMemberRequest(id: .init(rawValue: 2))]
        let plan = try GameServiceOperations.linkedLobbyMembers(lobbyID: .init(rawValue: 3), members: members)
        #expect(plan.chunks.count == 1 && plan.members.count == 2)
        let outcome = try await plan.execute(context: TransportContext(clock: ContinuousClock())) { endpoint in
            #expect(endpoint.authentication == .bot)
            return try endpoint.decode(Data(#"[{"id":"2","flags":0}]"#.utf8))
        }
        #expect(outcome.upserted.map(\.id) == [UserID(rawValue: 2)] && outcome.dropped == [UserID(rawValue: 1)])
        #expect(outcome.removed.isEmpty)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GameServiceOperations.linkedLobbyMembers(lobbyID: .init(rawValue: 3), members: [])
        }
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try GameServiceOperations.linkedLobbyMembers(lobbyID: .init(rawValue: 3), members: [members[0], members[0]])
        }
    }
}
