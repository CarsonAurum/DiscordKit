# Phase 5B execution

Date: 2026-10-16. Source: the master roadmap's independent Channel work package.
The committed 5A baseline bb93fd9 was clean and passed root build and all 392
strict macOS tests before implementation. Local socket validation used approved
host access after sandbox bind restrictions. Existing non-macOS/device/live/soak
qualification gates remain separate; no blocking 5A implementation issue was found.

1. Verify current official Channel, Invite, Guild active-thread, API version and
   change-log contracts; retain current hashes separately from discovery pins.
2. Implement complete channel-owned response fields/variants, type-aware request
   validation and every documented channel route plus active guild threads.
3. Reuse bounded forum upload ownership, add correct recipient authorization and
   invite CSV framing, preserve unknown/redacted state and nullable application IDs.
4. Add lazy finite membership/archive continuation, exact cursor units, complete
   member correlation and explicit no-op settings reconciliation.
5. Add deterministic model/request/endpoint/execution/workflow tests; update
   reviewed inventory, chronological parity and adoption/qualification documentation.
6. Explicitly regenerate, review output, run root/example/tooling/load checks,
   inspect the complete diff and stage the intended changes without committing.

## Final validation

The final source candidate passed `swift build` and `SWIFTNIO_STRICT=1 swift test`
on macOS: **459 methods, 52 suites, 12 bundles** (392 methods before Phase 5B).
The strict run includes the CSV framing/byte-limit regression and all endpoint,
model, request, pagination, cancellation, upload ownership and scoped reuse tests.
Every new method/test has Swift documentation; related resource-family projections
remain explicitly partial. No production dependencies or package settings changed.

The independent RESTOnly consumer built without authenticated calls.
DiscordKitTools passed **93 tests / 7 suites**, its Python discovery tests passed
**10**, and inventory validation, explicit `generate --write`, byte-identical
`generate --check` (five artifacts) and `parity check` passed. The inventory retains
18,137 discovery records / 280 sources, with 189 reviewed definitions and 47 mapped
implemented endpoints. Counts describe distinct discovery/review records, not a
full-platform parity percentage. Regeneration changed documentation reports only;
generated Swift remained unchanged.

The separate load harness passed **18 Swift tests / 3 suites** and **8 Python peer
tests**. Release build and six serial offline HTTP policy profiles passed; all
normal profiles had zero refusals, all runs met sampled resource/RSS budgets, and
all post-shutdown active/queued/coalesced/cache owner counts were zero. Burst
refusals are expected bounded admission outcomes. These profiles exercise the shared
HTTP pipeline with synthetic logical served-user dimensions, 2/4/16 actual credential
partitions and no sockets, Discord credentials or requests. They do not qualify
Discord quota throughput, fleet fairness, simultaneous user connections or soak.

| Logical accounts | Mode | Successes | Refusals | Avoided exchanges | Successful p99 ms | Peak RSS MiB |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |

| 100 | normal | 2,000 | 0 | 1,153 | 9.920 | 9.97 |
| 100 | burst | 1,207 | 793 | 1,085 | 35.704 | 12.61 |
| 10,000 | normal | 10,000 | 0 | 5,890 | 10.632 | 11.80 |
| 10,000 | burst | 6,714 | 3,286 | 5,829 | 65.253 | 14.62 |
| 1,000,000 | normal | 20,000 | 0 | 11,984 | 4.726 | 13.48 |
| 1,000,000 | burst | 14,240 | 5,760 | 11,870 | 92.432 | 17.95 |

Sandbox restrictions required isolated writable Swift caches, `--disable-sandbox`,
approved host access for loopback tests and macOS release symbol generation, and
read-only hardware metadata for the recorder. Those checks passed with host access;
no product error remains from the restricted attempts. Existing platform/device,
live API and long-soak qualification gates remain open as documented in PlatformSupport.

Current official reference/change-log verification and pinned spec supplements are
recorded in the Channel source hashes and chronological history. Concrete
written/spec response discrepancies have explicit compatibility decisions in the
ambiguity register. The original discovery pins and previous review/history entries
are preserved. Complete diff, whitespace, documentation links and intended staged
content were reviewed; changes are staged without creating a commit.
