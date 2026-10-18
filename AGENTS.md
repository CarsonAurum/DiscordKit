# Repository guidance

## Project and layout

DiscordKit is a Swift Package Manager library. Part 1 implements portable values,
transport contracts and deterministic test support. Part 2 adds owned Foundation/NIO
network adapters, Unix IPC, Apple lifecycle ownership and a separate local load harness.
Part 3 adds HTTP execution, partial User/Application models and the required early
sharded Gateway lifecycle. Part 0 records
architecture/parity and separate probes.
Part 4 adds offline reviewed-definition validation and deterministic generation for
the existing model/endpoint slice; see `Docs/Generation.md`.
Part 5A adds typed message/poll REST operations, components, validated payloads,
bounded uploads and explicit continuation/bulk helpers; see `Docs/RESTCatalog.md`.
Part 5B adds channels/threads, type-specific settings, invite/recipient operations,
forum/media uploads and bounded membership/archive workflows; see `Docs/Channels.md`.
Part 5C adds guild administration, members/bans/roles, widgets/integrations,
onboarding/incidents and bounded workflows; see `Docs/Guilds.md`.
Part 5D adds audit logs, Auto Moderation rules, validated moderation payloads and
bounded audit traversal; see `Docs/Moderation.md`.
Part 5E adds guild/application emoji, stickers/packs and default/guild soundboard
operations, validated media and bounded uploads; see `Docs/Expressions.md`.
Part 5F adds invites/target-user jobs, guild templates, recurring scheduled events and
Stage instances with bounded workflows; see `Docs/DiscoveryEvents.md`.
Part 5G adds applications/users, linked-role metadata and application commands,
validated configuration/registration and bounded guild traversal; see `Docs/ApplicationsUsers.md`.
Part 5H adds webhooks, interaction callbacks/original/follow-up REST and voice state/region
operations with typed path-token scopes; see `Docs/WebhooksInteractionsVoice.md`.
Part 5I adds SKUs, entitlements, subscriptions, premium interaction data and bounded
monetization traversal; see `Docs/Monetization.md`.
Part 5J adds lobbies/members/messages, linked-channel invites and application identity
profiles with bounded bulk workflows and full-replacement stats; see `Docs/SocialGame.md`.
Part 6 adds all documented Gateway dispatch names, typed outgoing requests and
bounded correlated request execution with independent opcode admission; see
`Docs/Gateway.md`. Full child-resource projections, native Social SDK and other
resource-family completion remain separate.
Part 7 adds the independently adopted consumer client, bounded broadcast subscriptions
and ordered handlers, optional scoped entity cache/refresh and permission resolution;
see `Docs/Client.md`. Client construction starts no tasks or network I/O. Reuse shared
credential and aggregate resource authorities across client instances.
Part 8 adds independently adopted signed HTTP ingress, interaction response ownership,
early defer, command definitions/routing/reconciliation, durable webhook-event admission
and display-only link previews; see `Docs/Interactions.md`. Construction starts no tasks
or network I/O; initial acknowledgement admission remains independent of ordinary REST.

Part 9 adds independently adopted OAuth, GameServices and Commerce products for
state/issuer/PKCE flows, token ownership, public account/publisher backend operations
and server entitlement verification; see `Docs/OAuth.md` and `Docs/Phase9ServiceContracts.md`.
Secure storage/browser UI are injected; native SDK and unpublished Social Commerce
contracts remain blocked. Construction starts no network or background work.

Part 10 adds independently adopted RPC and CertifiedDevices products for local
RPC v1 sessions, typed commands/events and prioritized full-array device publication;
see `Docs/RPC.md` and `Docs/CertifiedDevices.md`. Construction starts no tasks or I/O.
Transport adapters and device identifiers are injected. Windows named-pipe I/O,
real desktop/hardware smoke tests, ambiguous WebSocket port bounds and presence
clearing semantics remain explicit gates; no remote Gateway substitutes for RPC.

Part 11 adds independently adopted Activities and an owned dependency-free browser
postMessage bridge for typed host commands/events, bounded correlation and shared
subscriptions; see `Docs/Activities.md`. Construction starts no I/O. Swift/browser
bindings and approved Discord Web/iOS/Android smoke qualification remain separate;
no standalone browser/native container creates a Discord Activity host.

