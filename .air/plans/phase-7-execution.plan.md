# Phase 7 execution — consumer runtime, state and event delivery

Started 2026-10-16 from `cd2ac73`; the working tree was clean.

## Implementation plan

1. Introduce independently adopted Cache and Client products, preserving the existing
   dependency direction and Swift 6.4 concurrency settings.
2. Compose discovery, fixed-topology shards, service access, diagnostics, structured
   cancellation and idempotent awaited shutdown in a task-free client constructor.
3. Add independent bounded broadcast queues, explicit overflow behavior and bounded
   ordered handler execution. Share aggregate authorities across clients.
4. Add opt-in scoped entity projections with count/byte/TTL/refresh limits, sparse
   merging, visibility invalidation, stale-fetch fences and explicit uncertainty.
5. Resolve arbitrary-width permissions from explicitly complete supplied state,
   returning indeterminate for missing/redacted evidence.
6. Add a bot consumer example and fixed-working-set cache/event soak and recovery
   measurement. Preserve actual RSS alongside accounted cache bytes.
7. Run focused and full Swift tests/builds, independent examples, load/tooling/Python
   checks and nonwriting generation/parity validation. Review and commit the final diff.

## Source verification

Official Gateway, Gateway Events, change log, Permissions and Threads references
were checked on 2026-10-16. Existing REST/Gateway v10 behavior is reused; this phase
adds local consumer semantics rather than new Discord endpoints or dispatch names.
Channel obfuscation and partial payloads remain uncertainty, never authorization.

## Validation and qualification

Final source validation on macOS with Apple Swift 6.4 completed on 2026-10-17 UTC:

- Root `swift build` and `SWIFTNIO_STRICT=1 swift test`: **1,235 test methods in
  137 suites across 14 target bundles**, zero failures. Writable compiler caches,
  `--disable-sandbox` and host loopback access were used for managed-host validation.
- Independent tooling: **93 Swift tests in seven suites** and **10 Python tests**.
- Inventory validation: **18,137 entries / 280 sources**, zero unclassified entries;
  parity remains **891 reviewed contracts / 240 mapped implemented entries**.
  `generate --check` confirmed five byte-identical committed artifacts; parity check
  passed without altering the reviewed definitions or fetching/generating consumer code.
- Independent REST-only and Gateway bot examples build without credentials or
  authenticated execution. The bot example protects subscription admission with
  the same awaited owner cleanup as runtime failures.
- Load harness: **28 Swift tests in four suites** and **12 Python tests**, including
  loopback peer checks with host socket access. Local measured profiles are recorded in its
  [README](../../Tools/DiscordKitLoadTests/README.md) and baseline JSON files.
  Twelve finite cache/soak profiles cover normal and burst admission at three logical
  populations; six finite Gateway profiles cover the changed runtime cleanup path.

The fixed-working-set cache/broadcast soak completed **1,800.004 seconds / 238,427
rounds** with four opaque scopes and 20 fixed keys per scope. It completed **7,629,664
refresh reads using 953,708 loader calls** (87.5% fewer loaders than completed reads)
and explicitly refused 53,407,648 excess calls. Peak retained state was **64 entries /
72,512 accounted bytes**, below the 262,144-byte cap. Peak refresh/waiter/broadcast
queue counts were **1 / 8 / 2**; every owned shutdown counter returned to zero.

The 121 actual process checkpoints show no sustained RSS growth: all 20 samples in
the final five minutes were **8,781,824 bytes**. Process peak RSS was **9,715,712
bytes**, with **8,863,744 bytes** after shutdown; retained allocator/runtime overhead
is distinct from the now-empty cache. Final-five-minute live heap ranged from
326,784 to 360,960 bytes. The report and environment record preserve source/executable
checksums and distinguish later error-only/documentation/unexecuted adapter changes
from the exercised cache/refresh/broadcast success paths. Concurrent validation
processes mean CPU/wall observations are not an isolated throughput benchmark.

No live Discord request, cross-platform runtime, physical-device background or
deployment-capacity claim follows from these local tests. JSON entity projections
remain partial, persistence/distributed authorities remain injected contracts and
permission results never establish current Discord authorization.
