import DiscordInteractions
import DiscordModels

/// Snapshot available to an immediate slash handler. The unique response owner remains private to
/// lowering, so ordinary typed handlers cannot acknowledge twice or accidentally defer implicitly.
/// Interaction data retains presence/unknown fields and path credentials; formatting stays redacted.
/// Permission snapshots are observations and never substitute for application-side authorization.
public struct CommandContext: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let interaction: Interaction
    public let deliveryMode: InteractionDeliveryMode

    /// Copies only immutable invocation data, without retaining or exposing the low-level response owner.
    /// - Parameter context: Already normalized authenticated HTTP or trusted Gateway invocation.
    ///   No signature checking, hydration, token extension, tasks or I/O occur in this initializer.
    public init(_ context: InteractionContext) {
        interaction = context.interaction
        deliveryMode = context.deliveryMode
    }

    /// Conceals tokens, submitted options and resolved-resource content in ordinary formatting.
    public var description: String { "CommandContext(redacted)" }
    /// Uses the same safe marker in debugger and reflected string formatting.
    public var debugDescription: String { description }
    /// Prevents recursive reflective traversal into raw interaction data and secrets.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Snapshot available only after the deferred route has confirmed its initial loading response.
/// It exposes no responder, acknowledgement or follow-up operations. Returning a `DeferredMessageResponse`
/// completes the existing original; user code must not treat this value as extending continuation life.
public struct DeferredCommandContext: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let interaction: Interaction
    public let deliveryMode: InteractionDeliveryMode

    /// Copies immutable normalized input without retaining low-level response authority or doing work.
    /// - Parameter context: Invocation owned by the route's exact responder. Public construction alone
    ///   does not prove remote acknowledgement; only the deferred lowering adapter establishes that state.
    public init(_ context: InteractionContext) {
        interaction = context.interaction
        deliveryMode = context.deliveryMode
    }

    /// Conceals tokens, submitted arguments and other untrusted interaction data in ordinary formatting.
    public var description: String { "DeferredCommandContext(redacted)" }
    /// Preserves the same redaction for debugger string formatting.
    public var debugDescription: String { description }
    /// Prevents reflection from exposing raw interaction data or response authority.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
