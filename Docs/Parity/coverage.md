# Part 0 coverage and completion gates

Current Phase 7 consumer/cache/event delivery is recorded in the
[client guide](../Client.md) and [execution record](../../.air/plans/phase-7-execution.plan.md).
The historical counts and qualification gates below retain their original scope;
local composition/permission calculation adds no new endpoint/dispatch-name records.

Verified **2026-10-15**, on macOS arm64 with Swift **6.4**. This is a discovery and
feasibility baseline. **The complete Part 0 gate is still open**: other-host runtime
qualification, full semantic inventory review and missing upstream contracts cannot
be established by local tests. No Discord integration or full API parity is claimed.

## Discovery baseline

The committed inventory has **18,137 records from 280 source groups**, with
**zero unclassified discovered IDs**, **zero implemented support records**, and
**18,137 records pending semantic review**. Repeated documentation/specification
representations and reference sections are included; these are not counts of unique
Discord operations. Every record is independently addressable and linked to pinned
source membership, provenance, explicit status and an access/protocol condition.

| Discovered kind | Records |
|---|---:|
| Pages, sections and unrecognized table rows | 4,759 |
| Endpoint definitions/examples | 776 |
| Named model/callback definitions | 1,147 |
| Fields/static values | 8,412 |
| Enum values | 1,732 |
| Events | 347 |
| SDK methods/commands | 772 |
| Permissions / intents | 52 / 24 |
| Opcodes / close codes | 42 / 45 |
| Protocol-state sections | 29 |

Discovery includes all 204 official MDX source files at the pinned documentation
revision, the documentation index, both official preview specification files, and
SDK source groups with method/definition membership. The separate contract map has
**718 method/event/capability rows** and **302 enum/callback/static definitions**;
**89 distinct missing-contract blockers** are retained. It classifies local work,
public wire candidates and unproven equivalents separately. Neither mapping a
candidate nor extracting a schema changes implementation status.

## Executed checks

| Check | Result and practical limit |
|---|---|
| `swift build` | Passed for the existing runtime and explicit nonisolated default. No production dependencies added. |
| `swift test` | Passed, 1 existing empty scaffold. This does not establish Discord behavior coverage. |
| `swift test --package-path Tools/DiscordKitTools` | Passed, 35 Swift Testing test methods / 300 parameterized executions. Covers classification vocabularies, real dates, malformed/missing/null/wrong JSON, source metadata, duplicate and lost/wrong-source IDs, evidence and whitespace regressions. |
| Python standard-library extraction tests | Passed, 10 tests. Covers nested/inline schemas, large integers, routes, guide-only templates, unversioned OAuth URLs, independent protocol versions, permissions/intents/events, code-fence handling, SDK overloads/enum metadata and deterministic output. |
| `inventory validate --repository .` | Passed: exact source discovery membership and metadata; no network or source mutation. Does not authenticate upstream bytes or perform general JSON Schema validation. |
| Snapshot acquisition verification | All 204 MDX files matched Git blob hashes in the pinned, nontruncated official Git tree. Source SHA-256 values retained. |
| Inventory reproduction | Repeated harvesting from those snapshots and the committed SDK map produces byte-identical catalogs. |
| Platform fixture | Passed, 3 Swift Testing test methods / 7 cases: actual local HTTP, fully verified TLS, trust/hostname rejection, WebSocket upgrade/frame and empty/binary UDP. IPv4 loopback on macOS arm64 only. |
| Voice fixture | Passed, 5 Swift Testing test methods / 10 cases: AES-GCM/ChaCha roundtrip and authentication failure, truncated-tag/nonce rejection, AES block known answer, exact HPKE primitive suite. No DAVE or MLS implementation/interoperability claim. |
| Diff/link review | Whitespace, local Markdown links, JSON syntax and generated/cache exclusion reviewed. |

