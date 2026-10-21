# Semantic logging and trace diagnostics

DiscordKit uses Apple's [SwiftLog](https://github.com/apple/swift-log) for Swift
runtime diagnostics. Select `DiscordLogging` for the shared entry point and native
`Logging` APIs; select `DiscordLogHandlers` separately for owned output backends.
SwiftLog 1.16.1 is the minimum and resolved version for this change. `DiscordLogging` and existing runtime owners
never bootstrap SwiftLog, open outputs or change process-wide log configuration.
Existing diagnostics, typed errors, cancellation and resource ownership stay authoritative.

## Logging model

Logging is part of the runtime's operation contract: a trace should explain what was
admitted, which decision was made, what work followed, and how ownership ended.
Events use fixed names and structured counts, states, outcomes and protocol codes.
Higher thresholds retain increasingly significant events. Construction, pure
authoring/compilation and realtime/sample/crypto loops remain quiet.

This is diagnostic integration, not a new metrics, tracing, audit-event or persistence
authority. Events can help investigate behavior; they do not replace returned errors,
protocol security decisions or durable interaction admission.

## Severity policy

The policy follows [Swift's library logging guidance](https://www.swift.org/documentation/server/guides/libraries/log-levels.html).

| SwiftLog level | Meaning in DiscordKit |
| --- | --- |
| `trace` | Each meaningful operation step: admission, waiting, encoding, protocol decisions, dispatch, response handling and joined cleanup. |
| `debug` | Diagnostic summaries, cache decisions, response results and caller-visible failures. |
| `info` | Significant successful operation outcomes and normal owned lifecycle transitions. |
| `notice` | Recovery, authorization/media readiness, reconciliation and operational milestones worth retaining. |
| `warning` | Autonomous degradation/recovery or a documented compatibility fallback. |
| `error` | Failed admitted handler/owned operation, terminal supervised subsystem failure or failed owned cleanup. |
| `critical` | A permanently unusable safety authority: the fail-closed REST coordinator. |

The coordinator emits its critical transition once and rejects future admission;
the application must repair the external authority and replace the coordinator.
Routine request-level HTTP failures, invalid inputs, 429s, overload rejections and
cancellation stay diagnostic. A higher-level owner can report a failed admitted
operation or terminated subsystem at error when recovery requires a caller decision.
Severity does not change control flow.

SwiftLog's default process handler filters below `info`. Significant library lifecycle
events are now visible at that threshold. This deliberately replaces the first logging
attempt's reservation of `info` and `notice`. Applications also use all seven severities.
An individual trace step is not promoted merely to fill the severity ladder.

## Module and component filtering

Labels are dotted components such as `discordkit.http.execution`,
`discordkit.http.ratelimit`, `discordkit.gateway.session`, `discordkit.voice.session`
and `discordkit.interactions.response`. `dk.subsystem` stores the full component;
`dk.module` stores its first segment (`http`, `gateway`, `voice`, `interactions`).
SwiftLog's source field still identifies the actual Swift module. Flat labels from
the first logging attempt have moved to finer categories; update exact-label filters.
Existing event identities are retained where the operation meaning is unchanged.

| Logical module | Component categories |
| --- | --- |
| `http` | `execution`, `codec`, `ratelimit`, `retry`, `cache`, `coalescing`, `ordering` |
| `gateway` | `session`, `protocol`, `authentication`, `heartbeat`, `ownership`, `requests`, `events`, `handlers` |
| `client` / `cache` | `lifecycle`, `discovery`, `ingestion` / `lifecycle`, `storage`, `refresh` |
| `interactions` | `ingress`, `admission`, `http`, `response`, `webhooks` |
| `commands` / `command_dsl` | `router`, `reconciliation` / `http`, `admission`, `policy` |
| `dsl` / `bot` | `policy`, `middleware` / `lifecycle`, `interactions`, `events`, `events.handler` |
| `oauth` / `commerce` | `http`, `tokens`, `device` / `entitlements` |
| `rpc` / `activities` / `social` | `client` |
| `certified_devices` | `http`, `rpc` |
| `voice` / `dave` / `mls` / `media` | `session`, `manager` / `protocol` / `group` / `pcm_stream` |
| `transport` | `deadline`, `leases` |
| `foundation` | `admission`, `http`, `http.upload`, `http.body`, `websocket`, `websocket.handshake`, `websocket.read`, `websocket.write` |
| `nio` | `http`, `http.pool`, `http.connection`, `http.upload`, `http.body`, `websocket`, `websocket.read`, `websocket.write`, `datagram`, `ingress` |
| `unix` / `apple` | `ipc`, `ipc.read`, `ipc.write` / `audio`, `lifecycle` |


Use a policy in the application's bootstrap factory, or scope it around explicit work:

```swift
let policy = DiscordLogConfiguration(defaultLevel: .info, overrides: [
    "http": .debug,
    "http.execution": .trace,
    "gateway": .debug,
    "voice.session": .trace,
])

try await DiscordLog.$configuration.withValue(policy) {
    try await runtime.run()
}
```

The longest matching dotted prefix wins: `http` matches `http.execution` but not
`http2`. A nil scoped configuration preserves the factory's threshold. Setting a
native multiplex logger's level updates every child's level too. Wrap outputs in
`DiscordLevelFilterLogHandler` to retain a fixed minimum, for example an info console
beside a trace file. Set diagnostic outputs to trace when using scoped policies.
Policies hold only application
configuration and never change global logging state.

## Correlated operation timelines

`DiscordLog.withOperation` wraps synchronous or asynchronous work exactly once,
preserves its result/error and restores context on exit. Explicit HTTP execution,
Gateway shard and voice session scopes supply correlation to child components.
Applications may add scopes around their own operations:

```swift
try await DiscordLog.withOperation("application.sync", event: "application.sync") {
    try await synchronize()
}
```

Start and terminal events use `.started`, `.completed`, `.failed` or `.cancelled`
suffixes. Trace records success/cancellation; failures use debug so the owner can
separately identify terminal subsystem failures at error. Terminal events carry
`dk.outcome` and monotonic decimal `dk.duration_ns`. `dk.trace_id` is shared by nested
operations; each scope gets a new `dk.span_id` and optional `dk.parent_span_id`.
These are ephemeral diagnostic UUIDs with no Discord identity or persistence.
Events are observed in emission order; concurrent spans can interleave.

`DiscordLog.context` supplies additional application-owned metadata. Newly created
loggers copy that context; saved logger values retain their original context.
Structured tasks inherit it, detached tasks and later unrelated calls do not.
Apply a scope around the complete supervised lifetime. Calls made by unrelated
external tasks use that caller's scope; a run scope does not implicitly identify every
later call on the same actor. Shared RPC/Activity reader and writer tasks retain their
creation-time factory, configuration and application metadata. They rebind only bounded
request correlation for writes and replies; scope tenant routing around the owner's
complete lifetime. Logging creates no tracing
registry, timer task, network exporter or retries. Fixed event identity describes
the operation; safe metadata explains the current step. Full trace means runtime
control and ownership visibility, without dumping payloads or logging each sample,
media packet, cryptographic primitive or pure model accessor.

## Application setup

The executable chooses outputs and bootstraps once, before starting runtime work:

```swift
import DiscordLogging
import DiscordLogHandlers

LoggingSystem.bootstrap { label in
    var handler = StreamLogHandler.standardError(label: label)
    handler.logLevel = label.hasPrefix("discordkit.") ? .debug : .info
    return handler
}

let appLog = Logger(label: "my.application")
appLog.info("Application started")
appLog.notice("Command catalog synchronized", metadata: ["commands": "12"])
```

Do not bootstrap from a reusable library or repeatedly in unit tests. SwiftLog
handlers and thresholds belong to the executable. A production application can
use any compatible third-party handler without selecting `DiscordLogHandlers`.

For per-operation routing, tests or separate tenants, supply a native logger factory
in a task-local scope:

```swift
try await DiscordLog.$loggerFactory.withValue({ label in
    var logger = Logger(label: label)
    logger[metadataKey: "deployment"] = "staging"
    return logger
}) {
    try await runtime.run()
}
```

Apply the scope around the complete supervised lifetime or explicit operation.
Structured children and ordinary `Task` children inherit it; detached tasks, foreign
callbacks and unrelated later callers do not. Factories are looked up during execution,
not saved by inert constructors or static loggers. Factories must be cheap, concurrent-safe
and nonrecursive. Native `Logger.MetadataProvider` can supply dynamic task-local context;
forward the provider when bootstrapping a custom handler factory. Base metadata is
overridden by provider metadata, then per-call metadata.

## Destinations and ownership

| Destination | Selection and behavior |
| --- | --- |
| Console | SwiftLog `StreamLogHandler.standardOutput` or `.standardError`. |
| File | `DiscordFileLogSink` plus `DiscordFileLogHandler`; explicitly open and close one shared writer. |
| iOS/macOS unified log | Conditional `DiscordOSLogHandler`, available when Apple's `OSLog` module is importable. |
| Other outputs | `DiscordCallbackLogHandler` receives a Sendable structured record synchronously. |
| Multiple outputs | SwiftLog `MultiplexLogHandler`; use `DiscordLevelFilterLogHandler` for fixed destination floors when changing logger thresholds. |

For files, the parent directory must already exist and belong to the application:

```swift
let sink = try DiscordFileLogSink(
    url: applicationLogURL,
    configuration: .init(maximumFileBytes: 5 * 1_024 * 1_024,
                         maximumFiles: 3, maximumRecordBytes: 64 * 1_024)
)
LoggingSystem.bootstrap({ label, provider in
    var console = StreamLogHandler.standardError(label: label)
    console.logLevel = .info
    console.metadataProvider = provider
    return MultiplexLogHandler([
        DiscordLevelFilterLogHandler(console, minimumLevel: .info),
        DiscordFileLogHandler(label: label, sink: sink, logLevel: .debug,
                              metadataProvider: provider),
    ])
}, metadataProvider: .init { ["deployment": "staging"] })

// Stop/join the application's runtime children before closing the shared writer.
try sink.close()
```

These are alternative bootstrap examples; choose one per process. The independently
compiled [LoggingApp](../Examples/LoggingApp/README.md) demonstrates process bootstrap,
console/file multiplexing, dynamic metadata and a synthetic subsystem event offline.

The default file budget is three files of at most 5 MiB each, including the active
file; archives use `.1`, `.2`, and so on. A record includes its terminating newline
in the byte budget. Oversized records and excessive metadata are dropped before a
partial line is written or rotation begins. Metadata defaults to depth 16 and
1,024 total values. NDJSON preserves strings, arrays and dictionaries, escapes controls
and Unicode correctly, and includes label, level, message, metadata, source/file/function/
line, Unix epoch milliseconds and an error-presence flag. Attached error descriptions
are intentionally omitted. Custom metadata descriptions remain application code.

Writers synchronize handle/rotation/counters without queues or background tasks.
They block the logging caller; do not use them inside realtime audio callbacks.
Applications own forwarding queues, scheduling and retention for callback handlers.
Serialization limits bound retained output, not allocations already made by an
application's messages, metadata descriptions or concurrent callers.

Opening validates configured existing slots without truncating them, rejects
nonregular files/symlinks, and creates new files with mode 0600. Existing regular
files keep their permissions and content; crash-truncated NDJSON is not repaired.
Use one writer per destination and protect the parent directory from replacement.
The writer is not a cross-process logging service or a defense against concurrent
filesystem tampering. Archives outside the configured numbered slots are untouched;
reducing retention between runs requires deliberate cleanup of previous extra slots.
Successful writes are not crash-durability guarantees.

`snapshot` exposes fixed-size written/dropped/failure/rotation counters and closed
state. `onDiagnostic` receives sanitized errors outside the writer lock; concurrent
or recursive notifications are coalesced and counters remain authoritative. Logging
cannot throw: write/rotation failure closes the writer's admission, while explicit
open/close can throw. There is no retry, fallback, recursive diagnostic logging or
automatic reopening. Close waits for filesystem mutations already holding the writer lock and is idempotent.
Join all producer/log calls first: serialization already in progress can finish later,
drop its record and notify diagnostics after close returns.

Apple unified logging maps trace/debug to debug, info to info, notice/warning to
default, error to error and critical to fault. Original severity is preserved in
the record text. All dynamic message/context/location content is explicitly private;
only the fixed severity spelling is public. On-device capture, retention and viewing
private values follow the embedding application's OS logging configuration.

## Event coverage and privacy

Library events use `discordkit.<component>` labels, `dk.subsystem`, `dk.module` and fixed `dk.event`
metadata. Additional context is limited to safe counts, status codes, finite states
and attempt numbers. Application metadata is application-owned; handlers cannot infer
or sanitize arbitrary secrets an application explicitly logs.

| Owners | Instrumented boundaries |
| --- | --- |
| Transport, Foundation, NIO, Unix | Deadline expiration, lease acquire/renew/release, HTTP responses, WebSocket/IPC connect and local socket binding. |
| ApplePlatform | Explicit audio start/stop and host lifecycle resource draining; no realtime callback logs. |
| HTTP | Execution, response, cache/retry paths, admission and permanently failed coordinator. |
| Gateway, Client, Cache | Shard/socket/recovery lifetime, bounded subscriptions/dispatch, projection and entity refresh/retention. |
| Interactions, Commands | Signed admission, initial-response ownership, routing and explicit reconciliation. |
| DSL, CommandDSL, BotDSL | Explicit policy/middleware execution, HTTP serving and supervised bot/event pipelines. |
| OAuth | Authorization/token/device-poll operations and refresh ownership. |
| Commerce, CertifiedDevices | Entitlement/purchase and complete-array device-publication operations. |
| RPC, Activities, Social | Session/provider lifecycle, command admission, subscriptions and compatibility recovery. |
| Voice, DAVE, MLS, Media | Session/join/resume/control/recovery/epoch ownership, group/commit operations and stream termination. |

Bits/Core/Models and GameServices endpoint descriptors remain pure; the umbrella,
resource catalogs and extension/macro authoring packages inherit diagnostics from their
operation owners. Crypto/codec/DSP primitives, ratchets, exporters, frame transforms,
packet/sample processing and synchronous Social PCM controls emit no per-item logs.
Pure construction and DSL compilation emit none. The JavaScript Activity bridge has
no Swift runtime: its existing typed failures flow through the injected Swift Activity
owner; it gains no independent JavaScript console logger. The Activity host logging command and its wire `ActivityLogLevel` retain their
protocol meaning; they do not change the local SwiftLog severity policy.
Existing executable `print` calls are intentional CLI results/reports. The load,
benchmark and qualification executables explicitly bootstrap stderr diagnostics
at process entry, keeping report destinations separate. Reusable runners never
bootstrap SwiftLog.

No library event includes credentials, application URLs/paths, headers, request/response bodies,
interaction content, persistent user/guild/session identifiers, key material, human verification
codes or arbitrary error descriptions. Handler source locations use compiler-provided
module/file/function identifiers. No persistent identifier or unbounded diagnostic
state is added. Backend configuration never enters independently adopted runtime
product closures. The shared DSL gains only the logging-only dependency alongside
Core/Models; it still owns no runtime or concrete adapter.

## Validation and limits

Native Swift Testing capture suites verify factory inheritance/isolation, all levels,
lazy filtering, inert construction/compilation, event order, retries, cancellation,
redaction and a single permanent critical transition. Backend suites verify metadata
value semantics/provider precedence, multiplexing, bounded concurrent writes, Unicode/
JSON structure, rotation, oversized records, file validation, failures and closure.
The standalone example tests bootstrap/provider propagation in a separate process.

See [semantic logging validation](Release/semantic-logging-validation.json) for
current commands and observed results. The first [logging validation](Release/logging-validation.json)
remains a historical checkpoint. Local macOS compilation/tests, synthetic peers and bounded cache/broadcast
soaks do not qualify Linux/Windows/Android, physical iOS devices, unified-log capture,
live Discord, independent crypto review or production logging throughput. Default
handler semantics and active sink costs are separate from production capacity.
