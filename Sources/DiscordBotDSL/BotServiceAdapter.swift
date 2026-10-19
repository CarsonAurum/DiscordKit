import DiscordClient
import DiscordCore
import DiscordHTTP
import DiscordInteractions
import DiscordModels

/// Clock-independent typed REST access for explicitly injected command/event dependencies.
/// Implementations preserve existing endpoint authentication, mutation and cancellation ownership.
public protocol BotServiceProviding: Sendable {
    /// Executes an existing typed descriptor with an optional relative monotonic timeout.
    /// - Parameters:
    ///   - endpoint: Existing API v10 service contract; no hidden hydration or batching is introduced.
    ///   - timeout: Positive total duration no greater than one day, or nil for the executor's normal bounded lifetime.
    /// - Returns: Descriptor's decoded immutable response, including its empty/null semantics.
    /// - Throws: Invalid timeout or existing service, API, cancellation and uncertain mutation failures.
    func execute<Response: Sendable>(_ endpoint: Endpoint<Response>, timeout: Duration?) async throws -> Response
}

/// Explicit service composition over existing REST authorities. Ordinary authenticated operations
/// use the supplied `ServiceContext`; interaction-token clients are separately scoped and injected.
/// Construction starts no work, owns no transport cleanup and creates no per-token registry.
public struct BotServiceAdapter<C: Clock>: BotServiceProviding where C.Duration == Duration {
    public let services: ServiceContext<C>
    private let clock: C
    private let initialClient: @Sendable (Interaction) -> RESTClient<C>
    private let continuationServices: @Sendable (Interaction) -> ServiceContext<C>

    /// Binds explicit bot services and per-interaction HTTP response authorities without invoking factories.
    /// - Parameters:
    ///   - services: Existing shared authenticated REST/cache-invalidation authority, usable before READY.
    ///   - clock: Same monotonic clock domain as response clients; remaining lifetimes become deadlines.
    ///   - initialClient: Factory for the exact interaction-token credential and dedicated callback
    ///     admission/coordinator. Its queue must be independent of ordinary REST; token/resource/server
    ///     rate authorities still require coordination across workers. No factory is called at construction.
    ///   - continuationServices: Factory for that exact token's ordinary continuation REST executor and
    ///     shared entity invalidation callback. Share authority for matching tokens; never use a bot
    ///     credential for interaction path-token endpoints. The adapter retains no token-indexed state.
    public init(services: ServiceContext<C>, clock: C,
        initialClient: @escaping @Sendable (Interaction) -> RESTClient<C>,
        continuationServices: @escaping @Sendable (Interaction) -> ServiceContext<C>) {
        self.services = services
        self.clock = clock
        self.initialClient = initialClient
        self.continuationServices = continuationServices
    }

    /// Executes a typed API v10 operation through the existing bot service owner.
    /// - Parameters:
    ///   - endpoint: Existing typed descriptor with its authentication, retry and resource contract.
    ///   - timeout: Positive relative monotonic timeout at most one day, or nil for ordinary REST bounds, default nil.
    /// - Returns: Decoded immutable result with the descriptor's empty/null semantics.
    /// - Throws: Invalid-value validation for zero, negative or greater-than-one-day timeout; otherwise existing validation,
    ///   admission, API, cancellation, transport or uncertain mutation errors.
    /// Mutation invalidation and request coalescing remain owned by `ServiceContext` and REST.
    public func execute<Response: Sendable>(_ endpoint: Endpoint<Response>, timeout: Duration? = nil) async throws -> Response {
        guard timeout.map({ $0 > .zero && $0 <= .seconds(86_400) }) ?? true else {
            throw DiscordError.validation(.invalidValue)
        }
        return try await services.execute(endpoint, deadline: timeout.map { clock.now.advanced(by: $0) })
    }

    /// Creates exact-token HTTP callback and continuation mechanics after trusted dispatch admission.
    /// - Parameter interaction: Validated application-owned snapshot from the private Gateway bridge.
    /// - Returns: Sink retaining one initial client and one continuation context for this invocation.
    /// All callbacks preserve receipt-relative responder deadlines and existing REST uncertainty.
    /// Factories must be inert and terminating; they execute off client ingestion and control work.
    package func responseSink(for interaction: Interaction) -> InteractionResponseSink {
        let initial = initialClient(interaction)
        let continuations = continuationServices(interaction)
        let clock = self.clock
        return InteractionResponseSink(initial: { response, timeout in
            _ = try await initial.execute(InteractionEndpoints.createResponse(interactionID: interaction.id,
                token: interaction.token, response: response, interactionType: interaction.type.knownValue),
                deadline: clock.now.advanced(by: timeout))
        }, editOriginal: { request, timeout in
            try await continuations.execute(InteractionEndpoints.editOriginalResponse(
                applicationID: interaction.applicationID, token: interaction.token, request: request),
                deadline: clock.now.advanced(by: timeout))
        }, followup: { request, timeout in
            try await continuations.execute(InteractionEndpoints.createFollowup(
                applicationID: interaction.applicationID, token: interaction.token, request: request),
                deadline: clock.now.advanced(by: timeout))
        }, deleteOriginal: { timeout in
            _ = try await continuations.execute(InteractionEndpoints.deleteOriginalResponse(
                applicationID: interaction.applicationID, token: interaction.token),
                deadline: clock.now.advanced(by: timeout))
        })
    }
}
