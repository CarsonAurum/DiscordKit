# Gateway invocation resilience and safe diagnostics

Recorded and official interaction response documentation verified: 2026-10-19.
REST/Gateway remain v10. Upstream announcement/effective dates are unknown: this
is a local ownership/diagnostic change, not a new upstream contract.

Previously, an uncaught matched command, stale route or response failure escaped
the private interaction callback, terminated the adapter and cancelled the bot's
client/event siblings. The default behavior remains fail-fast. Hosts can now
explicitly select `GatewayInvocationFailurePolicy.continueInvocations` to end one
ordinary failed invocation and continue queued work on the existing connection.
Malformed routing/input, failed typed preparation, provenance/application mismatch,
continuity/overflow, owner/control and cancellation errors remain terminal.

Recovery never sends an alternative acknowledgement or failure follow-up, refreshes
an expired token, replays a handler or mutation, or reconciles possible effects.
Existing responder state, deadlines and independent initial admission remain.

`BotFailureDiagnostic` exposes a closed stage/category and optional numeric HTTP
status/API code/fatal Gateway close code. Synchronous nonthrowing observers receive
no arbitrary error or interaction; the library retains no token-indexed diagnostics.
Runtime aggregate entries are classified individually, at most three, without
recursive reflection. Read [adoption and attribution limits](../../BotApplications.md).

The unpublished root API candidate advances to 0.17.0 and records defaulted
initializer changes and additive APIs in a new baseline. Historical snapshots and
release evidence remain unchanged. Existing ordinary call sites compile unchanged;
explicit function-reference consumers must review the initializer declarations.

The reported MiniCarson Failed state predates its successful live command session
and remains unattributed. Local regression checks do not reproduce or prove its
cause, live Discord acceptance, cross-platform/device qualification or capacity.

Source: [official receiving and responding documentation](https://docs.discord.com/developers/interactions/receiving-and-responding).
