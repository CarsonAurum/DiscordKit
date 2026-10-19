import DiscordCore
import DiscordDSL
import DiscordGateway
import DiscordModels

/// A future dispatch name and its exact data, obtained through the existing lossless decoder.
/// This snapshot adds no resource projection or claim that Discord currently emits the name.
public struct GatewayUnknownEvent: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Exact unrecognized, case-sensitive dispatch name.
    public let name: String
    /// Complete bounded data, including unknown fields and exact number lexemes.
    public let data: JSONValue

    /// Retains an unknown dispatch without decoding another schema or starting work.
    /// - Parameters:
    ///   - name: Exact future name already admitted by the Gateway envelope.
    ///   - data: Original lossless bounded payload; no authenticity is inferred.
    public init(name: String, data: JSONValue) {
        self.name = name
        self.data = data
    }

    /// Conceals arbitrary event names and payload data from ordinary diagnostics without serialization.
    /// Explicit access to `name` and `data` remains available for deliberate application inspection.
    public var description: String { "GatewayUnknownEvent(redacted)" }

    /// Uses the ordinary redacted marker when debug formatting or `String(reflecting:)` inspects this value.
    public var debugDescription: String { description }

    /// Prevents recursive reflection from exposing future payloads or user-controlled event names.
    /// - Returns: A mirror containing only a fixed nonsecret redaction flag.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// A finite typed projection of the existing decoded Gateway catalog.
/// Selectors are open to application-defined payloads without editing a central switch. Their
/// extraction closures execute only during explicit pipeline execution and must remain synchronous,
/// bounded and free of I/O. Required intent bits are checked against an explicit host selection;
/// neither constructing a selector nor compiling handlers enables privileged intents.
public struct GatewayEventSelector<Event: Sendable>: Sendable {
    /// Stable explicit selector identity, validated with declaration metadata at compilation.
    public let id: String
    /// All bits the selector requires; applications must select and provision them themselves.
    public let requiredIntents: GatewayIntents
    internal let decodesDispatch: Bool
    internal let extract: @Sendable (GatewayEvent, GatewayDispatch?) throws -> Event?

    /// Stores a custom projection without executing it, decoding payloads or starting work.
    /// - Parameters:
    ///   - id: Stable nonempty identity, at most 128 UTF-8 bytes without ASCII controls.
    ///   - requiredIntents: Explicit scope/content requirements, default empty. Unknown bits are
    ///     retained; portal approval and event delivery cannot be established locally.
    ///   - select: Returns the associated event for a match, otherwise nil; invoked only at runtime
    ///     after the existing bounded `GatewayEvent.decodeDispatch` has succeeded. A thrown error
    ///     terminates the supervised pipelines without replay or fallback. Capture actor services in
    ///     the handler instead of doing service work in this synchronous projection.
    public init(id: String, requiredIntents: GatewayIntents = [],
        select: @escaping @Sendable (GatewayDispatch) throws -> Event?) {
        self.id = id
        self.requiredIntents = requiredIntents
        decodesDispatch = true
        extract = { _, dispatch in
            guard let dispatch else { return nil }
            return try select(dispatch)
        }
    }

    /// Stores the deliberate raw-envelope escape hatch without requesting typed decoding.
    /// - Parameters:
    ///   - id: Fixed internal identity, included in the admitted declaration snapshot.
    ///   - extract: Synchronous bounded projection of the exact raw event, executed only at runtime.
    ///
    /// A group containing any decoded selector still validates every dispatch before invoking its
    /// raw handlers. Only a group consisting entirely of raw handlers bypasses model decoding.
    private init(id: String, extract: @escaping @Sendable (GatewayEvent) -> Event?) {
        self.id = id
        requiredIntents = []
        decodesDispatch = false
        self.extract = { raw, _ in extract(raw) }
    }
}

public extension GatewayEventSelector where Event == GatewayDispatch {
    /// Selects every typed or unknown dispatch. Control/future opcodes are not dispatches.
    /// No intent requirements are inferred: add requirements on the handler for its actual use.
    static var all: Self { .init(id: "discord.dispatch.all") { $0 } }
}