Part 12 starts with independent Media, VoiceCodecs, VoiceCrypto and Voice products;
see `Docs/Voice.md`. They implement bounded PCM processing/streaming/clocks/pacing,
continuous linear/bandlimited resampling, statistical speech activity, ordinary Opus
framing/entropy, CELT pulse search/spreading/transforms and SILK LPC/LTP/excitation,
transport AEAD and pure Voice v8/RTP/discovery/control components. They do not yet
provide complete Opus codecs, MLS/DAVE or supervised network sessions. The Apple
platform adapter adds audio I/O, macOS input/output UIDs and supported preferred-input routing;
Windows/Android audio and hardware qualification remain open.
Construction starts no I/O. External crypto review, codec/MLS interoperability,
per-platform device qualification and ten-minute duplex evidence remain open.

- `Package.swift`: package manifest, library product, and target settings.
- `Sources/DiscordKit/`: library implementation and public APIs.
- `Sources/DiscordBits/`, `Sources/DiscordCore/`, `Sources/DiscordTransport/`:
  independent foundations; preserve Bits <- Core <- Transport dependency direction.
- `Tests/DiscordKitTests/` and matching foundational test suites: Swift Testing.
- `Sources/DiscordFoundationTransport/`, `Sources/DiscordNIOTransport/`: concrete
  injectable backends; portable products must never depend on them.
- `Sources/DiscordUnixPlatform/`, `Sources/DiscordApplePlatform/`: owned IPC/lifecycle.
- `Sources/DiscordModels/`, `Sources/DiscordHTTP/`, `Sources/DiscordGateway/`:
  presence-aware projections, bounded HTTP policy and independently adopted shard runtime.
- `Sources/DiscordInteractions/`, `Sources/DiscordCommands/`: signed ingress,
  transport-neutral response ownership and bounded command workflows; neither imports Gateway.
- `Sources/DiscordOAuth/`, `Sources/DiscordGameServices/`, `Sources/DiscordCommerce/`:
  independently adopted authentication, public game/backend and server entitlement workflows.
- `Sources/DiscordRPC/`, `Sources/DiscordCertifiedDevices/`: independent local RPC v1
  protocol/session ownership and certified-device publication; no HTTP/Gateway/OAuth dependency.
- `Sources/DiscordActivities/`: independent Activity protocol/client/catalog over Core/Transport.
- `Sources/DiscordMedia/`, `Sources/DiscordVoiceCodecs/`, `Sources/DiscordVoiceCrypto/`:
  bounded portable media, Opus packet/entropy structure and experimental voice crypto primitives.
- `Sources/DiscordVoice/`: deterministic voice framing/control/RTP components; no client ownership.
- `Examples/VoiceBot/`: offline synthetic voice-protocol consumer; never joins Discord.
- `Browser/DiscordActivityBridge/`: owned JavaScript bridge; no npm runtime dependencies.
- `Examples/ActivityHost/`: independent Activity/backend composition; build without authenticated calls.
- `Examples/RPCApp/`: independent portable RPC/device consumer; build without connecting to Discord.
- `Examples/OAuthApp/`: independent OAuth consumer; build without running authenticated calls.
- `Examples/RESTOnly/`: independent REST consumer; build it without running authenticated calls.
- `Examples/HTTPApp/`: independent signed HTTP consumer; build without authenticated calls.
- `Sources/DiscordCache/`, `Sources/DiscordClient/`: optional bounded entity state and
  supervised consumer composition; Cache must never import Gateway, HTTP or Client.
- `Examples/GatewayBot/`: independent bot consumer; build without authenticated calls.
- `Tools/DiscordKitLoadTests/`: independent local-only transport measurements and profiles.
- `Tests/DiscordTestSupport/`: internal development support target, never a product.
- `Docs/`: architecture, dependency/platform policy, feasibility findings and parity history.
- `Tools/DiscordKitTools/`: separate discovery/review validators, offline generator,
  parity checks, discovery script and their tests. Generated outputs are committed;
  consumer builds never fetch documentation or regenerate source.
