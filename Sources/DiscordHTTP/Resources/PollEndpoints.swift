import DiscordCore
import DiscordModels
import Foundation

/// Typed API v10 poll operations; poll creation is part of `MessageCreate`.
///
/// Verified 2026-10-16 against https://docs.discord.com/developers/resources/poll.
/// Descriptors use bot authentication and the same credential-global/channel buckets,
/// finite retry/deadline/cancellation policies as other messages, without requiring Gateway.
public enum PollEndpoints {
    /// Retrieves answer voters using an exclusive after-user cursor.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Message containing the poll.
    ///   - answerID: Positive answer identifier returned by the poll, not an array index.
    ///   - after: Optional exclusive user cursor; nil starts at the beginning.
    ///   - limit: Voters per page, 1...100; default 25.
    ///   - readPolicy: Optional scoped read reuse; default coalesces without completed caching.
    /// - Returns: A safe GET descriptor extracting `users` from the voters envelope.
    /// - Throws: Safe count/answer/descriptor errors; malformed/missing users fail decoding.
    ///   The User-family projection remains partial, with unknown fields retained exactly.
    public static func voters(channelID: ChannelID, messageID: MessageID, answerID: Int,
                              after: UserID? = nil, limit: Int = 25,
                              readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<[User]> {
        try messageLimit(limit, maximum: 100)
        guard answerID > 0 else { throw DiscordError.validation(.invalidValue) }
        var query = [QueryItem(name: "limit", value: String(limit))]
        if let after { query.append(.init(name: "after", value: after.description)) }
        return try Endpoint(method: "GET", path: ["channels", channelID.description, "polls", messageID.description, "answers", String(answerID)],
            route: "/channels/{channel.id}/polls/{message.id}/answers/{answer_id}", query: query, authentication: .bot,
            majorParameter: channelID.description, retrySafety: .safe,
            readPolicy: messageReadPolicy(readPolicy, channelID: channelID), decode: { data in
                guard case .object(let fields) = try JSONValue.parse(data), let users = fields["users"]
                else { throw DiscordError.transport(.invalidResponse) }
                return try messageUsers(users.serialized())
            })
    }

    /// Ends a poll owned by the authenticated bot immediately; another author's poll is rejected by Discord.
    /// - Parameters:
    ///   - channelID: Channel major-rate partition.
    ///   - messageID: Message containing the owned poll.
    /// - Returns: An unsafe POST descriptor decoding the updated message and invalidating channel reads.
    ///   Ending does not assert that vote results are already finalized; inspect Poll.results.isFinalized.
    /// - Throws: Descriptor errors; execution preserves API errors, cancellation and indeterminate outcomes.
    public static func end(channelID: ChannelID, messageID: MessageID) throws -> Endpoint<Message> {
        try Endpoint(method: "POST", path: ["channels", channelID.description, "polls", messageID.description, "expire"],
            route: "/channels/{channel.id}/polls/{message.id}/expire", authentication: .bot,
            majorParameter: channelID.description, invalidates: messageTags(channelID), decode: { try Message(data: $0) })
    }
}
