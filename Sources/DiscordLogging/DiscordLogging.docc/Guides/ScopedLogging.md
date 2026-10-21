# Configure logging at the application boundary

Choose a native SwiftLog handler before starting subsystem work.

## Overview

Import `DiscordLogging` to use native `Logger` and ``DiscordLog``. Configure
`LoggingSystem.bootstrap` once from the executable, or override
``DiscordLog/loggerFactory`` in a task-local scope around explicit runtime work.
Factories must be cheap, concurrency-safe and nonrecursive. Structured child tasks
inherit a scoped factory; detached work and unrelated callers do not.

``DiscordLog/makeLogger(_:)`` adds a stable `discordkit.<subsystem>` label and
`dk.subsystem` metadata while preserving application thresholds. Library event
sites add fixed `dk.event` values and safe counts/states. `dk.module` identifies the
first dotted category component for module filtering. All seven severity levels
carry semantic meaning. Runtime code starts no output or global bootstrap.

Set ``DiscordLog/configuration`` around an operation to select a
``DiscordLogConfiguration``. Longest dotted-prefix matching allows `http` debug
and `http.execution` trace while other modules stay at info. Without a scoped policy,
the application factory's threshold is preserved. Native multiplex level changes also
update child thresholds; a fixed output-level filter preserves destination minimums.

``DiscordLog/context`` copies application context into new loggers. Correlated
operation scopes add ephemeral `dk.trace_id`, `dk.span_id` and `dk.parent_span_id`
fields, start/terminal events and monotonic `dk.duration_ns` terminal timing.
Nested operations and structured tasks inherit the trace. No persistent Discord
identifier, registry, timer task or network tracing provider is created.

Pure values and per-frame DSP/crypto paths remain quiet. Apply scopes around the full
supervised lifetime so child operation events use the same destination and context.
Native SwiftLog metadata providers can attach application context without changing
the subsystem API. Application-supplied metadata remains its privacy responsibility.
