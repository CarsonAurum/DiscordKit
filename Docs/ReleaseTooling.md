# Release certification tools

The Phase 14 tools are development-only Python standard-library programs. They
perform local, nonwriting checks unless an API snapshot output is explicitly
requested. Consumer packages do not run these scripts, fetch documentation or
regenerate source. A validated report establishes evidence traceability and
explicit exclusions; it does not grant platform, live Discord or crypto approval.

## Dependency and independent-product audit

```sh
python3 Tools/DiscordKitTools/scripts/release_check.py graph --repository .
```

This command evaluates the actual root, twelve independent example consumers and
the independent DSL benchmark manifest using `swift package dump-package`, with
temporary writable caches. Part 15D adds
the independent DSLCommands consumer, including its explicitly selected separate
macro product. Part 15H adds the macro-free DSLEvents event consumer. Part 15I adds
the macro-free DSLBot supervised offline host consumer. Part 15J adds the separate
`DiscordDSLExtensions` libraries, selected explicitly by DSLCommands and DSLBot.
The command-only product preserves its independent graph while the event product
explicitly selects BotDSL. It compares
the complete shipped target DAG, direct package requirements, product roots,
source roots and resolved Apple package identities/URLs against the reviewed
`Tools/DiscordKitTools/release-policy.json`. Every resolved pin needs a concrete
revision; package version updates still require normal dependency review.

Other consumers continue to select only the local runtime checkout. Extra local
authoring paths and external products require a per-consumer allowlist, exact
manifest version requirements and reviewed URLs. Their selected authoring runtime
closure participates in the same isolation audit; a macro package cannot hide a
forbidden runtime product from the consumer's graph.

The audit inspects actual Swift imports in every conditional compilation branch,
including scoped and escaped identifiers. It masks comments, nested string
interpolation, raw strings and regex literals. An imported module must be a
direct declared dependency or an explicitly allowed system module. The lexical
scan checks dependency boundaries rather than full Swift grammar. Compilation
remains required, and unfamiliar valid syntax can require a scanner update.

Root product closures and separately reviewed consumer product selections must
avoid their forbidden modules. Test support cannot enter a public product. This
checks the selected manifests and source boundaries in addition to compiling the
examples; an umbrella build alone does not satisfy isolation. The audit found
and corrected `DiscordHTTP`'s missing direct `DiscordCore` declaration: that
module was already imported and transitively linked, so no runtime dependency or
behavior was added.

## Source API baselines and semantic versions

```sh
swift package dump-symbol-graph --minimum-access-level public
python3 Tools/DiscordKitTools/scripts/api_baseline.py snapshot \
  --repository . --symbolgraphs .build/out/symbolgraph \
  --version 0.15.0 --output /tmp/discordkit-current-api.json
python3 Tools/DiscordKitTools/scripts/api_baseline.py check \
  --baseline Docs/Release/api-baseline.json \
  --candidate /tmp/discordkit-current-api.json --version 0.15.0
python3 Tools/DiscordKitTools/scripts/api_baseline.py check \
  --baseline Docs/Release/api-baseline-0.15.0.json \
  --candidate /tmp/discordkit-current-api.json --version 0.15.0
```

