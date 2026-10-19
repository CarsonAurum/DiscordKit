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
framing/entropy, mono/stereo SILK/CELT/hybrid coding, ordinary mode transitions and PLC/CNG/FEC,
transport AEAD and pure Voice v8/RTP/discovery/control components. They do not yet
provide perceptually qualified full codec policies or supervised network sessions. The Apple
platform adapter adds audio I/O, macOS input/output UIDs and supported preferred-input routing;
Windows/Android audio and hardware qualification remain open.
Construction starts no I/O. External crypto review, codec/MLS interoperability,
per-platform device qualification and ten-minute duplex evidence remain open.

Part 12B adds independently adopted DiscordMLS with owned MLS 1.0/ciphersuite-2
wire, basic credentials, signed key packages, TreeKEM, key/secret trees, epoch
exporters and the restricted group-handshake profile required by DAVE v1; see
`Docs/MLS.md`. It selects only Swift Crypto and owns no transport or device I/O.
Trusted participant identity/key associations and the expected external sender
are application-supplied. Independent crypto review,
complete-client interoperability and live Discord qualification remain separate.

Part 12C adds independently adopted DiscordDAVE for authenticated Voice/MLS
transition coordination, sender ratchets, codec-aware encoded-frame encryption,
bounded replay/verification and ephemeral human verification; see `Docs/DAVE.md`.
DAVE depends on Voice/MLS/VoiceCrypto/Core/Transport and existing Crypto/CryptoExtras;
Voice and VoiceCrypto remain independent of MLS/DAVE. Construction starts no tasks,
sockets, devices or persistence. Trusted external sender/participant membership,
shared signing identity and monotonic clocks are injected. Downgrade fails closed.
Independent crypto review, complete-client/live interoperability, platform/device
qualification and 12D supervised network/duplex evidence remain open.

Part 12D adds supervised `VoiceSession`/`VoiceManager`, owned UDP discovery and
heartbeat/resume lifetimes, bounded authenticated SSRC media routing, paced PCM/
encoded Opus, jitter/PLC and playback/recording primitives. `DAVEVoiceSession`
implements injected Voice interfaces while preserving DAVE -> Voice dependencies.
Constructors remain inert; `run`/join own work and stop/leave close it. The separate
local UDP qualification harness uses synthetic PCM and owned MLS/DAVE peers;
authorized Discord, independent review and full device/platform qualification
remain explicit gates. See `Docs/VoiceSessions.md`.

Part 13 adds independently adopted `DiscordSocial`: explicit consent/host capability
coordination over narrow owned HTTP/RPC/Activity providers, bounded scoped relationship
state, local PCM controls and exhaustive SDK/Commerce/mobile gap accounting. OAuth also
adds the published confidential backend device grant with explicit bounded polling.
Construction starts no work. No native Discord runtime or guessed Social/Commerce wire
is permitted; see `Docs/Social.md` and `Docs/Parity/phase13-social-catalog.json`.

Part 14 adds release certification, DocC adoption/setup/migration guides, owned
SwiftSyntax callable-documentation auditing, dependency/import/product isolation,
public API/semver baselines, platform CI and weekly official-source review. See
`Docs/Release/README.md`, `Docs/ReleaseTooling.md` and `Docs/CI.md`. The 0.14.0
candidate is unpublished. Unverified platform/live/hardware/crypto/interop gates
remain explicit exclusions, and syntactic presence never proves semantic completeness.

Part 15A adds independently adopted `DiscordDSL`: synchronous module/body and public
contribution protocols, structural builders, stable explicit module IDs, source diagnostics
and bounded deterministic declaration descriptions. It selects Core/Models only; existing
products remain independent of the DSL. Construction and compilation start no tasks, I/O,
registration or handler execution. Command lowering/macros, response builders/policies
and HTTP/Gateway hosts remain later milestones; see `Docs/DSL.md` and
`Docs/DSLImplementationRoadmap.md`.

Part 15B adds independently adopted `DiscordCommandDSL`: finite typed argument schemas
and strict per-invocation decoding, manual slash-command contributions, explicit
validated-command adapters and deterministic lowering to existing command definitions
and routes. It selects DSL/Core/Models/Commands/Interactions; existing products and
shared DSL retain their independent graphs. Construction/compilation start no tasks,
I/O, registration or handler execution. Explicit router invocation uses existing
interaction ownership. Macros, response builders/policies and HTTP/Gateway hosts
remain later milestones; see `Docs/CommandDSL.md`.

Part 15C adds the separate `Packages/DiscordDSLMacros` authoring package for
`@CommandArguments`, `@Option` and `@SlashCommand`, compiled execution parity and
external diagnostic fixtures. Runtime products remain independent of compiler plugins
and SwiftSyntax. Manual response ownership remains unchanged; see `Docs/MacroDSL.md`.

