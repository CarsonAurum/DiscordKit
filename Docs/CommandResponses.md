# Command responses and signed HTTP applications

Part 15D extends `DiscordCommandDSL` with separate immediate, deferred and manual
slash-handler contracts. Each contribution still lowers to the existing validated
`CommandDefinition` and exact `CommandRoute`. The existing interaction responder
owns the initial slot, token expiry and continuation state; the DSL adds no parallel
response state machine. This is an additive, unpublished **0.15.0 candidate**.

## Choose one response owner

| Handler | User work | Completion |
| --- | --- | --- |
| `SlashCommandHandler` | Receives `CommandContext` after full argument decoding. | Returns one validated `MessageResponse`; the adapter sends the initial message. |
| `DeferredSlashCommandHandler` | Receives `DeferredCommandContext` after the defer acknowledgement completes. | Returns `DeferredMessageResponse`; the adapter edits the original response. |
| `ManualSlashCommandHandler` | Receives the existing `InteractionContext`. | Uses its raw responder explicitly, including any defer/continuation workflow. |

Typed contexts expose the interaction and delivery mode, with redacted diagnostic
formatting. They expose no responder. The retained interaction still contains its
raw path token for deliberate application inspection; redacted formatting is not
a secret-removal boundary. Returning a value gives
the adapter the single transmission owner. `MessageResponse` validates an existing
`InteractionMessageCreate`; `DeferredMessageResponse` validates an existing
`InteractionMessageEdit`. Part 15E also accepts
[validated message/component builder closures](MessageBuilders.md) for both response
families. Both are JSON-only; multipart upload ownership remains in
the existing low-level APIs. Their constructors preserve omission/null/value behavior
and existing payload validation. They cannot represent component update,
autocomplete, modal, pong or other incompatible response kinds.

`DeferredSlashCommandHandler.responseVisibility` defaults to `.public`; use
`.ephemeral` explicitly when required. The type-5 acknowledgement fixes visibility
before handler execution. Completion uses edit-original, never a follow-up standing
in for the deprecated first-follow-up compatibility behavior. The response edit must
meet the existing endpoint's rules, including its flag and attachment constraints.

```swift
import DiscordCommandDSL
import DiscordDSLMacros
import DiscordModels

@CommandArguments
struct PingArguments: Sendable {}

@SlashCommand("ping", description: "Check the command application")
struct Ping: SlashCommandHandler {
    typealias Arguments = PingArguments

    /// Returns the sole initial message; the adapter owns its transmission.
    /// - Parameters:
    ///   - context: Trusted, redacted invocation metadata without responder access.
    ///   - arguments: Fresh validated empty arguments.
    /// - Returns: A validated JSON message containing Pong.
    /// - Throws: Message validation errors; no delivery occurs inside this method.
    func execute(_ context: CommandContext, arguments: Arguments) async throws -> MessageResponse {
        try MessageResponse(InteractionMessageCreate(content: .value("Pong!")))
    }
}
```

The optional macro infers the explicitly declared handler family. Its original
no-family/manual syntax remains supported. Handwritten handlers and schemas use the
same adapters; runtime products do not select a compiler plugin or SwiftSyntax.

## Admission, cancellation and delivery

The route checks the trusted application-command envelope and complete argument
schema before acknowledgement or handler work. Invalid options, wrong command
identity, unsupported nesting and incompatible interaction kinds fail before user
execution. This preflight does not infer authorization from registration defaults or
partial resolved resources. Part 15G adds [explicit authorization, policies and middleware](CommandPolicies.md),
with complete input admission before policy execution and deferral.

The finite declaration fingerprint includes the response family and deferred
visibility. Inspecting or comparing this metadata executes no handler or policy;
it is not an authorization decision or proof that a response was delivered.

Immediate handlers execute, then pass a cancellation checkpoint before the single
reply. Deferred handlers await acknowledgement, execute, then pass a cancellation
checkpoint before edit-original. A failed or uncertain defer never starts user work.
User errors, cancellation and transport failures propagate without synthetic fallback
messages, mutation replay or a second initial acknowledgement. A failure after defer
can therefore leave the loading response outstanding; applications choose their
explicit recovery policy through the existing low-level APIs.

The responder enforces the initial three-second deadline and fifteen-minute token
lifetime using its injected clock. An indeterminate send is not proof of failure;
do not retry it blindly. Continuation overlap, expiry and resource cleanup retain
the existing [interaction contracts](Interactions.md). These contracts apply equally
to signed HTTP contexts and already trusted normalized contexts; no public shortcut
authenticates arbitrary Gateway input, and no Gateway application host is added here.

## Own the HTTP application explicitly

Compile the module to `CompiledCommands`, then construct `CommandApplication` with
the expected application ID, signed ingress and shared initial-response admission
authority. Its configuration defaults are 64 concurrent handlers, 64 concurrent HTTP
requests and 1 MiB of definition bytes, alongside the existing ingress limits. Use
finite limits appropriate to the deployment and share authorities across workers.

`handle` accepts one exchange, its transport context and an optional injected
continuation sink. `run(listener:context:continuations:)` consumes the supplied
`HTTPIngress`, bounds admitted requests and owns listener closure on every exit.
Construction is inert. Cancellation of `run` propagates to its children; handlers
and injected sinks must cooperate with cancellation. A concrete networking adapter
belongs to the application's composition root. Initial callback admission remains
independent of ordinary REST quotas.

The initializer rejects any non-nil application-level `autoDefer`: the selected
handler contract owns acknowledgement timing, so a competing timer is invalid.
Manual contributions remain available for explicitly managed low-level workflows.

Construction, `handle` and ordinary `run` issue zero command-registration requests.
Only an explicit `synchronize(using:deadline:)` invokes the existing
`CommandReconciler` with compiled definitions and managed names. Its application ID,
optional guild scope, shared REST authority, deadline, unmanaged-command preservation
and partial/indeterminate outcomes retain the existing command contracts. Inspect
the report; synchronization is not an implicit startup side effect.

The independent [DSLCommands consumer](../Examples/DSLCommands/README.md) compiles a
macro-authored `/ping` and exercises a synthetic Ed25519-signed HTTP exchange without
credentials. Its explicit listener mode owns local ingress; it does not register
commands. The example and response tests are offline evidence. Live Discord, other
platforms, Gateway hosts, capacity and full Phase 15
certification remain separate [milestones](DSLImplementationRoadmap.md).

Current response kinds, deadlines, ephemeral behavior and edit-original semantics
were reviewed against the official [interaction reference](https://docs.discord.com/developers/interactions/receiving-and-responding),
[API reference](https://docs.discord.com/developers/reference) and
[change log](https://docs.discord.com/developers/change-log) on **2026-10-18**.
[Source hashes](Release/sources/2026-10-18-phase15d.json) identify the exact reviewed
inputs; unchanged discovery classifications are not promoted to new parity claims.
