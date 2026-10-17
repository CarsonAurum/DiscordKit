import DiscordCore
import DiscordHTTP
import DiscordModels
import Foundation

/// Snapshot conveniences over the existing API v10 typed lobby/profile descriptors.
/// Snapshots never establish fresh permissions or consent; executing descriptors retains ordinary shared HTTP policy.
public enum GameServiceOperations {
    /// Avoids replacing an already matching linked channel without performing a hidden GET.
    /// - Parameters:
    ///   - current: Caller-owned complete lobby snapshot, potentially stale.
    ///   - channelID: Existing desired guild channel, requiring caller membership and CanLinkLobby upstream.
    /// - Returns: Nil when the projected channel ID matches, otherwise the existing bearer-authenticated unsafe PATCH.
    /// - Throws: Descriptor construction errors. Concurrent channel changes can race the supplied snapshot;
    ///   there is no implicit channel hydration, lobby join, write replay or linked-message delivery guarantee.
    public static func linkIfChanged(current: Lobby, channelID: ChannelID) throws -> Endpoint<Lobby>? {
        if case .value(let channel) = current.linkedChannel, channel.id == channelID { return nil }
        return try LobbyEndpoints.linkChannel(lobbyID: current.id, channelID: channelID)
    }

    /// Avoids a stats/profile PATCH when every explicitly requested field matches the caller's snapshot.
    /// - Parameters:
    ///   - applicationID: Application whose bot token executes the descriptor; game-stats approval remains upstream.
    ///   - userID: User with application_identities.write consent.
    ///   - providerIssuedUserID: Exact external identity key, validated even for an omitted/equal request.
    ///   - current: Caller-owned complete profile snapshot; external writes can race it.
    ///   - request: Validated username/full-data changes. A supplied data object replaces all stats; omitted fields
    ///     inside it are removed. This helper never merges nested stats with the snapshot.
    /// - Returns: Nil for omitted/equal fields, otherwise the existing unsafe typed PATCH with 201/204 semantics.
    /// - Throws: Identifier/body/descriptor errors even for no-op input. No I/O or background synchronization occurs.
    public static func profileIfChanged(applicationID: ApplicationID, userID: UserID,
        providerIssuedUserID: String, current: ApplicationIdentityProfile,
        request: ApplicationIdentityProfileUpdate) throws -> Endpoint<Nullable<ApplicationIdentityProfile>>? {
        let endpoint = try ApplicationIdentityProfileEndpoints.update(applicationID: applicationID, userID: userID,
            providerIssuedUserID: providerIssuedUserID, request: request)
        guard case .object(let desired) = request.jsonValue(),
              desired.contains(where: { current.rawFields[$0.key] != $0.value }) else { return nil }
        return endpoint
    }

    /// Builds bounded incremental membership changes without converting them into full lobby replacement.
    /// - Parameters:
    ///   - lobbyID: Application-owned target lobby.
    ///   - members: 1...10,000 unique explicit upserts/removals, split into documented groups of at most 25.
    /// - Returns: Existing sequential plan preserving returned upserts, silent drops, removals and partial failure.
    /// - Throws: Existing input/body/descriptor validation errors; construction never sends requests or starts tasks.
    ///   A successful chunk may silently omit ineligible users; callers inspect the plan outcome's dropped IDs.
    public static func linkedLobbyMembers(lobbyID: LobbyID,
        members: [BulkLobbyMemberRequest]) throws -> BulkLobbyMembersPlan {
        try BulkLobbyMembersPlan(lobbyID: lobbyID, members: members)
    }
}
