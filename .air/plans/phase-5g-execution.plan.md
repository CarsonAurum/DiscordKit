# Phase 5G execution

Date: 2026-10-16. Source: the master roadmap's independent application/user batch.

The clean committed 5F baseline 9542e90 passed the root build and all **731 strict
test methods in 84 suites across 12 bundles** on macOS arm64 / Apple Swift 6.4.
Existing unavailable-platform/device, live API, durable coordination and soak gates
remain separate from this independent REST catalog work package.

1. Verify current written Application, Team, User, linked-role metadata and
   Application Command references, official API preview and change log. Preserve
   historical discovery membership pins and record current source hashes separately.
2. Complete application configuration, installation, flags_new, team/profile and
   activity-instance models and validated current-application updates.
3. Complete User-owned fields, connection/profile projections, authorized DM and
   current-membership operations, linked roles and bounded guild-list traversal,
   including large-bot shard parameters distinct from Gateway shard IDs.
4. Implement all available application command CRUD/list/bulk and permission
   operations, every command/option/handler type, localizations, installation and
   interaction contexts, bounded validation and explicit snapshot reconciliation.
   Keep the disabled batch-permission operation classified as unavailable.
5. Migrate the original partial generated User/Application seed to handwritten
   bounded codecs. Preserve scalar regression fixtures and isolate the generator's
   positive template fixtures from the evolving runtime inventory.
6. Update field/variant/endpoint evidence, parity and chronology together. Explicitly
   regenerate the fixed output set, inspect changes and check byte identity.
7. Run focused and strict root tests/build, REST example, tools and Python suites,
   inventory/generation/parity audits and affected serial local HTTP load profiles.
   Review documentation and the entire diff, stage all intended changes and suggest
   a commit message without creating a commit.

## Validation evidence

Implementation is complete for all **32 available written operations**: three
Application, twelve User, two linked-role metadata and fifteen global/guild command
and permission operations. The disabled batch-permission endpoint is recorded as
removed. Reviewed metadata includes 564 definitions, 183 mapped implemented
endpoints and explicit owned-field contracts; these are audit counts, not an API
parity percentage. Historical discovery remains 18,137 entries from 280 sources.

The final macOS arm64 / Apple Swift 6.4 validation passed:

- Root `swift build` and `SWIFTNIO_STRICT=1 swift test`: **831 test methods in
  97 suites across 12 bundles**, including the original 128 scalar regression
  cases and new request, codec, endpoint, snapshot, pagination and failure coverage.
- Independent `Examples/RESTOnly` build, without executing authenticated requests.
- `swift test --package-path Tools/DiscordKitTools`: **93 methods in seven suites**,
  including compiling and round-tripping the frozen positive generation seed.
- Tooling Python discovery: **10 tests**.
- `inventory validate --repository .`, explicit `generate --write --repository .`,
  `generate --check --repository .` and `parity check --repository .`: all passed.
  Five committed generated artifacts are byte-identical to current reviewed data;
  audits ran at the current UTC date, 2026-10-17, without `--as-of` overrides.
- `swift test --package-path Tools/DiscordKitLoadTests`: **18 methods in three
  suites**; load-harness Python peers: **eight tests**; release harness build passed.
- All six serial offline HTTP profiles passed the harness acceptance checks,
  including retry/request reduction, per-identity progress, sampled resource/RSS
  budgets and zero retained queues, active work, flights or cache entries at shutdown.

| Logical served accounts | Mode | Successful | Bounded refusals | Avoided exchanges | Sample p99 ms | Peak RSS MiB |
| ---: | --- | ---: | ---: | ---: | ---: | ---: |
| 100 | Normal | 2,000 | 0 | 1,154 | 10.123 | 10.05 |
| 100 | Burst | 1,152 | 848 | 1,012 | 46.769 | 12.64 |
| 10,000 | Normal | 10,000 | 0 | 5,906 | 10.457 | 11.56 |
| 10,000 | Burst | 6,402 | 3,598 | 5,629 | 62.362 | 14.53 |
| 1,000,000 | Normal | 20,000 | 0 | 11,984 | 4.778 | 14.17 |
| 1,000,000 | Burst | 14,469 | 5,531 | 12,030 | 91.061 | 18.02 |

These profiles use a scripted adapter with no sockets or credentials, 2/4/16 bot
identities and synthetic allowances. At most 4,096 successful prefix samples are
retained; peaks are sampled after operations. They measure one local policy
process, not Discord throughput, one million simultaneous connections, a fleet or
long-running stability. Burst refusals are the expected bounded-admission outcome;
there were no unexpected failures or cancellations. Platform/device, live API,
distributed ownership and soak gates remain open and separate.

Validation used writable canonical caches and `--disable-sandbox` after managed
cache/socket restrictions. Loopback adapter and Python peer tests used local host
socket access. A stale tool compiler-cache alias was isolated with fresh canonical
caches and scratch output; the unchanged smoke test then passed. No credentials or
live Discord requests were used.

Cross-review regression fixes ensure non-null image uploads cannot be mistaken for
unchanged CDN hashes, nullable preview connection-account names decode correctly,
and command numeric/name boundaries remain exact. Updated documentation, source
hashes, ambiguity decisions, parity chronology and frozen generator fixtures are
included in the handoff. All intended changes are staged; no commit is created.