Part 15D adds typed immediate/deferred response handlers, restricted command contexts,
validated JSON message responses and `CommandApplication` over the existing signed HTTP
application/router. Initial response admission remains independent. Construction and
ordinary listener execution register no commands; synchronization is explicit.
The independent `Examples/DSLCommands` uses a macro-authored command in a synthetic
signed offline exchange, with listener ownership only when explicitly requested.
Policies, broader command families and Gateway hosts remain later milestones;
see `Docs/CommandResponses.md`.

Part 15E adds pure `MessageContent` authoring in `DiscordDSL`, with safe dynamic
text interpolation, typed user/role/channel mentions and explicit mention allowlists.
`DiscordCommandDSL` adds message/component builders and validated lowering to existing
Models. Thin immediate/deferred builder adapters retain existing response ownership.
Trusted literals/raw segments preserve markup; ordinary dynamic strings are escaped
and mention-neutralized.
Construction starts no tasks, registration or I/O; manual raw Models remain
available. See `Docs/MessageBuilders.md`.

Part 15F adds command trees, typed user/message context menus, partial autocomplete,
exact component/modal handlers and explicit compiled-catalog reconciliation over the
existing Commands/Interactions owners. Family response types keep autocomplete,
modal opening, message updates and message replies separate. Construction and ordinary
serving register nothing. Existing Models remain authoritative for supported fields;
policies, Gateway hosts and capacity qualification remain later milestones. See
`Docs/CommandFamilies.md`.

Part 15G adds bounded `InvocationPolicy`/`InvocationMiddleware` values in the shared
DSL and explicit command authorization, guild/context observations, injected aggregate
concurrency and rejection/error mapping. Complete typed input preparation precedes
policies and deferral. Middleware terminal execution is single-use and closes before
admission releases; existing response owners preserve deadlines and uncertainty.
Construction starts no work; HTTP rate authorities remain unchanged. See
`Docs/CommandPolicies.md`. Gateway hosts and capacity qualification remain later milestones.

Part 15H adds independently adopted `DiscordBotDSL`: typed Gateway selectors/handlers,
explicit intent validation, one default bounded subscription and finite independent
event groups over the existing complete-shard dispatcher. Construction and compilation
start no tasks, subscriptions, client startup or registration. Explicit subscribe/run
owns only event pipelines; Part 15I adds explicit supervised client/interaction hosts.
See `Docs/GatewayEventModules.md`.

Part 15I adds `BotApplication`, `BotRuntime`, shared typed REST service access and a
trusted Gateway interaction bridge to `DiscordBotDSL`, explicitly composing existing
Client/CommandDSL/Commands/Interactions/HTTP/Transport owners. Construction starts no
work. The runtime subscribes before client startup and cancels/closes/joins client,
event and interaction children on terminal exit. Only the client's package-internal
ingestion boundary supplies interaction provenance; public event publication cannot
authenticate input. Callbacks retain existing HTTP ownership and independent initial
response admission. Registration remains explicit. No concrete adapter or compiler
plugin enters the runtime product. See `Docs/BotApplications.md`.

Part 15J adds explicit `ModuleNamespace` installation and lazy `DependentModule`
construction over typed Sendable `ModuleDependencies`. Compilation admits each module,
validates local dependencies and then creates its body; dependency failures are bounded
and redact the original error. Namespace component paths qualify structural identities
without rewriting original metadata, command wire routes or event handler IDs.
The separate `Packages/DiscordDSLExtensions` package demonstrates public external
adoption through independent HTTP/Gateway consumers. Existing runtime graphs remain
unchanged; optional Voice/Social/OAuth interfaces are injected application choices.
Construction and compilation start no tasks, I/O, registration or handler execution.
See `Docs/ModuleExtensions.md`; local extension adoption does not qualify production
capacity or final release certification.

Part 15K adds the independent `Tools/DiscordDSLBenchmarks` package for finite paired
direct/DSL handler measurements, compiler costs with/without macros and explicit
regression budgets. Functional gates include cached schemas, bounded state, no implicit
hydration/registration and zero owned cleanup counters. Existing cache/broadcast and
new handler soak evidence remain separate. No runtime product selects this tooling;
local measurements do not establish production or fleet capacity. See `Docs/DSLBenchmarks.md`.

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
- `Sources/DiscordMLS/`: independently adopted MLS 1.0/ciphersuite-2 key establishment,
  ratchet trees and restricted DAVE-profile group handshakes; no transport/media ownership.