- `Tests/Fixtures/PlatformProbe/` and `Tests/Fixtures/VoiceProbe/`: independently
  resolved feasibility packages; their dependencies are not production dependencies.

Introduce the roadmap's runtime sublibraries only with real implementations and tests.
Follow the adopted dependency directions in `Docs/Architecture.md`; preserve independent
REST, HTTP interactions, Gateway, OAuth2 and optional voice adoption.

## Build and validation

Use Swift 6.4 or newer, as required by the manifest. All root package targets enable the
`ApproachableConcurrency` upcoming feature and explicitly use nonisolated default
isolation; preserve these settings unless the task requires changing them.

Run these commands from the repository root for source or manifest changes:

```sh
swift build
swift test
```

For load-harness changes, also run `swift test --package-path Tools/DiscordKitLoadTests`
and its Python peer tests; see its README for local measurement commands. Root adapter
tests require loopback sockets but never Discord credentials. See `Docs/Transport.md`
for exact current behavior, ownership and open platform qualification gates.

For Part 0 tooling or inventory changes, also run:

```sh
swift test --package-path Tools/DiscordKitTools
swift run --package-path Tools/DiscordKitTools DiscordKitTools inventory validate --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools generate --check --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools parity check --repository .
python3 -m unittest discover -s Tools/DiscordKitTools/scripts -p 'test_*.py'
```

For reviewed-definition or generator changes, explicitly regenerate with
`generate --write --repository .`, review the output diff, and run the checks above
plus the root build/tests. Checks are nonwriting; use `--as-of YYYY-MM-DD` only for
historical reproducibility, never as a substitute for current source verification.