In the managed workspace, normal Swift compiler caches and sandbox DNS were
unavailable. Successful dependency acquisition and Swift checks used approved host
access. Those initial environment failures are not compatibility or test failures.

## Roadmap completion gates

| Part 0 requirement | State | Evidence or remaining work |
|---|---|---|
| Adopt graph, dependencies, API and concurrency conventions | Recorded | Architecture, concurrency and dependency policy; Swift 6.4/ApproachableConcurrency preserved, explicit `.defaultIsolation(nil)` in each implemented package target. |
| Versioned discovery inventory and change history | Implemented locally | Schema/catalog, 18,137 classified records, source membership validator, append-only history and dated baseline. Definition extraction remains a discovery aid, with pending semantic review explicit. |
| Every discovered ID classified | Structural check passed | All discovered entries are unsupported, with an explicit condition. This does not prove every upstream prose-only contract was discovered or reviewed. |
| Exact schema/access/platform metadata per operation | Open semantic gate | Review each source contract before implementing; generic source prerequisites do not establish individual auth/scopes/permissions. Resolve retained table rows and arbitrary prose or new markup forms. |
| Ambiguity register and protocol blockers | Recorded | Identity Profile response, RPC/device port discrepancy, preview precedence, source-only Activity variants, SDK contracts and commerce access/schema gaps. |
| Every target platform explicitly classified | Recorded | Capability matrix covers macOS, Linux, Windows, iOS, tvOS, watchOS, visionOS, Android, WASI, browser, Embedded and experimental ports. |
| Qualify exact native graph across requested hosts | Open external gate | macOS local transport probe passed; Linux, Windows, Android and Apple-device/minimum-OS runs are not available here. Do not freeze adapter choices or introduce a fallback without this evidence. |
| Verify public voice primitives and isolate owned work | Primitive feasibility recorded | Exact Crypto/CryptoExtras probe, XChaCha/HChaCha and truncated-tag gaps, MLS/DAVE/codecs still require owned implementations and conformance vectors. |
| Map every discovered Social/Activity/Commerce operation | Discovery mapping recorded | Method-level source anchors/hashes, public/local/missing-contract categories, prerequisites and concrete required evidence. Source-only and unproven equivalents remain blockers. |
| Entire-platform implementation feasibility resolved | Open upstream gate | Public wire schemas/access/host evidence are still missing for named operations. No native SDK/runtime wrapper or invented private protocol is permitted. |

The next implementation part may build portable values independently. Full Part 0
qualification remains tracked here; passing this repository's tests cannot close
unavailable-host or missing-upstream-contract gates.

## Subsequent transport implementation

Part 2's 2026-10-15 [transport record](changes/2026-10-15-transports.md) adds owned
network adapters and local macOS evidence. It does not change discovery inventory
operation statuses, close the historical semantic-review gate, or qualify unavailable
hosts. Current adapter behavior, limits and outstanding platform gates are recorded
in [Transport](../Transport.md); the Part 0 results above remain historical.

## Part 3 HTTP and early Gateway update (2026-10-16)

The historical counts above describe the Part 0 baseline. Current inventory keeps
all18,137 discovered IDs, with three reviewed written-reference endpoint records:
one supported Gateway discovery and two partial User/Application projections.
Duplicates from preview specifications remain unsupported pending their independent
semantic review; these are not unique-operation or full-platform parity counts.

The root HTTP, read-reuse, model, rate-coordination and Gateway suites cover the
initial runtime slice with virtual time and scripted peers. WebSocket loopback suites
exercise real Foundation/NIO session-aware reconnect and peer codes. The REST-only
example is independently built without running authenticated operations. See
[HTTP policies](../HTTP.md), [Gateway contracts](../Gateway.md), and the
[local load harness](../../Tools/DiscordKitLoadTests/README.md) for numeric budgets
and measured limits. Full event/resource models, durable external coordinators,
other-host sessions and sustained-capacity certification remain open gates.

