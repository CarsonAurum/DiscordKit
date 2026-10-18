import DiscordActivities
import DiscordCore
import DiscordTransport

/// Sanitized Activity-presence bridge errors; application names and presence text are never included.
public enum SocialActivityProviderError: Error, Sendable, Equatable {
    /// Application name is empty, exceeds 128 UTF-8 bytes or contains control characters.
    case invalidApplicationName
    /// Activity names come from the host application and cannot be changed by SET_ACTIVITY.
    case applicationNameMismatch
}

/// Browser/mobile Activity equivalents over an existing exact-source/origin-authenticated host bridge.
/// The caller owns start, authentication, subscriptions and close. Construction starts no tasks or I/O.
/// Web/iOS/Android host support comes from the selected Activity protocol, never desktop IPC inference.
public struct SocialActivityProvider<C: Clock>: SocialPresenceProvider where C.Duration == Duration {
    public typealias ProviderClock = C
    private let client: ActivityClient<C>
    private let applicationName: String
    public let presenceRequirements = SocialProviderRequirements(host: .activityHost, scopes: ["rpc.activities.write"])
    /// Relationship reads also require accepted Social SDK terms; the host remains authoritative for policy.
    public let relationshipRequirements = SocialProviderRequirements(host: .activityHost, scopes: ["relationships.read"])
    /// Participant and UI commands require the Activity host; invite dialogs additionally require guild context
    /// and CREATE_INSTANT_INVITE, while external links remain subject to host confirmation/policy.
    public let hostRequirements = SocialProviderRequirements(host: .activityHost)

    /// Retains the host bridge and its application-derived presence name without starting it.
    /// - Parameters:
    ///   - client: Independently owned ready/authenticated Activity client; no host is created or impersonated.
    ///   - applicationName: Trusted application name from configuration, 1...128 UTF-8 bytes, without controls.
    ///     Activity mutations cannot override the name; neutral updates must match this value exactly.
    /// - Throws: `SocialActivityProviderError.invalidApplicationName` for an invalid configured name.
    public init(client: ActivityClient<C>, applicationName: String) throws {
        guard !applicationName.isEmpty, applicationName.utf8.count <= 128,
              !applicationName.unicodeScalars.contains(where: { $0.properties.generalCategory == .control })
        else { throw SocialActivityProviderError.invalidApplicationName }
        self.client = client; self.applicationName = applicationName
    }

    /// Updates the neutral details/state through host SET_ACTIVITY after checking the immutable application name.
    /// - Parameters:
    ///   - presence: Validated neutral presence; name must exactly match the configured application name.
    ///     Missing details/state are omitted rather than silently cleared.
    ///   - context: Cancellation and optional inclusive deadline in the Activity client's clock domain.
    /// - Throws: Application-name mismatch before I/O, auth/scope/host failure, overload, cancellation,
    ///   deadline, malformed response or uncertain delivery. Requires rpc.activities.write.
    /// Name equality prevents silently dropping an unsupported caller-requested rename. No command is replayed.
    public func updatePresence(_ presence: SocialPresence, context: TransportContext<C>) async throws {
        guard presence.name == applicationName else { throw SocialActivityProviderError.applicationNameMismatch }
        let update = try ActivityPresenceUpdate(state: presence.state.map(Field.value) ?? .absent,
                                                details: presence.details.map(Field.value) ?? .absent)
        _ = try await setPresence(.value(update), context: context)
    }

    /// Executes the documented Activity-specific presence mutation, including explicit null clearing.
    /// - Parameters:
    ///   - activity: Typed host presence update or explicit null to clear; application name remains host-owned.
    ///   - context: Cancellation and optional Activity-clock deadline; no deadline uses a 15-second operation cap.
    /// - Returns: Typed host Rich Presence response, preserving complete unknown fields.
    /// - Throws: Validation, rpc.activities.write/host permission, overload, cancellation, deadline or protocol failures.
    /// Clearing here is supported by the embedded schema and does not imply local-RPC clearing support.
    public func setPresence(_ activity: Nullable<ActivityPresenceUpdate>,
                            context: TransportContext<C>) async throws -> ActivityRichPresence {
        try await execute(ActivityRequests.setActivity(activity: activity), context: context)
    }

    /// Reads the consented host user's relationship snapshot without inventing relationship mutations.
    /// - Parameter context: Cancellation and optional Activity-clock deadline; absent deadline uses 15 seconds.
    /// - Returns: Ordered typed relationships, including empty snapshots and unknown relationship kinds.
    /// - Throws: Missing relationships.read, unaccepted Social SDK terms, host/transport/overload,
    ///   cancellation, deadline or decoding failures. The snapshot is not a native Social event stream.
    public func relationships(context: TransportContext<C>) async throws -> ActivityRelationships {
        try await execute(ActivityRequests.getRelationships(), context: context)
    }

    /// Reads users connected to the present Activity instance through the current renamed host command.
    /// - Parameter context: Cancellation and optional Activity-clock deadline; absent deadline uses 15 seconds.
    /// - Returns: Typed ordered participants, including empty snapshots; no guild-member hydration occurs.
    /// - Throws: Host/auth, overload, cancellation, deadline, transport or malformed-response failures.
    /// This establishes Activity-instance membership only, never a Social lobby or call participant list.
    public func participants(context: TransportContext<C>) async throws -> ActivityParticipants {
        try await execute(ActivityRequests.getActivityInstanceConnectedParticipants(), context: context)
    }

    /// Opens the host's invite dialog after the caller's explicit user action.
    /// - Parameter context: Cancellation and optional Activity-clock deadline; absent deadline uses 15 seconds.
    /// - Throws: Missing guild context/CREATE_INSTANT_INVITE, unsupported host, overload, cancellation,
    ///   deadline or protocol failures. The host owns selection and user consent; success does not prove an invite was sent.
    public func openInviteDialog(context: TransportContext<C>) async throws {
        _ = try await execute(ActivityRequests.openInviteDialog(), context: context)
    }

    /// Opens a host-confirmed external link under the documented Activity browser/mobile command.
    /// - Parameters:
    ///   - url: Validated by the existing command schema and host policy; no server-side fetch occurs here.
    ///   - context: Cancellation and optional Activity-clock deadline; absent deadline uses 15 seconds.
    /// - Returns: Typed host outcome preserving cancellation or unknown fields according to its schema.
    /// - Throws: Invalid URL arguments, unsupported/denied host action, overload, cancellation, deadline or protocol failures.
    public func openExternalLink(_ url: String, context: TransportContext<C>) async throws -> ActivityExternalLink {
        try await execute(ActivityRequests.openExternalLink(url: url), context: context)
    }

    /// Preserves caller cancellation/deadline while using the bounded Activity request owner.
    /// - Parameters:
    ///   - request: Already validated typed command; this helper invents no wire fields or retries.
    ///   - context: Caller cancellation and deadline in the client's clock domain.
    /// - Returns: Existing typed response after the caller context remains valid.
    /// - Throws: Pre-admission cancellation/expired deadline, command/transport failure, overload or malformed response.
    /// The original deadline covers admission, write and response. No deadline selects a finite 15-second budget.
    private func execute<Response: Sendable>(_ request: ActivityRequest<Response>,
                                             context: TransportContext<C>) async throws -> Response {
        try context.check()
        let timeout = context.deadline.map { context.clock.now.duration(to: $0) } ?? .seconds(15)
        return try await context.run { try await client.execute(request, timeout: timeout) }
    }
}
