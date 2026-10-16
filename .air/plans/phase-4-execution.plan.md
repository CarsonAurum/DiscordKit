# Phase 4 execution plan

Date: 2026-10-16. Scope: Part 4, reviewed inventory tooling and schema generation,
in the master roadmap. The starting working tree is clean at `dc11cf8`.

1. Inspect the existing discovery inventory, validator, partial User/Application
   models and typed HTTP/Gateway discovery descriptors. Verify official contracts
   and preserve the existing Swift 6.4 concurrency and product boundaries.
2. Introduce a versioned reviewed-definition schema with stable, checked links to
   pinned upstream discovery, symbols and test/fixture evidence. Keep upstream
   dates separate from local implementation dates and classify each modeled field.
3. Review the existing runtime slice into those definitions, recording optionality,
   nullability, defaults, constraints, access and unknown-value behavior. Preserve
   partial support and handwritten rate, ownership and response-lifecycle policy.
4. Generate repetitive models/codecs and endpoint descriptors, reviewed documentation,
   fixture-case indexes and parity report sections deterministically and offline.
   Consumer builds only compile committed output. Explicit generation is a developer
   command; check/validation commands never write files or fetch upstream content.
5. Add nonwriting inventory, generation and parity checks for duplicate/unclassified
   IDs, unresolved links, incomplete auth/request/response/status contracts, stale
   verification, orphan symbols, nonexistent tests/fixtures and output drift.
6. Cover generator and semantic-validation branches with deterministic Swift Testing,
   including negative mutation tests for an unclassified field and missing evidence.
   Test the generated runtime projections through their observable public behavior.
7. Update documentation, chronological parity/history and repository guidance. Derive
   current parity counts from validated records; keep historical baseline counts dated.
8. Run root build/test, independent tooling Swift/Python tests, inventory validation,
   generation check, parity check, REST-only example build and affected local HTTP
   scenarios. Review the complete diff and stage all scoped work.
9. Prepare the commit message from the verified staged snapshot. Do not create a commit.

No new resource catalog coverage, broad platform qualification or capacity claim is
part of this phase. Existing external gates and unsupported discovery records remain
visible. The generator supplies repetitive structure; handwritten semantics and review
remain necessary for every future integration.

## Execution results

Implemented the reviewed schema and 43 classified contracts linked to the existing
discovery inventory, pinned official written/preview sources, 42 declarations and
named evidence. The schema supports explicit handwritten event/payload/variant
relationships without adding a supported Discord event. Current User/Application
projections remain partial; Gateway discovery remains handwritten. Preview source
cross-check metadata is unsupported, preserving independent implementation counts.

Five deterministic artifacts contain the existing response projections, typed HTTP
descriptors, reviewed documentation, parity records and the 128-case field index.
The generator additionally compiles and executes synthetic Codable request/response
templates in its tests. Consumer builds use committed output without a generator,
network fetch or new dependency. Handwritten runtime policy and exact JSON parsing
remain independent of the tool package.

Final verification passed on 2026-10-16:

- Root `swift build` and `swift test`: 300 test methods across 12 test bundles.
- Tool package: 87 Swift Testing methods in six suites, including compiled Codable
  templates, exhaustive field classification, stale/missing evidence, source pins,
  event references, deterministic bytes and nonwriting modification-time checks.
- Inventory validation, generation check and parity check: 18,137 discovery records,
  280 sources, 43 reviewed definitions and three existing implemented endpoint maps;
  all five generated artifacts byte-identical.
- Independent REST-only example build, without authenticated calls.
- Tool discovery Python tests: 10 passed. Load Swift tests: 18 passed; load Python
  tests: eight passed with approved local-loopback access.
- Offline HTTP accounts-100 normal/burst smoke runs: zero failed requests, all
  configured latency/RSS/resource checks passed and zero retained work after shutdown.
- CLI usage and failure exit statuses, changed JSON syntax, relative Markdown links
  and complete diff whitespace checks passed.

The managed environment required a temporary Clang module cache and Swift's
`--disable-sandbox`; adapter/peer tests used approved host loopback access. The
initial default-cache and sandbox socket failures were environmental and were
resolved before successful reruns. Measurements here are regression smoke checks,
not refreshed release baselines or a new capacity qualification.

The final scoped changes are reviewed and staged. No commit is created; the commit
message is prepared from the verified staged snapshot.