For feasibility fixture changes, run the affected separate package's `swift test
--package-path` command documented in `Docs/Feasibility/`. Runtime probes need local
loopback sockets; they never use Discord credentials or live Discord requests.
Root `swift test` does not include these independent packages. Keep their resolved
graphs and results synchronized with the feasibility report.

The root suites cover the implemented foundations, without live Discord requests.
For HTTP/Gateway changes, also build `Examples/RESTOnly` and run affected local load
scenarios. See `Docs/HTTP.md` and `Docs/Gateway.md` for authority sharing, ownership
and qualification limits. Source changes must meet the method documentation and unit testing requirements below.
For interaction/command changes, also build `Examples/HTTPApp` and preserve its selected
graph without Gateway, Client or Cache. See `Docs/Interactions.md` for signature/replay,
initial-response admission, token expiry and durable webhook acknowledgement contracts.
For consumer/cache/event changes, also build `Examples/GatewayBot` and run the load
package's cache/soak scenarios, including the fixed-working-set 30-minute local soak
and actual RSS/accounted-byte evidence described in `Docs/Client.md` and the load README.
For OAuth/game/commerce changes, also build `Examples/OAuthApp`; preserve its graph
without Gateway, Client, Cache, Commands or Interactions. Secure storage implementations
must enforce atomic generation replacement and publisher-child invalidation; no native
SDK wrapper or undocumented Commerce protocol counts as implemented support.
For RPC/device changes, also build `Examples/RPCApp`; preserve its graph without
HTTP, Gateway, Client, Cache, OAuth, Commands or Interactions. Use deterministic
local peers for framing, correlation, cancellation and device replacement tests.
Real Discord desktop/hardware tests and Windows named-pipe host qualification are
separate gates; preserve the documented port-range and presence-clear blockers.
For Activity changes, also build `Examples/ActivityHost` and run the browser bridge
with Node's built-in test runner (`node --test Browser/DiscordActivityBridge/*.test.mjs`).
Keep Activities independent of HTTP/Gateway/RPC/OAuth/Client/Cache. Use synthetic
Swift frames and simulated message hosts; approved Discord browser/mobile auth,
participant and purchase smoke tests remain separate gates. Keep client secrets
out of iframe/mobile code and verify entitlements through server-authoritative APIs.
For documentation-only changes, review the diff; a build is not required.

For media/voice changes, also build and run the offline `Examples/VoiceBot` package.
Preserve its graph without HTTP/Gateway/Client/Cache/OAuth or concrete adapters.
Run published primitive vectors and malformed/tamper/replay/counter/queue tests.
The local encoded-packet round trip does not satisfy the full codec/MLS/DAVE,
device, authorized Discord or ten-minute duplex gates in `Docs/Voice.md`.

For C# code on macOS, use `msbuild` rather than `dotnet`.

## Code conventions

- Follow the existing four-space indentation and Swift naming conventions:
  `UpperCamelCase` for types and `lowerCamelCase` for functions and properties.
- Keep library code in `DiscordKit` or the roadmap's implemented sublibrary targets;
  expose public APIs deliberately. Keep development tools and probes separate.
- Keep changes focused; add package dependencies only when the task needs them.

## Scalability and request efficiency

- Treat bot deployments serving hundreds through millions of accounts, and many
  independent bot identities, as an architectural requirement from the first
  runtime slice. Follow `Docs/Scalability.md`; distinguish served users, bot
  credentials, guilds, shards and actual concurrent connections in capacity claims.
- Keep rate admission coordinated across clients/workers sharing a credential;
  honor server/resource/egress scopes and bounded retry budgets. Define fairness,
  cancellation and coordinator-failure behavior. Sharding does not raise REST quotas.
- Reduce requests with authentication-scoped eligible-read coalescing, explicit
  bounded cache/freshness policies, lazy pagination and documented bulk operations.
  Preserve mutation ordering, partial results and indeterminate outcomes; do not
  invent generic batching or silently merge mutations.
- Plan sharding, startup budgets and ownership during architecture/transport work;
  deliver a multi-shard lifecycle alongside the first HTTP slice. Keep distributed
  coordination injectable and ordinary in-process adoption straightforward.
- Bound both per-identity and total queues, bytes, tasks, connections, caches and
  metadata. Keep heartbeat/control work independent of handlers and cache I/O.
  Test overload/failover deterministically and measure throughput, tail latency,
  memory and request reduction before each runtime capacity claim. Keep metrics
  label cardinality bounded and never use credentials as diagnostic identifiers.

## Method documentation

- Every explicitly declared function and method must have comprehensive Swift
  documentation comments (`///`), regardless of access level: `open`, `public`,
  `package`, `internal`, `fileprivate`, or `private`. This includes helpers, protocol
  requirements, initializers, deinitializers, operators, subscripts, accessors, and
  test functions. Small or apparently self-explanatory methods are not exempt.
- Provide as much accurate, useful detail as possible. Describe purpose, behavior,
  design rationale, assumptions, preconditions, invariants, and limitations; add
  implementation explanations where they help future maintenance.
- Document every parameter, including defaults, units, valid ranges, validation,
  and optional or nullable semantics. Document return values, empty or missing
  results, every known error and failure condition, and recovery expectations.
  Use DocC sections such as `- Parameters:`, `- Returns:`, and `- Throws:` as applicable.
- Explain side effects, state changes, resource ownership and cleanup, performance
  considerations, actor isolation, concurrency guarantees, suspension points,
  cancellation, ordering, and reentrancy wherever relevant.
- For Discord operations, include endpoint or event references, permissions and
  intents, API version requirements, rate limiting, pagination, retry behavior,
  and compatibility or deprecation details. Include usage examples and links to
  related symbols or official documentation where they clarify behavior.
- Document test intent, setup assumptions, exercised edge cases, and expected
  outcomes. Keep all documentation synchronized with implementation and tests in
  the same change; expand incomplete documentation when touching existing methods.
  State unknowns explicitly instead of inventing behavior or guarantees.

## Unit testing

- Every new or modified production method must have thorough unit tests using
  Swift Testing. This applies to functions, helpers, initializers, operators,
  subscripts, and accessors at every access level. Cover private implementation
  behavior through observable callers without widening visibility solely for tests.
- Use `import Testing`, `@Test`, `@Suite`, `#expect`, and `#require` as appropriate,
  with `@testable import DiscordKit` for internal APIs. Use Swift Testing for all
  new unit tests and async tests.
- Test as many meaningful possibilities, branches, edge cases, and failure
  conditions as possible for each method. Include normal behavior, alternate paths,
  boundary and extreme values, empty inputs, missing and null values, malformed or
  invalid inputs, repeated calls, and state transitions wherever applicable.
- For Discord behavior, cover request construction, encoding and decoding, unknown
  fields or enum values, large snowflake IDs, pagination, permissions, authentication
  failures, rate limits, retries, transport failures, and API error responses.
  Test Gateway ordering, duplicate events, reconnects, and resume behavior as those
  features are implemented.
- For concurrent methods, test success, thrown errors, cancellation before and
  during work, timeouts, resource cleanup, concurrent callers, and isolation or
  ordering guarantees. Use `async`/`await` directly in tests.
- Use parameterized tests to exercise input combinations and add regression tests
  for every bug fix. Assert outputs, errors, state changes, and observable side
  effects; an invocation without meaningful assertions is not adequate coverage.
- Keep unit tests deterministic and independent so they can run in parallel. Inject
  transports, clocks, and other dependencies to simulate responses and failures;
  avoid live Discord requests, real credentials, and timing-dependent sleeps.
- Run `swift test` after implementation changes and resolve failures before marking
  the work complete. Report remaining coverage gaps or checks that could not run.

## Modern Swift and dependencies

- Prioritize the most up-to-date syntax, APIs, and programming techniques supported
  by Swift 6.4 and the package's platform requirements. Check official Swift and
  library documentation rather than carrying forward outdated patterns.
- Design asynchronous I/O and event handling around `async`/`await` and structured
  concurrency. Use actors for shared mutable state, task groups or `async let` for
  related concurrent work, and `AsyncSequence` for asynchronous event streams where
  appropriate. Propagate errors and cooperative cancellation through the architecture.
- Respect Swift's isolation, executor, and `Sendable` rules. Prefer compiler-checked
  data-race safety; avoid blocking async work, unnecessary detached tasks, and
  unchecked concurrency escape hatches. Keep synchronous computations synchronous
  when they have no asynchronous work.
- Use current standard-library and Foundation APIs and the latest suitable stable
  releases of maintained libraries compatible with Swift 6.4 and supported platforms.
  Verify releases, compatibility, and migration notes when selecting or updating
  dependencies; document version constraints and any reason a newer release cannot
  be used. Adopt useful modern libraries as needed for the implementation.
- Consult the [Swift language documentation](https://docs.swift.org/latest/documentation/the-swift-programming-language/),
  [Swift 6.4 release notes](https://www.swift.org/blog/swift-6.4-released/), and
  [Swift Testing documentation](https://developer.apple.com/documentation/testing).

## Discord API currency and parity history

- Target the most recent officially available Discord API version for each relevant
  surface, including REST and Gateway. Verify versions, endpoints, events, schemas,
  permissions, intents, limits, and deprecations against the current
  [Discord API reference](https://docs.discord.com/developers/reference) and
  [Discord change log](https://docs.discord.com/developers/change-log) before
  implementing or updating integrations. Specify protocol versions explicitly;
  do not assume Discord's default version is the latest.
- Treat API parity as an ongoing, documented responsibility. Maintain a versioned
  parity inventory and chronological change history in the repository as Discord
  features are implemented or updated. Track endpoints, models and fields, Gateway
  events and opcodes, permissions, and intents with explicit supported, partial,
  unsupported, deprecated, or removed status and known gaps.
- For each addition, removal, or behavior change, record the upstream API version,
  Discord announcement and effective dates when available, official source links,
  and the date the information was verified. Separately record when DiscordKit
  added, changed, deprecated, or removed support, including its release or commit
  when available. Use explicit dates (`YYYY-MM-DD`) and mark unknown dates as unknown.
- Document previous and current behavior, affected symbols and payloads, breaking
  changes, migration guidance, and compatibility decisions. Preserve historical
  entries as parity evolves; include changes within an API version as well as
  version upgrades. Never infer upstream introduction dates from local commit dates.
- Update method documentation, parity records, and regression tests together with
  implementation changes. Verify behavior against official schemas and realistic
  fixtures before claiming support; distinguish partial coverage from full parity.

## Workspace hygiene

- Inspect the working tree before editing and preserve unrelated user changes.
- Keep generated build output, local IDE metadata, and credentials out of commits;
  follow the existing `.gitignore`.
- Report which validation ran and any failures or checks that could not run.
