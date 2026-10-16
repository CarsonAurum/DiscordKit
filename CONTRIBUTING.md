# Contributing

DiscordKit is implementing its roadmap incrementally. Read the
[architecture](Docs/Architecture.md), [concurrency](Docs/Concurrency.md),
[dependency](Docs/Dependencies.md), [platform](Docs/PlatformSupport.md) and
[parity](Docs/Parity/README.md) records before changing a public contract.
Repository agent guidance also applies to every contribution.

## Focus and evidence

Inspect the working tree first and preserve unrelated changes. Use four-space
indentation, Swift naming conventions and deliberate public access. Add a target
only when it contains real code. Optional products must retain the dependency
boundaries documented in the architecture; do not add a dependency simply because
it may be useful later.

Use official, current Discord documentation before implementing a protocol. Record
the protocol version explicitly and distinguish implementation status from
approval, portal, host or unavailable-wire-contract restrictions. Preview OpenAPI
material assists discovery but does not override Discord's written documentation.
Pin development evidence to revisions where possible. Consumer builds must not
fetch documentation or regenerate source.

Every integration change updates the relevant inventory rows, chronological
history, method documentation and regression tests together. Record previous and
current behavior, affected symbols/payloads, migration impact, verified date and
official sources. Preserve old entries and use `unknown` for unknown upstream
announcement or effective dates. Raw-route access and placeholder throwing APIs
do not establish typed parity.

## Declaration documentation

Every explicitly declared function, method, initializer, deinitializer, protocol
requirement, operator, subscript, accessor and test function needs comprehensive
`///` documentation at every access level, including private helpers.

Explain purpose, behavior, rationale, assumptions and invariants. Document each
parameter, defaults, optional semantics and valid ranges; describe return values,
empty results, thrown errors, failure recovery, side effects and cleanup. Include
isolation, suspension, cancellation, ordering, resource ownership, reentrancy and
performance details where relevant. State unknown behavior explicitly.

For Discord operations, identify endpoints/events, versions, permissions/intents,
rate limits, pagination, retry semantics and compatibility changes. Add examples
and official links when they clarify actual behavior. Presence of a comment alone
does not establish accuracy; review its contents with the implementation.

## Tests

Use [Swift Testing](https://developer.apple.com/documentation/testing):
`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`, parameterized cases and
direct `async`/`await`. Use `@testable import DiscordKit` for the current internal
API; future suites import the module under test. Exercise private behavior through
observable callers without widening visibility solely for tests.

Every new or modified production method needs meaningful tests for applicable
normal, alternate, boundary, invalid, empty, missing/null and repeated-call cases.
Concurrent operations need deterministic cancellation before/during work, error,
timeout, ordering, reentrancy, cleanup and concurrent-caller tests. Protocol work
also covers request/response codecs, unknown variants, large IDs, authentication,
API/transport failures, rate limits, retries and pagination. Gateway work covers
duplicates, reconnect and resume as those features arrive.

Inject transports, clocks and scripted peers. Unit tests need no live Discord
requests, real credentials or timing-dependent sleeps; they must be safe to run
independently and in parallel. Assert results and observable effects. Invoking a
method without an assertion is not sufficient coverage.

## Validation and review

Use Swift 6.4 or newer and retain `ApproachableConcurrency` plus deliberate target
isolation settings. For source or manifest changes, run from the repository root:

```sh
swift build
swift test
```

Whenever parity records or validation tooling change, run the separate offline
development tool and its deterministic validator suite:

```sh
swift run --package-path Tools/DiscordKitTools DiscordKitTools inventory validate --repository .
swift test --package-path Tools/DiscordKitTools
python3 -m unittest discover -s Tools/DiscordKitTools/scripts -p 'test_*.py'
```

The tool declares a macOS 13 minimum on macOS for current Foundation URL APIs;
this development requirement does not set the runtime library's deployment target.
Structural validation checks the recorded discovery set and evidence metadata;
it does not establish semantic completeness or platform runtime qualification.

Documentation-only changes require diff and link review; a package build is not
otherwise required. For C# work on macOS, use `msbuild` rather than `dotnet`.

Report the checks run, their outcomes, coverage gaps and unavailable platforms or
tools. A cross-compile result must not be described as a runtime qualification.
Keep build outputs, IDE metadata, credentials and local smoke-test secrets out of
commits. Include reviewed deterministic generated source and fixture provenance
when those become part of an implemented feature.