Use the symbolgraph directory printed by the installed SwiftPM toolchain if it
differs. Compile the graphs with the same target/deployment scope as the baseline.
The initial `0.14.0` baseline records 28 modules and 13,235 public/open symbols on
macOS arm64. It establishes a starting point; there is no earlier public baseline
against which to establish historical compatibility. This candidate is neither a
published release nor a tag. The current `0.15.0` candidate adds the independent
shared-declaration and typed-command products for Parts 15A/15B, plus the separately
compiled Part 15C macro authoring package. Part 15D adds typed response adapters
and signed HTTP command application composition with explicit synchronization.
Part 15E adds safe typed content interpolation in the shared DSL, plus pure
CommandDSL message/component builders and thin validated response adapters, preserving
the reviewed runtime dependency graphs. Part 15F adds command-family protocols,
finite exact-route catalogs and optional family macro authoring over the same graph.
Part 15G adds bounded policy/middleware composition, complete synchronous input
preparation before execution interception, injected authorization/concurrency and
explicit denial/error translation. Existing registration payloads and independent
product graphs remain unchanged. Part 15H adds the independent `DiscordBotDSL`
event product with explicit intent and finite subscription ownership. Part 15I
broadens only that selected product's graph with Client, CommandDSL and the existing
HTTP interaction owners for supervised bot lifetime, trusted Gateway callbacks and
shared typed service access. Existing products retain independent adoption and gain
no upward DSL dependency. Its public API and DocC join the current candidate.
Part 15J adds namespace-qualified structural identities and validated lazy typed
dependencies over the unchanged runtime graphs. The independent extension package
uses only public APIs for custom codecs, policies, typed/raw commands and event
modules; its public library products receive a separate API snapshot and DocC
conversion. Runtime products do not acquire the package. Part 15K adds an independent
[benchmark package](DSLBenchmarks.md), compiler-cost scripts and finite machine-specific
regression budgets. Hard functional checks run independently of timing comparisons.
Part 15L captures separately named root, macro and extension `0.15.0` baselines
after reviewing the Phase 15 API additions and the `0.14.0` comparison. It adds
current candidate evidence without replacing the frozen checkpoint reports.
The root runtime API is compared
against that frozen baseline with a pre-1.0 minor increment. The checker conservatively labels added enum cases
and protocol requirements as requiring a major increment (a minor increment before
1.0), including declarations in a new module; inspect the detailed comparison to
distinguish those additions from changes to existing APIs. The separately named
`api-baseline-0.15.0.json` now fixes the reviewed Phase 15 root API. CI compares
fresh compiler output to both versions: the `0.14.0` comparison describes the
migration, while the same-version `0.15.0` comparison rejects added, removed or
changed APIs until a new version and baseline receive review. Never rewrite a
historical baseline to make a new API pass.

The macro authoring declarations receive a separate snapshot, including Part 15F's
context-menu macros; the compiler plugin and its tests do not become runtime API modules:

```sh
swift package --package-path Packages/DiscordDSLMacros dump-symbol-graph --minimum-access-level public
python3 Tools/DiscordKitTools/scripts/api_baseline.py snapshot \
  --repository . --authoring-package Packages/DiscordDSLMacros \
  --symbolgraphs Packages/DiscordDSLMacros/.build/out/symbolgraph \
  --version 0.15.0 --output /tmp/discordkit-current-macros-api.json
python3 Tools/DiscordKitTools/scripts/api_baseline.py check \
  --baseline Docs/Release/api-baseline-macros-0.15.0.json \
  --candidate /tmp/discordkit-current-macros-api.json --version 0.15.0
```

The macro package receives its own DocC conversion and curated reference pages.
Its reviewed `api-baseline-macros-0.15.0.json` contains only the authoring product,
independently from the runtime API. This first macro baseline establishes no
earlier historical compatibility. Compiled external fixtures
check the actual macro signatures and generated behavior on the recorded toolchain.

Part 15J uses the same separate-package snapshot mechanism for public extension
libraries, without compiler plugins or SwiftSyntax in that package:

```sh
swift package --package-path Packages/DiscordDSLExtensions dump-symbol-graph --minimum-access-level public
python3 Tools/DiscordKitTools/scripts/api_baseline.py snapshot \
  --repository . --authoring-package Packages/DiscordDSLExtensions \
  --symbolgraphs Packages/DiscordDSLExtensions/.build/out/symbolgraph \
  --version 0.15.0 --output /tmp/discordkit-current-extensions-api.json
python3 Tools/DiscordKitTools/scripts/api_baseline.py check \
  --baseline Docs/Release/api-baseline-extensions-0.15.0.json \
  --candidate /tmp/discordkit-current-extensions-api.json --version 0.15.0
```

Build/test the package independently and run
`python3 Tools/ci/dsl_extension_fixtures.py --repository .` for genuine external
positive and missing/wrong dependency compile checks. Collect its two library
products' curated DocC with the same separate-repository commands used for the
macro package. `api-baseline-extensions-0.15.0.json` fixes their separately reviewed
public API; this first extension baseline establishes no earlier historical
extension compatibility.

Snapshots normalize all owned graph shards, including external-type extensions,
and reject missing modules, conflicting duplicates and mixed platform scopes.
They retain declaration/type/default spelling, access, generic/extension
constraints, availability and relationship qualifiers. Source locations and
documentation do not affect signatures. Each symbol and relationship occupies a
compact JSON line so changes can be reviewed without enormous one-line diffs.

Removal, signature/constraint/availability changes, relationship removal, new
required protocol members and enum cases conservatively require a major version
increment. Before `1.0.0`, these require a minor increment. Other source additions
require a minor increment. Identical APIs permit a patch increment or the same
version for candidate revalidation. Stable three-component versions are accepted;
prerelease/build-metadata version policy is deliberately outside this checker.