public extension GatewayEventSelector where Event == GatewayUnknownEvent {
    /// Selects only future names, preserving exact lossless data after bounded dispatch decoding.
    /// Known malformed dispatches fail instead of being reclassified as unknown events.
    static var unknown: Self {
        .init(id: "discord.dispatch.unknown") { dispatch in
            guard case .unknown(let name, let data) = dispatch else { return nil }
            return GatewayUnknownEvent(name: name, data: data)
        }
    }
}

public extension GatewayEventSelector where Event == GatewayEvent {
    /// Selects every raw envelope, including control opcodes. A group containing only this selector
    /// deliberately skips model decoding; mixed groups retain strict known-dispatch validation.
    /// This observation is not an authentication, authorization or raw-shard-consumer capability.
    static var raw: Self { .init(id: "discord.envelope.raw", extract: { $0 }) }
}

public extension GatewayEventSelector where Event == GatewayReady {
    /// Selects the existing partial `READY` model with no additional Gateway intent requirement.
    /// Receipt does not prove that guild resources, privileged content or services are available.
    static var ready: Self {
        .init(id: "discord.dispatch.ready") { dispatch in
            guard case .ready(let ready) = dispatch else { return nil }
            return ready
        }
    }
}

public extension GatewayEventSelector where Event == GatewayMessageCreate {
    /// Selects `MESSAGE_CREATE` across both guild and direct-message scopes, deliberately requiring
    /// both `.guildMessages` and `.directMessages`. A custom selector may declare a narrower scope.
    /// Content availability additionally requires the caller's applicable permissions/exemptions;
    /// handlers using privileged content must explicitly require `.messageContent` themselves.
    static var messageCreate: Self {
        .init(id: "discord.dispatch.message-create", requiredIntents: [.guildMessages, .directMessages]) { dispatch in
            guard case .messageCreate(let message) = dispatch else { return nil }
            return message
        }
    }
}

public extension GatewayEventSelector where Event == GatewayMessageUpdate {
    /// Selects partial `MESSAGE_UPDATE` values in guild and direct-message scopes, deliberately
    /// requiring both message intents. Missing fields remain partial and no hydration occurs.
    /// Use a custom selector for a narrower scope and explicitly require privileged content bits.
    static var messageUpdate: Self {
        .init(id: "discord.dispatch.message-update", requiredIntents: [.guildMessages, .directMessages]) { dispatch in
            guard case .messageUpdate(let message) = dispatch else { return nil }
            return message
        }
    }
}

/// Immutable raw metadata accompanying one typed callback. Application services remain ordinary
/// initializer-injected dependencies on the handler; this context owns no client or service locator.
public struct GatewayEventContext: Sendable {
    /// Source shard identity, sequence, socket generation and lossless envelope payload.
    /// The value carries no additional authenticity beyond the hub chosen by the application.
    public let rawEvent: GatewayEvent

    /// Retains the exact bounded event without I/O, lookup, hydration or registration.
    /// - Parameter rawEvent: The event whose decoded selection is supplied to the same callback.
    public init(rawEvent: GatewayEvent) { self.rawEvent = rawEvent }
}

/// Public extension point for inert custom event declarations. The exact registration snapshot
/// must agree with `declaration`, including source, capabilities and selector requirements.
/// Structural collection captures `declaration` once; subsequent event lowering captures
/// `registration` once and compares the complete metadata. The default declaration obtains its
/// own registration snapshot, so conforming accessors must agree across those separate captures.
/// Neither capture invokes retained runtime behavior.
public protocol GatewayEventContribution: DefinitionContribution {
    var registration: GatewayHandlerRegistration {
        /// Returns one deterministic immutable registration without I/O or callback execution.
        /// - Returns: A registration whose complete metadata agrees with the structural declaration.
        get
    }
}

public extension GatewayEventContribution {
    /// Complete inert registration metadata for shared structural admission.
    var declaration: RawDefinitionContribution { registration.declaration }
}

/// A reusable typed Gateway leaf directly accepted by `BotBuilder` and `BotModule` bodies.
/// Handler values are immutable declarations; initializer-injected actors own mutable services.
/// Compilation performs no handle calls, tasks, subscriptions, registration or network work.
public protocol GatewayEventHandler: GatewayEventContribution {
    /// Existing or application-defined immutable selected event value.
    associatedtype Event: Sendable

    var handlerID: String {
        /// Returns an explicit stable ID, globally unique across every group and module.
        /// - Returns: Nonempty identity of at most 128 UTF-8 bytes without ASCII controls.
        get
    }

