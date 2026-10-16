# Portable foundation contracts

Part 1, verified 2026-10-15 with Swift 6.4 on macOS arm64. These products perform
local computation and define injectable I/O contracts. They do not connect to
Discord. The production dependency graph is `DiscordBits <- DiscordCore <-
DiscordTransport`, with `DiscordKit` depending on Core for common public aliases.
All targets retain `ApproachableConcurrency` and nonisolated default isolation.

## Identifiers and bits

`Snowflake<Tag>` preserves all UInt64 values with string-only Codable and numeric
comparison. Standard resource aliases prevent mixing user, channel and other IDs.
Zero is accepted as a boundary value, without asserting resource existence. The
timestamp accessor uses the documented epoch and bit layout; the inverse
timestamp initializer checks before-epoch and overflow boundaries. External
provider/user identifiers remain distinct opaque strings.

`UnsignedBitSet` grows in 32-bit words, supports union, intersection, XOR, removal
and subset checks, and serializes canonical decimal strings. Leading zeroes are
normalized. Decimal parsing defaults to 16,384 digits and bit insertion to an
inclusive maximum position of 1,048,575; callers can configure these resource
limits. No named permission policy or overwrite resolution is implemented.

Discord specifies [snowflakes and string serialization](https://docs.discord.com/developers/reference#snowflakes)
and [variable-length permissions](https://docs.discord.com/developers/topics/permissions).
Those contracts and the [change log](https://docs.discord.com/developers/change-log)
were checked on 2026-10-15. REST/Gateway v10 remain the adopted protocol baseline;
these local values do not send versioned requests or require permissions/intents.
Upstream introduction dates remain unknown.

## Lossless JSON and field presence

Use `JSONValue.parse` and `serialized` to retain arbitrary numeric lexemes,
including integers beyond UInt64, fractional trailing zeroes, negative zero and
extreme exponents. Unknown object fields and variants remain in the tree.
Whitespace, object order and escape spelling are not retained. Duplicate decoded
keys, including canonically equivalent Unicode keys under Swift string equality,
are rejected to avoid data loss; output keys are sorted deterministically.

The parser/writer defaults are 1 MiB of UTF-8, 64 container levels and 100,000
nodes. Configurable depth is capped at 128. Malformed Unicode, invalid number
grammar, trailing documents and exceeded bounds fail with typed, content-free
diagnostics. Computation is synchronous and bounded by the selected limits.

Generic `Decoder` does not expose original number tokens, and Foundation can
round long fractions even when decoding integers. Consequently, `JSONValue`'s
Codable bridge rejects numeric decoding. It encodes only canonical Int64/UInt64
numeric spellings; fractions, exponent forms and larger integers require the
explicit lossless serializer. Nonnumeric trees can use the Codable bridge.
Codable does not apply `JSONLimits`; bound the outer input separately. Future
endpoint codecs must use the lossless path when retaining unknown numeric data.

`Field<Value>` represents `.absent`, `.null` and `.value`. Use keyed
`encodeField(_:forKey:)` / `decodeField(_:forKey:)`; a standalone value encoder
cannot omit a containing key. `Nullable<Value>` represents a required response
key that may contain null; a missing required key fails decoding. Endpoint
nullability is a separate validation responsibility. `RawValue<Known>` retains
unknown enum raw values without inventing a known case.

## Dates, secrets and capabilities

`DiscordTimestamp` validates an extended Gregorian ISO-8601 profile and retains
the original spelling plus exact Unix seconds/nanoseconds. It accepts one to nine
fractional digits, explicit `Z` or numeric offsets, and four-digit years 0001–9999.
Leap seconds and other profiles are rejected. Foundation `Date` is an explicitly
approximate convenience; use exact components for precision-sensitive work.

Typed credentials reject empty/whitespace/control input and conceal contents in
ordinary descriptions, debug output and mirrors. Accessing a token requires an
explicit `withUnsafeValue` call. Strings are not encrypted or guaranteed to be
erased. `DiagnosticRedactor` filters registered strings and common encoded forms,
suppresses sensitive headers/bodies and recognizes credential-bearing paths.
It is a best-effort diagnostic filter; arbitrary transformations of unregistered
secrets are outside its contract. Never log raw transport payloads.

`DiscordError` carries safe categories and numeric API codes, distinguishing
validation, transport failure, cancellation and unknown mutation outcomes.
An ambiguous mutation must be reconciled before retrying. Capability reporting
distinguishes host restrictions, missing configuration, unqualified implementations
and missing upstream contracts. An unavailable result establishes no API parity.

## Transport ownership and deterministic verification

`DiscordTransport` defines HTTP exchange/ingress, complete WebSocket messages,
datagrams and IPC byte streams. Adapters own framing, actual cancellation and
resource release; endpoint policy, authentication and retry behavior belong above
them. No adapter or automatic retry is included here.

`TransportContext` uses an injected Swift `Clock` and optional absolute deadline.
Its structured race cancels and awaits the losing child. Operations must cooperate
with cancellation; a deadline cannot forcibly stop blocking code. Simultaneous
completion/expiration has no total-order guarantee.

`BodyStream` pulls on demand with a maximum chunk size and no queued chunks.
Concurrent reads fail. EOF, producer failure, cancellation and explicit close
release the source exactly once; late completions cannot yield data after close.
The owner must close an abandoned stream. Cleanup must complete promptly even
when its owner is cancelled; synchronous executor blocking is prohibited.

The internal `DiscordTestSupport` target provides a manual monotonic clock,
seeded randomness, explicit barriers, scripted transports and resource counters.
It is excluded from public products. Its `Mutex`-backed clock requires macOS 15,
iOS/tvOS 18, watchOS 11 or visionOS 2 on Apple hosts, without raising production
minima. Scripts exercise deterministic ordering, cancellation and stale completion
races without live Discord requests or timing-dependent sleeps.

Root `swift build` and `swift test` validate these foundations; the separate
tooling and feasibility commands remain documented in the repository guidance.
Results and remaining qualification limits are recorded in the
[Part 1 history](Parity/changes/2026-10-15-foundations.md). Other-host builds and
runtime network qualification remain open for the relevant adapter phase.