## Part 4 reviewed generation update (2026-10-16)

The [reviewed inventory](reviewed-v1.json) adds a finite semantic generation seed
without promoting unsupported discovery records. Current reviewed counts derive
from the [generated report](generated-reviewed.md); the nonwriting `parity check`
command derives both discovery and reviewed kind/status counts after validation.
The Part 0 numbers above remain historical, not manually maintained current totals.

The tooling suites cover source pinning, verification-age boundaries, per-field
contracts, reciprocal references, missing/unclassified records, orphan declarations,
real test/fixture evidence, symlink containment, deterministic rendering, output drift
and explicit regeneration. Generated runtime projections retain bounded JSON and
presence semantics and are tested through the root model/HTTP suites. Evidence-name
existence and passing generation do not replace semantic assertion review.

Consumer builds compile committed output without fetching or generating. Full
catalog parity, unavailable-host qualification and sustained-capacity gates remain
open. See the [dated tooling history](changes/2026-10-16-reviewed-generation.md) and
[generation guide](../Generation.md) for contracts and reproducible commands.

Local verification passed: root build and 300 Swift test methods; 87 tool test
methods (including compiled Codable request/response templates); 10 discovery
Python tests; REST-only example build; 18 load Swift tests and eight load Python
tests. Offline HTTP normal/burst smoke runs met configured resource/latency/RSS
checks and retained no owned work after shutdown. These checks did not use Discord
credentials or live Discord requests. Inventory validation, byte-identical generation
and parity checks passed for the committed records; JSON syntax, relative links and
the complete diff were reviewed.

## Part 5G application/user update (2026-10-16)

The [application/user catalog](../ApplicationsUsers.md) adds all 32 available
written-reference operations and explicitly classifies disabled batch command
permission editing as removed. Existing partial generated User/Application seeds
move to handwritten bounded models; their scalar regression fixtures remain active
and the independent generator seed preserves positive template coverage. Current
source hashes, field/variant declarations, executable test anchors and chronology
are linked in the reviewed records. This does not change historical Part 0 counts
or establish event, live API, fleet, unavailable-platform or capacity qualification.

## Part 5H webhook, interaction-response and voice update (2026-10-16)

The [webhook, interaction-response and voice catalog](../WebhooksInteractionsVoice.md)
adds all 28 current written REST operations: 15 webhook, eight interaction-response
and five voice operations. Reviewed evidence covers owned fields, unknown variants,
validated payloads, explicit callback/compatibility response shapes, exact typed
path-token binding, shared IP-global webhook admission and interaction exemptions.
The legacy premium-required callback remains deprecated. Current source fingerprints
and explicit written/preview ambiguity decisions accompany the chronological record;
historical discovery pins and prior support records remain unchanged.

Deterministic tests cover descriptors, decoding, validation, credential/reuse
boundaries, uploads, retries, cancellation, permission/authentication errors and
global admission/cleanup. Related resource projections remain explicitly partial.
The [execution record](../../.air/plans/phase-5h-execution.plan.md) records complete
validation and local HTTP measurements. These short synthetic macOS measurements
do not establish served-user, live Discord, fleet, device or sustained capacity.
Interaction ingress/signatures/routing and voice media/device ownership remain
separate roadmap work; batches 5I–5J remain pending.

## Part 5I monetization update (2026-10-16)

The [monetization catalog](../Monetization.md) adds all eight current written REST
operations, owned SKU/Entitlement/Subscription fields and named variants, typed
premium interaction entitlements, owner-safe test requests and finite lazy traversal.
Current official source fingerprints, corrected numeric status chronology, explicit
written/specification precedence and private-scope/Commerce boundaries accompany
the [dated record](changes/2026-10-16-monetization.md). Historical discovery pins
and earlier support records remain intact; counts do not imply unique operations.