- `Sources/DiscordVoice/`: deterministic voice framing/control/RTP components; no client ownership.
- `Sources/DiscordDAVE/`: exact-session Voice/MLS signaling ownership, sender ratchets,
  codec-aware frame transforms and bounded ephemeral verification; no transport/device I/O.
- `Sources/DiscordSocial/`: independently adopted provider composition, scoped local
  observations and PCM controls; no upward dependency from existing products.
- `Sources/DiscordDSL/`: inert structural module composition and finite validated
  descriptions, explicit namespaces and validated typed dependencies over Core/Models
  only; no runtime, macro or concrete-adapter ownership.
- `Sources/DiscordCommandDSL/`: finite typed arguments and manual slash-command lowering
  over existing Commands/Interactions and HTTP/Transport; signed HTTP composition,
  explicit synchronization and no Gateway/client or concrete-adapter ownership.
- `Sources/DiscordBotDSL/`: inert typed event compilation, explicit bounded Gateway
  subscription/dispatcher composition, shared services, trusted interaction admission
  and supervised bot lifetime over the existing Client/CommandDSL owners.
- `Packages/DiscordDSLExtensions/`: independently selected public extension libraries
  and tests; no upward dependency from root runtime products.
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

For release tooling, audit or example changes, run the relevant Swift/Python tests,
the documentation presence audit, dependency/import graph audit, API comparison,
DocC and independent examples. Validate both machine release and maintenance records
with `release_check.py`; preserve append-only parity history and dated transition
fixtures. See `Docs/ReleaseTooling.md` for exact commands. Cross-platform workflow
definitions do not establish a passed run; update claims only from actual evidence.

For media/voice changes, also build and run the offline `Examples/VoiceBot` package.
Preserve its graph without HTTP/Gateway/Client/Cache/OAuth or concrete adapters.
Run published primitive vectors and malformed/tamper/replay/counter/queue tests.
For DAVE changes, keep the product independently adopted over Voice/MLS; do not add
upward dependencies from Voice/VoiceCrypto or HTTP/Gateway/Client/Cache/OAuth/Kit.
Test authenticated signaling, candidate selection/recovery, epoch/counter ownership,
bounded attempts/replay/expiry and codec-specific framing. Keep signing identity
shared across related sessions while recovery replaces HPKE/init keys. Complete
frames are transformed before RTP packetization and after depacketization.
The local encoded-packet round trip does not satisfy the full codec/MLS/DAVE,
device, authorized Discord or ten-minute duplex gates in `Docs/Voice.md`.

For C# code on macOS, use `msbuild` rather than `dotnet`.

For shared DSL changes, preserve the Core/Models-only graph and run root build/tests,
callable documentation, graph/import isolation and scoped API/DocC checks. Test structural
count/depth/text limits, duplicate identities, unsupported capabilities, deterministic
builder order and zero execution of injected work. Pure descriptions are authoring-layer
evidence; they do not qualify command/event execution, macros, live Discord or capacity.

For command DSL changes, preserve its DSL/Core/Models/Commands/Interactions/HTTP/Transport graph
without Gateway/Client/Cache or concrete adapters. Run root build/tests, callable
documentation, graph/import isolation and API/DocC checks; build `Examples/HTTPApp`
and the offline `Examples/CommandsApp`. Verify direct-versus-DSL definitions/routes,
strict option/resolved-resource decoding, fresh argument state per invocation,
compile-time zero execution and bounded cancellation-aware router ownership. Macro
compilation, broader command families, Gateway hosts and DSL capacity qualification
retain separate gates.

For macro authoring changes, run `swift test --package-path Packages/DiscordDSLMacros`,
`python3 Tools/ci/dsl_compile_fixtures.py` and its Python tests. Preserve the downstream
macro-package graph, Swift 6.4-compatible exact SwiftSyntax pin, generated callable
documentation and genuine external positive/negative compile fixtures. Text expansion
alone does not establish parity. Run documentation/graph audits and root build/tests;
manual response ownership and the remaining DSL milestones retain separate gates.

For response/HTTP command application changes, also build/test `Examples/DSLCommands`
and run its explicit offline mode. Preserve immediate/deferred/manual separation,
complete argument/envelope admission before acknowledgement, one initial response,
deferred completion through edit-original, expiry/uncertainty/cancellation behavior,
and rejection of competing application auto-defer. Construction and ordinary run must
make zero registration requests; explicit synchronization retains the existing managed
name policy and partial outcomes. The selected graph may use HTTP/Transport but must
exclude Gateway/Client/Cache, concrete adapters and compiler plugins from the runtime
product. Synthetic signed HTTP and trusted normalized contexts do not qualify live
Discord or a Gateway application host. Broader command families and 15F+ remain separate.

