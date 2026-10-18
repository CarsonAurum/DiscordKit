import DiscordCore
import DiscordModels
import DiscordHTTP
import Foundation
import Testing

/// Pins future HTTP omission separately from current Gateway obfuscation. These
/// synthetic responses exercise decoding only and establish no live visibility.
@Suite struct ChannelTransitionTests {
    /// Decodes the dated server responses without inventing missing channels, losing
    /// snowflake precision, mutating previous snapshots or selecting behavior by local date.
    /// The empty and restored responses establish that omission is not a deletion event.
    /// - Throws: Fixture I/O, JSON schema, descriptor or channel decoding failures fail the test.
    @Test func datedHTTPChannelOmission() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Release/channel-obfuscation-2026-11-16.json")
        let value = try JSONValue.parse(Data(contentsOf: fixture))
        guard case .object(let document) = value,
              case .array(let cases) = document["cases"] else {
            Issue.record("Dated transition fixture has no cases")
            return
        }
        #expect(document["announcedOn"] == .string("2026-08-12"))
        #expect(document["effectiveOn"] == .string("2026-11-16"))
        #expect(cases.count == 4)
        let endpoint = try GuildEndpoints.channels(guildID: .init(rawValue: UInt64.max))
        #expect(endpoint.method == "GET")
        #expect(endpoint.route == "/guilds/{guild.id}/channels")
        #expect(endpoint.query.isEmpty)
        #expect(endpoint.readPolicy?.timeToLive == nil)
        var snapshots: [[Channel]] = []
        for entry in cases {
            guard case .object(let fields) = entry,
                  let response = fields["response"],
                  case .array(let expectedIDs) = fields["expectedIDs"] else {
                Issue.record("Dated transition case has invalid response or IDs")
                continue
            }
            let channels = try endpoint.decode(JSONEncoder().encode(response))
            #expect(channels.map { JSONValue.string($0.id.description) } == expectedIDs)
            #expect(channels.allSatisfy { !$0.isObfuscated })
            snapshots.append(channels)
        }
        #expect(snapshots.map(\.count) == [2, 1, 0, 2])
        #expect(snapshots.first?.last?.id.rawValue == UInt64.max)
        #expect(snapshots.first == snapshots.last)
    }
}