The comparison cannot prove behavioral or binary compatibility. Compiler/SDK
updates may change synthesized declarations and require review. API changes on
other operating systems, architectures and conditional compilation branches
require separate compiler-produced baselines; the macOS snapshot does not
qualify those surfaces. Local API migration and upstream protocol changes are
tracked separately in release and parity history.
The Phase 15 baselines were emitted locally with Apple Swift 6.4, while hosted
CI requests Swift 6.4.1. Actual hosted comparison results are required before
claiming identical compiler output; a local pass is not evidence of a hosted run.

## Machine-readable report and explicit exclusions

```sh
python3 Tools/DiscordKitTools/scripts/release_check.py report --repository . \
  --report Docs/Release/phase15l-report.json
```

The current report covers shared declarations, typed argument decoding, command
lowering, separate macro authoring, response ownership, signed HTTP composition,
event modules, supervised bot lifetime, trusted Gateway interaction composition,
external namespace installation, validated typed dependency adoption, local
benchmark/soak evidence, reviewed API baselines and release/adoption documentation.
It includes only checks actually recorded for the current checkpoint. The macro
package is audited separately from the root runtime API graphs;
its public macro signatures are checked through compiled external consumers. Validate the
historical `phase14-report.json` and `phase15-report.json` separately; their frozen
evidence describes those checkpoints rather than the current release candidate.
No passing record implies that excluded external qualification gates completed,
or that a release was published or tagged.

The schema-1 report identifies the candidate semantic version, verification date,
explicit REST/Gateway/Voice/RPC/MLS/DAVE versions, every required gate, and the
claims supported by passed gates. Each evidence object has a repository-relative
`path` and exact lowercase SHA-256. Missing files, changed bytes, duplicate JSON
keys, path traversal and escaped symlinks reject validation.

A gate is `passed` only with scoped evidence. An unavailable gate is `unverified`
with a reason and `excludedClaims` containing its own canonical gate ID. Every
support claim names passed `checkIDs`; it cannot name an excluded claim or depend
on an unavailable gate. `globalExclusions` also prohibits its named scopes from
appearing as claims, even when a proposed claim references passed local gates.
Missing/unknown gates and `failed` status reject the
record. Failed checks must be corrected or accurately recorded as unverified and
excluded; changing a status never turns failure evidence into a successful check.
All-unverified records may describe no support claims, consistent with the
roadmap's explicit-exclusion rule. Hashes prove exact local evidence membership,
not that a process ran, its semantic accuracy or an independent attestation.

## Weekly upstream review, history and dated transitions

```sh
python3 Tools/DiscordKitTools/scripts/release_check.py maintenance --repository . \
  --record Docs/Release/maintenance.json
```

The review must be current, with its next deadline no more than seven days after
the recorded review date. No unclassified upstream entries may remain. Official
source rows bind the exact local review evidence; compact source metadata can
retain the hash of fetched upstream bytes without redistributing full documents.
The read-only maintenance workflow fetches upstream material separately and
publishes differences for human review. These audits never auto-apply upstream
changes to production source or claim full semantic review from a source hash.

The policy freezes the exact canonical hashes and order of pre-Phase-14 history
entries. New entries may be appended; historical edits/removals fail validation.
This does not replace reviewing new history entries for complete source/date,
symbol/payload, migration and release provenance.

The mandatory `channel-obfuscation-http` fixture records the announced
`2026-11-16` HTTP transition. At least the preceding day and exact effective day
must be present, with current/effective classifications computed from dates.
Future-effective behavior remains explicitly separate from currently active
behavior. The fixture is hash-bound, source-linked and exercised by Swift HTTP
regression tests. Use `--as-of YYYY-MM-DD` only to reproduce a historical review;
it must never substitute for a fresh review before a new release.

## Tests

```sh
python3 -m unittest discover -s Tools/DiscordKitTools/scripts -p 'test_*.py'
```

Deterministic tests cover isolated and forbidden imports, lexing edge cases,
manifest cycles, changed package/product boundaries, consumer graph selection,
exact evidence/path safety, missing/failed gates, prohibited claims, weekly
freshness, append-only history, transition dates, graph shards and conservative
source semver. Root Swift, tooling, generation, parity, DocC, examples, browser,
load and externally qualified platform checks remain separate release gates.
