# Semantic logging and detailed runtime traces

Recorded locally: 2026-10-20. This changes local diagnostics, not an upstream
Discord contract. Upstream announcement/effective dates are unknown; protocol
versions and payloads remain unchanged. No official source re-verification is claimed.

The initial implementation logged mostly operation starts and ends, used coarse
labels, and reserved info/notice for application events. Runtime owners now expose
admission, state/protocol decisions, response decoding, recovery and cleanup through
fixed dotted categories and safe structured fields. Trace carries individual steps;
debug summarizes diagnostics; info records significant normal lifecycle outcomes;
notice records milestones and recovery. Warning/error/critical retain distinct
operational meanings, with ordinary cancellation and bounded rejection kept diagnostic.

`DiscordLogConfiguration` resolves longest dotted-prefix thresholds. Task-local
context and operation scopes add ephemeral trace/span/parent identifiers and monotonic
durations while preserving results, errors, actor isolation and ownership. RPC/Activity
queues retain only bounded diagnostic correlation so later writes/replies remain
attributable to the correct request. `DiscordLevelFilterLogHandler` keeps output
floors fixed when a multiplex logger changes level.

The unpublished runtime candidate advances to 0.18.0 with a separate API baseline.
Update exact-label filters and default-level output expectations. Existing report
and baseline checkpoints stay historical. See [adoption](../../Logging.md),
[migration](../../Migration.md) and [validation](../../Release/semantic-logging-validation.json).

Pure construction/compilation, sample/packet processing and crypto primitives remain
quiet. Local synthetic/load evidence does not qualify live Discord, other platforms,
hardware, independent crypto review or production trace-output throughput.