For message/component builder changes, preserve shared content's Core/Models-only
adoption, CommandDSL's existing dependency graph and command response ownership.
Run root build/tests, callable documentation, graph and API/DocC checks, plus
build/test/offline execution of `Examples/DSLCommands`.
Verify exact direct-model payload parity, safe untrusted interpolation even when a
typed allowlist contains the same ID, explicit raw/mention-policy opt-in, Unicode
boundaries, structural bounds, empty output, field omission/null/value and illegal
legacy/V2/component combinations. Keep existing payload validators authoritative;
local JSON parity does not prove Discord rendering, notification delivery or capacity.

For command-family changes, also run macro package tests and external compile fixtures,
plus the independent DSLCommands family examples. Cover exact namespaces, group depth,
focused partial autocomplete, typed context-menu targets, malformed modal/component
inputs, response compatibility and reconciliation no-op/change/partial outcomes.
Preserve explicit application/scope/name/type management, unmanaged commands and
no registration during construction or serving. Unknown upstream fields remain gaps.

For policy/middleware changes, verify named/operator parity, left-to-right short circuiting,
outer-left entry/reverse exit, finite node/depth and repeated application limits, malformed
input before policies, explicit rejection compatibility, shared admission overload and
cancellation cleanup. Test one terminal execution, retained continuation closure and error
translation without replay or fallback after partial side effects. Stateful keyed stores
must inject finite count/TTL bounds; the built-in authority retains only a fixed active count.

For Gateway event DSL changes, preserve existing shared/command product graphs and
the reviewed BotDSL host graph. Run root build/tests, callable documentation, graph/import
isolation, API/DocC and the independent DSLEvents offline consumer. Test declaration
order, complete-shard serialization/cross-shard progress, explicit required intents,
duplicate identities, raw/unknown/malformed dispatches, queue overflow, callback failure,
finite independent groups and cancellation/setup cleanup. Build GatewayBot and run
load cache/soak checks as required for event changes. Local tests do not qualify live
Discord or DSL handler capacity; Parts 15K-15L remain separate.

For bot application/interaction bridge changes, also build/test/run the independent
DSLBot consumer offline. Keep raw shard ingestion exclusive to DiscordClient and
authenticate Gateway interactions only at its package-internal ingestion boundary.
Test ordinary public-hub publication rejection, bounded trusted admission, exact
application identity, malformed/wrong-kind interactions, relative service timeouts,
HTTP callbacks and existing one-response/defer/expiry/uncertainty contracts. Exercise
subscribe-before-startup, cancellation before/during startup, stop-before-run,
repeated shutdown, cancelled cleanup waiters, handler-requested stop, child failure,
failed lease release and zero final owned counters. Inject and retain shared
credential/startup/lease/event/handler/REST/resource authorities across modules;
construction and ordinary execution must issue no command registration. Build the
affected independent command/event consumers and retain the cache/broadcast soak's
qualification limits. No concrete adapter, compiler plugin, voice, Social or OAuth
requirement belongs in BotDSL's runtime graph.

For external module/dependency changes, run the independent
`Packages/DiscordDSLExtensions` tests, root build/tests, callable documentation,
graph/import isolation, scoped API/DocC checks and affected DSLCommands/DSLBot
build/test/offline runs. Keep shared DSL Core/Models-only and command extension
adoption independent of Gateway/Client/Cache/concrete adapters. Test exact namespace
components and duplicate/empty/count/depth/text bounds, original metadata/source
preservation, dependency rejection before body creation, terminal swallowed failures
and zero construction/compilation execution. External compile fixtures must reject
missing/wrong typed dependencies. Reuse injected aggregate authorities and preserve
existing command/event route uniqueness and response/lifetime ownership. Local
extension tests do not qualify capacity, optional service support or live Discord.

For DSL benchmark changes, run the independent `Tools/DiscordDSLBenchmarks` Swift
and Python tests, release default paired matrix and compiler-cost matrix. Record
observations before deriving numerical budgets, then validate the complete report
against those budgets on matching hardware/toolchain/workload. Exercise finite
payload/concurrency/sample/invocation limits, cached schemas and zero cleanup
ownership. Preserve the separate cache/broadcast 30-minute soak and new DSL handler
soak evidence; report actual duration and measurement interference. Never infer
production/fleet capacity from synthetic declaration counts or local throughput.

For Social changes, build/run `Examples/SocialApp` offline, run the Social catalog
validator and Python tests, and preserve its graph without Gateway/Client/Cache,
Voice/MLS/DAVE or concrete adapters. Build affected provider examples and run the
Activity browser tests. User consent, bot authority, desktop/mobile hosts and local
media routes remain distinct; named unmet requirements never count as SDK support.

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
