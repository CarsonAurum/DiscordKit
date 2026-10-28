<!--
File: Docs/Parity/changes/2026-10-19-gateway-zero-reset.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Gateway discovery with a zero reset interval

On 2026-10-19, DiscordKit accepts Gateway discovery responses whose session-start
limit has `reset_after: 0`. Previously, the positive-reset validation rejected such
a response before opening a WebSocket. The reported input was HTTP 200 with
`total: 1000`, `remaining: 1000` and `reset_after: 0`.

The [official session-start reference](https://docs.discord.com/developers/events/gateway#session-start-limit-object)
describes `reset_after` in integer milliseconds, remaining/total starts and the
five-second `max_concurrency` limit, but does not define zero-reset semantics.
This change is conservative local compatibility behavior; no upstream announcement
or effective date is inferred from the observed response.

Zero does not grant an unbounded allowance or schedule automatic replenishment.
Identify reservations consume the reported remaining quota before writes, are
never refunded, and retain the existing concurrency bucket spacing. Repeated
zero-delay snapshots cannot restore locally spent starts. A zero-delay refresh
clears any previous reset deadline because the newer snapshot supplies no usable
future deadline. A later positive delay establishes a future one-shot reset without
immediately restoring spent starts. Negative intervals and the existing 30-day
bound remain rejected. Exhaustion without a known future reset requires fresh
discovery.

This is a source-compatible bug fix with deterministic local regression coverage.
It introduces no new Gateway payload fields, protocol version or public symbols.
Local validation does not establish live Discord interoperability, distributed
admission correctness, cross-platform qualification or runtime capacity. See the
[Gateway ownership and qualification limits](../../Gateway.md).
