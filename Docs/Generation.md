# Reviewed definitions and offline generation

Part 4 adds development tooling around the existing API v10 User/Application
projection and HTTP descriptors. It does not expand the REST catalog. Gateway
discovery and runtime policies remain handwritten. All generator inputs and outputs
are committed; consumer builds neither fetch documentation nor run generation.

## Records and review

The broad [discovery inventory](Parity/inventory-v1.json) retains individually
classified definitions, including unsupported and unreviewed entries. The smaller
[reviewed inventory](Parity/reviewed-v1.json), described by its
[versioned schema](Parity/reviewed.schema.json), is the generation authority.
Its stable IDs link model fields, enum variants, endpoints, source pins, source
declarations and specific test or fixture evidence. Handwritten event contracts can
also link to payload models and variants; this phase seeds no supported Discord event.
It keeps upstream announcement
and effective dates separate from local support dates. Unknown upstream dates stay
`unknown`; a local implementation date cannot establish an upstream introduction.

Each reviewed field explicitly records wire and Swift names, value type,
optionality, nullability, default behavior, range/counting constraints, access and
unknown-value handling. Models list their typed fields and known omitted upstream
fields. Partial projections stay partial even when all generated declarations
compile. Endpoint records classify authentication, request and response models,
success and error statuses, rate policy, retry semantics and pagination.

Phases 5A–5F also record handwritten semantic models through optional `manual.fields`
contracts. They carry the same field-level presence, nullability, default, constraint,
access and unknown-value decisions, each linked to an actual discovery field and Swift
declaration. The validator rejects empty or duplicate field lists, unsafe metadata,
and links outside the parent's source, upstream IDs or symbols. These contracts audit
the recursive Message/Poll/component, Channel/Invite, Guild, moderation, expression
and discovery/event payloads
without asking the finite seed generator to emit unsupported Swift shapes. Adding
them changes the reviewed reports; it never generates or replaces their handwritten
runtime declarations. See [REST catalog](RESTCatalog.md),
[Channel catalog](Channels.md), [Guild catalog](Guilds.md), [moderation catalog](Moderation.md),
[expression catalog](Expressions.md) and [discovery/event catalog](DiscoveryEvents.md)
for the implemented operations and explicitly partial related-resource projections.

Source pins refer to exact revision/hash pairs in the existing official source
catalog. Written Discord documentation takes precedence over the pinned preview
specification. Neither a pin nor a successful structural check resolves an upstream
ambiguity. Review changes against the current official reference and change log,
then update the source evidence, contracts, tests and chronological history together.

## Commands

Run from the repository root with Swift 6.4 or newer:

```sh
swift test --package-path Tools/DiscordKitTools
swift run --package-path Tools/DiscordKitTools DiscordKitTools inventory validate --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools generate --check --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools parity check --repository .
python3 -m unittest discover -s Tools/DiscordKitTools/scripts -p 'test_*.py'
```

These checks are offline and nonwriting. They reject duplicate or unclassified
definitions, unresolved references, incomplete wire contracts, changed source pins,
stale verification, orphan symbols and nonexistent declaration/test/fixture evidence.
Generation checks compare complete UTF-8 output bytes, including whitespace and
documentation. A changed or missing output makes the check fail without repairing it.
Unknown schema metadata keys fail rather than silently disappearing during decoding.

Audits default to the current UTC day. Use `--as-of YYYY-MM-DD` to reproduce a
historical review within its declared freshness window. Passing a historical check
does not establish current API currency. Update and reverify stale source contracts
instead of merely extending their allowed age or changing their verification date.

After reviewing input changes, regenerate explicitly:

```sh
swift run --package-path Tools/DiscordKitTools DiscordKitTools generate --write --repository .
swift run --package-path Tools/DiscordKitTools DiscordKitTools generate --check --repository .
```

The writer is restricted to the generator's output allowlist and refuses symlink
destinations. Review its diff and run the root `swift build` and `swift test` before
staging. There is no SwiftPM build plugin, consumer network dependency or automatic
regeneration. Documentation and dependency-audit commands from later roadmap work
remain unsupported and return usage status 64.

## Generated structure and handwritten semantics

The reviewed output includes repetitive model/codecs, typed HTTP descriptors,
documentation and fixture-case/parity indexes. Handwritten code continues to own
bounded lossless JSON parsing, exact numeric validation, credential isolation,
rate admission, permission algorithms, retry decisions and Gateway/response
lifecycle. Generated model methods use the same bounded projection helpers as
before. Required nullable values remain distinct from missing optional fields,
and unknown payload fields retain exact JSON numeric spelling.

Generated documentation is an initial structure filled by reviewed definition
text; it needs the same semantic review as handwritten documentation. A fixture
index records evidence relationships, not a test execution result. Source-line and
test-name checks establish that named artifacts exist, not that they prove the
claimed behavior. Passing root tests and reviewing those assertions remain required.

The nonwriting parity command derives kind/status counts from validated discovery
and reviewed records and checks the existing implemented endpoint mappings. Discovery
representations from written references and preview specifications remain distinct;
their counts are not unique operations or an API parity percentage. See the
[generated reviewed report](Parity/generated-reviewed.md) and
[reviewed API documentation](Generated/ReviewedAPI.md).