Deterministic tests cover malformed/null/missing/future fields and bounds, exact
requests and responses, OAuth/bot category enforcement, rate/transport/API errors,
read reduction/invalidation, cancellation/deadlines and bounded cursor/resource
validation. The [execution record](../../.air/plans/phase-5i-execution.plan.md) records
validation and local measurements. No live Discord, private OAuth eligibility,
Social Commerce checkout/fulfillment, event dispatch, other-host/device, distributed
storage or sustained capacity qualification follows from these scripted tests.
Batch 5J and later event/catalog/platform gates remain open.

## Part 5J social/game backend update (2026-10-16)

The [lobby and identity/profile catalog](../SocialGame.md) adds all 21 written
operations, including the distinct link/unlink contracts sharing one route. Owned
fields, additional-name snapshots, bot/Bearer separation, targeted invites,
moderation metadata and full-replacement statistics are explicit. Bounded sequential
member bulk plans retain correlation, silent upsert omissions and completed progress;
caller-snapshot reconciliation avoids unchanged writes without hidden reads.

The [dated record](changes/2026-10-16-social-game.md) records current source hashes,
chronology and written/specification precedence. The
[execution record](../../.air/plans/phase-5j-execution.plan.md) records final checks.
This completes the named 5A–5J written REST batches under their documented
compatibility limits; it does not establish complete Discord parity, every
referenced family projection, native Social SDK/OAuth flows, event dispatch,
production eligibility, live Discord, other-host/device, distributed or soak qualification.

## Part 6 Gateway catalog and requests update (2026-10-16)

The [Gateway contract](../Gateway.md) adds typed recognition of all 79 documented
opcode-zero dispatch names, all 13 documented Gateway opcode values, 21 intents,
Identify capabilities and presence/voice/member/soundboard/channel-info commands.
Named dispatch coverage is distinct from complete child-resource projection:
reviewed event definitions retain partial status where related fields are not fully
typed, and all exact raw payloads and unknown event names remain available.

Member requests assemble nonce-correlated chunks with bounded partial progress.
Soundboard/channel-info responses have no upstream nonce and use exclusive
per-guild/family ownership; failed/direct-send keys cannot be reused in a generation,
while successful-key reuse has an explicit duplicate-response ambiguity. Cancellation,
disconnect, deadlines, overflow and opcode-specific rate limits have explicit
outcomes, independent of REST scheduling. No hidden request replay or cache follows.

The [dated record](changes/2026-10-16-gateway-catalog.md) records official chronology,
source fingerprints and compatibility. The [execution record](../../.air/plans/phase-6-execution.plan.md)
records integrated validation. JSON/uncompressed transport remains the explicit
protocol choice; live Discord, other hosts/devices, distributed storage adapters
and sustained-capacity qualification remain separate gates.

## Part 8 signed ingress and interaction runtime (2026-10-17)

Independent Interactions/Commands products add exact raw-body Ed25519 verification,
bounded replay/admission, HTTP/Gateway contexts, reserved initial acknowledgements,
explicit defer/expiry/uncertainty, bounded routing and canonical change-only command
synchronization. Identical managed definitions send zero writes; unmanaged commands
and omitted settings are preserved. The HTTPApp graph has no Gateway/Client/Cache.

Webhook events recognize twelve current names, with typed authorization/entitlement
and explicitly partial social-message children/quest schema. Empty HTTP 204 follows PING
or durable admission; failed/uncertain admission gets retryable HTTP 503. Exact-byte local
deduplication is advisory. Display-only component embeds and partial common Open
Graph helpers never enter interaction routing. Six reviewed contracts link sixty-two
newly reviewed discovery records to actual declarations and deterministic tests.

See [contracts](../Interactions.md), [dated record](changes/2026-10-17-interaction-runtime.md)
and [execution evidence](../../.air/plans/phase-8-execution.plan.md). Current source
hashes are separate from unchanged historical pins. Live Discord/rendering, durable
fleet authorities, other-host/device and sustained capacity remain open gates.
