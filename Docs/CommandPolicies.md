# Policies and middleware

Part 15G adds generic `InvocationPolicy<Input>` and
`InvocationMiddleware<Input, Output>` to `DiscordDSL`, preserving its Core/Models-only
graph. `DiscordCommandDSL` applies them explicitly to compiled command routes through
`CommandPolicies`. Existing products remain independently adoptable. Construction,
composition, validation, compilation and catalog policy application execute no injected
work, registration, tasks or I/O.

```swift
import DiscordDSL
import DiscordCommandDSL

let limits = try PolicyLimits(maximumNodes: 64, maximumDepth: 16)
let admission = try CommandConcurrencyLimit(maximumConcurrent: 8)
let authorization = CommandPolicy.authorized { context in
    try await accessPolicy.authorize(context.interaction)
}
let required = CommandPolicy.isGuild() && authorization
let policies = try CommandPolicies(
    limits: limits,
    requiring: required,
    middleware: audit >>> metrics,
    concurrency: admission,
    onRejection: { _ in
        .message(try MessageResponse(visibility: .ephemeral) { Text("Access denied.") })
    })
let guardedCommands = try commands.applying(policies)
let router = try guardedCommands.makeRouter()
```

`commands` is an existing `CompiledCommands` value; `accessPolicy`, `audit` and
`metrics` are explicitly injected application services/middleware. The independently
compiled [DSLCommands consumer](../Examples/DSLCommands/README.md) includes a complete
signed offline allow/deny example. Its synthetic authorization proves local composition
only, without Discord requests or a deployment capacity claim.

## Evaluation and ownership

`and`, `or` and `negated` are identical to `&&`, `||` and `!`. The ordinary Swift
Boolean operators retain ordinary Boolean precedence. Conjunction and disjunction
evaluate left-to-right and skip the unused branch, including its side effects. Errors
and cancellation propagate instead of becoming Boolean results. `then` is identical
to `>>>`; this operator is left associative and binds more tightly than Boolean
conjunction. `audit >>> metrics` enters audit, enters metrics, executes the terminal,
exits metrics, then exits audit. Middleware owns its `do`/`catch` and `defer` cleanup;
normal statements after a throwing terminal do not automatically run.

Every explicit evaluation requires `PolicyLimits`. A leaf counts as one node and
depth one; each composition adds one node and one level above its children. Defaults
are 256 nodes and depth 32; maximum supported depth is 128. Bounds cover every branch,
including a branch that would short circuit. Structural admission precedes all work.
Captured application objects, arbitrary Swift allocation and injected execution time
remain application-owned.

`CommandPolicies` validates predicate and middleware structure together, counting one
additional execution layer. `CompiledCommands.applying(_:to:)` checks aggregate nodes
and wrapper depth across repeated applications. Exact key subsets can select one
root, leaf, context menu, autocomplete, component or modal route; unknown keys reject.
Each later catalog application is an outer layer. Registration definitions and
structural declaration descriptions remain unchanged; `policyNodeCount` and
`policyDepth` account for the separately adopted execution layers.

Typed routes first admit the complete envelope, typed arguments/target, partial
autocomplete or modal/component tree. Only then do they enter policy execution.
Malformed input cannot run authorization, middleware, denial callbacks, error mapping
or a defer. Next comes the predicate, concurrency admission, middleware, and the
existing immediate/deferred/manual response adapter. A deferred handler still confirms
its defer before user work and completes with edit-original. Manual low-level routes
must supply their own synchronous preparation if they require this boundary.

Shared middleware supports general caller-owned continuation semantics. Command
adapters restrict the terminal to one invocation, including concurrent attempts and
failed attempts. Replacement input cannot replace the original authenticated context
or responder. The terminal continuation closes when middleware exits; an already started
terminal is joined before admission releases. Authors must await next, cooperate with
cancellation and keep child work structured. Retaining an outer continuation can still
enter inner middleware before its terminal claim rejects, so retaining any continuation
or launching detached work is outside the command author contract. Skipping next runs no handler
and sends no automatic response.

## Authorization, admission and failures

`CommandPolicy.isGuild()` observes a concrete guild ID. `context(_:)` compares the
explicit known envelope context and rejects missing, null and future raw values.
`authorized(by:)` delegates the current application decision without interpreting
registration defaults, resolved resources, permission caches or entitlement snapshots.
These observations have distinct purposes from current authorization. Discord's
published [command permissions](https://docs.discord.com/developers/interactions/application-commands)
and [interaction context fields](https://docs.discord.com/developers/interactions/receiving-and-responding)
remain authoritative for API v10.

A false predicate throws `CommandPolicyError.denied` by default, leaving the initial
slot untouched. Explicit `onRejection` can return a validated message for a command,
component or modal submit, or `emptyAutocomplete` for autocomplete. An incompatible
choice rejects before submission through the existing response owner. Authorization
errors, overload, coordinator failures and handler failures never trigger this callback.
Rejection also obeys the original acknowledgement deadline; no extra timer or implicit
deferral is introduced.

`CommandConcurrencyLimit` is a shared fixed-count actor. It fails immediately with
`capacityExceeded`, owns no waiters or keyed history, and releases on success, error
and cancellation after admitted work exits. Cancellation does not release a slot while
its work is still running. Reuse the same authority across routes, routers or catalogs
to obtain an aggregate bound; the existing router additionally keeps its own handler
bound. `CommandConcurrencyAuthority` supports externally owned distributed coordination
with explicit bounded state, fairness, cancellation and cleanup behavior. Persistent
or keyed policy stores require injected count/TTL bounds; no such store is created by
this milestone. Predicate work precedes this execution admission and remains bounded
by the existing router and the injected authorization provider.

Optional `mapError` translates an error into an application error after middleware and
admission cleanup. Cancellation bypasses translation. This hook receives an immutable
snapshot, has no response authority, and never retries, rolls back partial effects or
fabricates a reply after a successful/uncertain acknowledgement. Transport uncertainty
and continuation ownership stay with the existing responder. HTTP rate coordination
continues through existing shared authorities; policies add no replacement quotas or
blind retry middleware.

Local tests cover named/operator behavior, skipped branches, bounds, malformed input,
denial compatibility, shared overload, cancellation, continuation closure and partial
effects. Gateway host composition has separate [bot application tests](BotApplications.md),
and [local measurements](DSLBenchmarks.md) name their exact workload. Part 15L adds
complete [adoption guidance](DSLAdoption.md) and scoped [release records](Release/README.md).
Live authorization services, live Discord, other platforms and production capacity
remain separately qualified gates.
