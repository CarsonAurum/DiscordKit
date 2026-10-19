# Integrated SwiftLog diagnostics

DiscordKit uses Apple's [SwiftLog](https://github.com/apple/swift-log) for Swift
runtime diagnostics. Select `DiscordLogging` for the shared entry point and native
`Logging` APIs; select `DiscordLogHandlers` separately for owned output backends.
SwiftLog 1.16.1 is the minimum and resolved version for this change. `DiscordLogging` and existing runtime owners
never bootstrap SwiftLog, open outputs or change application log thresholds.
Existing diagnostics, typed errors, cancellation and resource ownership stay authoritative.

## Design and implementation plan

1. Introduce a small logging-only foundation and a separately selected backend product.
2. Instrument explicit operation, admission, recovery and shutdown owners throughout
   the ecosystem with fixed event names and safe structured metadata.
3. Keep construction, pure authoring/compilation and realtime/sample/crypto loops quiet.
4. Validate native handler contracts, scoped propagation, redaction, independent
   consumer graphs and bounded local runtime cleanup; document actual evidence separately.
5. Review the complete diff and commit the integrated source, tests, guides and pins.

This is diagnostic integration, not a new metrics, tracing, audit-event or persistence
authority. Events can help investigate behavior; they do not replace returned errors,
protocol security decisions or durable interaction admission.

## Severity policy

The policy follows [Swift's library logging guidance](https://www.swift.org/documentation/server/guides/libraries/log-levels.html).

| SwiftLog level | Meaning in DiscordKit |
| --- | --- |
| `trace` | Fine admission, bounded counts, policy evaluation and operation details. |
| `debug` | Normal subsystem lifecycle, responses, retries and caller-visible failures. |
| `info` | Reserved for application semantic events; runtime libraries emit none. |
| `notice` | Reserved for application milestones; runtime libraries emit none. |
| `warning` | Autonomous degradation/recovery or a documented compatibility fallback. |
| `error` | Terminal supervised subsystem failure or failed owned cleanup. |
| `critical` | A permanently unusable safety authority: the fail-closed REST coordinator. |

The coordinator emits its critical transition once and rejects future admission;
the application must repair the external authority and replace the coordinator.
Routine HTTP failures, invalid inputs, 429s, overload rejections and cancellation
do not create high-severity alerts. Severity does not change control flow.

SwiftLog's default process handler filters below `info`, so ordinary subsystem
flow is quiet until the application enables debug or trace. All seven severities
are supported by the optional handlers, including the two application levels.

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
| Multiple outputs | SwiftLog `MultiplexLogHandler`; each child keeps its own threshold. |

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
        console,
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

Library events use `discordkit.<subsystem>` labels, `dk.subsystem` and fixed `dk.event`
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
interaction content, user/guild/session identifiers, key material, human verification
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

See [logging validation](Release/logging-validation.json) for commands and observed
results. Local macOS compilation/tests, synthetic peers and bounded cache/broadcast
soaks do not qualify Linux/Windows/Android, physical iOS devices, unified-log capture,
live Discord, independent crypto review or production logging throughput. Default
handler semantics and active sink costs are separate from production capacity.