    var selector: GatewayEventSelector<Event> {
        /// Returns a finite inert selector; its projection closure is never called by compilation.
        /// - Returns: The handler's immutable typed projection and explicit intent requirements.
        get
    }

    var requiredIntents: GatewayIntents {
        /// Returns additional explicit requirements, unioned with the selector's requirements.
        /// - Returns: Required bits, default empty; privileged bits are never enabled implicitly.
        get
    }

    var eventGroup: String? {
        /// Returns an independent subscription identity or nil for the shared default pipeline.
        /// - Returns: Stable nonempty ID with the 128-byte identity restrictions, or nil. Equal IDs
        ///   share declaration ordering; distinct groups have no ordering guarantee between them.
        get
    }

    var sourceLocation: DefinitionSourceLocation {
        /// Returns an inert diagnostic coordinate without opening a source file.
        /// - Returns: Captured author location or the default unavailable synthetic coordinate.
        get
    }

    /// Handles one selected event under the existing bounded complete-shard dispatcher.
    /// - Parameters:
    ///   - event: Typed selection from this event's already decoded dispatch, or raw envelope.
    ///   - context: Exact raw metadata for the same event; inject services in the initializer.
    /// - Throws: Application failure or cancellation, propagated unchanged and cancelling every
    ///   sibling pipeline. No retries, replay or compensating work occurs after partial side effects.
    ///
    /// Matching handlers in a group complete in declaration order before its next same-shard
    /// event starts. Different complete shard identities may overlap. User work must cooperate
    /// with cancellation; a nonterminating callback prevents structured cleanup from completing.
    func handle(_ event: Event, context: GatewayEventContext) async throws
}

public extension GatewayEventHandler {
    /// Adds no intent bits beyond the selector unless a handler explicitly declares them.
    var requiredIntents: GatewayIntents { [] }
    /// Uses the single default subscription regardless of module count.
    var eventGroup: String? { nil }
    /// Supplies an unavailable coordinate when the handler does not store its author's location.
    var sourceLocation: DefinitionSourceLocation { .init(fileID: "<unknown>", line: 0, column: 0) }
    /// Erases this typed handler while retaining the exact associated selector and immutable metadata.
    var registration: GatewayHandlerRegistration { .init(self) }
}

/// Type-erased handler with an exact inspectable structural snapshot. Construction stores behavior
/// without executing it. Applications can expose this value through `GatewayEventContribution`
/// to adapt an existing typed handler without introducing another execution runtime.
public struct GatewayHandlerRegistration: Sendable {
    public let id: String
    public let selectorID: String
    public let requiredIntents: GatewayIntents
    public let eventGroup: String?
    public let source: DefinitionSourceLocation
    internal let decodesDispatch: Bool
    internal let invoke: @Sendable (GatewayEvent, GatewayDispatch?) async throws -> Void

    /// Captures each handler setting once without calling its selector or execution method.
    /// - Parameter handler: Immutable Sendable handler and initializer-injected dependencies.
    ///   Property getters must remain deterministic, finite and inert. Intent, identity and group
    ///   validation occur during compilation; no permissions or event delivery are inferred here.
    public init<Handler: GatewayEventHandler>(_ handler: Handler) {
        let selector = handler.selector
        id = handler.handlerID
        selectorID = selector.id
        requiredIntents = selector.requiredIntents.union(handler.requiredIntents)
        eventGroup = handler.eventGroup
        source = handler.sourceLocation
        decodesDispatch = selector.decodesDispatch
        invoke = { raw, dispatch in
            try Task.checkCancellation()
            if let event = try selector.extract(raw, dispatch) {
                try await handler.handle(event, context: .init(rawEvent: raw))
            }
        }
    }

    /// Complete deterministic metadata, including decode mode and every declared intent bit.
    /// Numeric bitfields use exact decimal strings to preserve all UInt64 bits in snapshots.
    public var declaration: RawDefinitionContribution {
        .init(id: id, kind: EventCompilation.contributionKind,
            payload: .object([
                "selector": .string(selectorID),
                "required_intents": .string(String(requiredIntents.rawValue)),
                "group": eventGroup.map(JSONValue.string) ?? .null,
                "decode_dispatch": .bool(decodesDispatch)
            ]), source: source)
    }
}
