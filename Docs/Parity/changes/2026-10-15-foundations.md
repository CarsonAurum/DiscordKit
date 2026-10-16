# 2026-10-15: Part 1 portable foundations

Previous behavior: a `hello()` greeting and empty test scaffold. Current behavior:
independent Bits, Core and Transport products implement local foundational values,
bounded body ownership and injectable transport contracts, with deterministic
Swift Testing coverage. The umbrella product exposes common Core type aliases.

Affected symbols include `UnsignedBitSet`, `Snowflake`, `ExternalIdentifier`,
`JSONValue`, `JSONNumber`, `JSONLimits`, `Field`, `Nullable`, `RawValue`,
`DiscordTimestamp`, `Secret`, `Credential`, `DiagnosticRedactor`, `DiscordError`,
`CapabilityAvailability`, `TransportContext`, `BodyStream` and transport protocols.
Full public contracts, resource limits and Codable restrictions are documented
in [Foundation](../../Foundation.md) and the declarations.

The official [reference](https://docs.discord.com/developers/reference),
[permissions](https://docs.discord.com/developers/topics/permissions) and
[change log](https://docs.discord.com/developers/change-log) were verified on
2026-10-15. REST v10 / Gateway v10 / Voice Gateway v8 remain the baseline;
no request is sent by these values. Discord announcement and effective dates for
the underlying primitive formats are **unknown**. Local support date is
**2026-10-15**; release and commit are **unknown** until assigned.

Compatibility: removing `hello()` is a source-breaking scaffold cleanup. Remove
greeting calls and adopt the portable products as needed. The Apple deployment
baselines already documented in Part 0 are now explicit manifest requirements:
macOS 13, iOS/tvOS 16, watchOS 9 and visionOS 1. Future network adapters remain
independently adoptable. JSON numeric fidelity requires `parse`/`serialized`;
generic Codable is intentionally restricted rather than silently rounding.

Validation covers UInt64 boundaries and malformed identifiers; bits 64/127/255;
large decimal conversion and set operations; JSON numeric precision, unknown
data, syntax and resource limits; omitted/null/value fields; dates and unknown
enum values; secret diagnostics; cancellation, deadlines, stale completions and
exactly-once cleanup. No Discord credentials or live requests are used.

Executed checks on macOS arm64 / Swift 6.4:

| Check | Result |
| --- | --- |
| `swift build` | Passed, all foundational products and development support. |
| `swift build --target DiscordCore` | Passed independently; Core depends only on Bits. |
| `swift test` | Passed, 92 test methods in 12 suites / 321 executions including parameterized cases. |
| Tooling `swift test` | Passed, 35 test methods / 300 executions. |
| `inventory validate --repository .` | Passed, 18,137 records / 280 sources; zero unclassified discovered IDs and zero implemented operation records. |
| Python extraction tests | Passed, 10 tests. |
| Platform feasibility tests | Passed, 3 test methods / 7 local HTTP/TLS/WebSocket/UDP cases. |
| Voice feasibility tests | Passed, 5 test methods / 10 primitive cases. |
| Manifest and diff review | Four public products, no external production dependencies, uniform concurrency settings; Markdown/history references and whitespace checks passed. |

The managed sandbox prevents normal system compiler-cache access; final Swift
checks ran with approved host access. Initial compilation and regression failures
were resolved before the final successful runs. No other-host execution result
is inferred from these macOS checks.

The discovery inventory's protocol-support statuses are unchanged: local values
and protocol declarations do not implement endpoints, full resource payloads or
named permission behavior. API-operation support remains zero. The Part 0
coverage report remains historical. Cross-platform builds, actual adapters,
protocol integration and existing feasibility blockers remain open.
