# Phase 3 execution plan

Date: 2026-10-16. Source: Part 3 and required early Part 6 steps 1–5 in the master roadmap.

1. Inspect the clean baseline and verify Swift 6.4 and official Discord v10 contracts.
2. Introduce implemented Models/HTTP/Gateway products with existing concurrency settings.
3. Deliver bounded request descriptors, JSON/form/multipart codecs, error evidence,
   fixed-origin raw access, unauthenticated assets, lazy pagination and operation-specific polling.
4. Implement injectable atomic rate authority, partitioned in-process rate state,
   finite FIFO scheduling, deadlines, fail-closed coordinator errors and bounded retry safety.
5. Integrate REST execution, current-user/application descriptors, independently
   cancellable read coalescing, opt-in TTL/LRU caching and invalidation fencing.
6. Deliver the minimal sharded JSON Gateway lifecycle, heartbeat/reconnect/resume,
   generation fences, leases, Identify buckets and shared session-start allowances.
7. Add deterministic Swift Testing coverage and a standalone REST-only example;
   extend local-only load profiles and record measured HTTP request savings/budgets.
8. Update architecture, parity inventory/history, contribution guidance and limitations.
9. Run root build/test, tooling inventory checks, independent load Swift/Python tests,
   example build, review the complete diff and stage the scoped result.
10. Suggest the commit message from the final staged changes; do not create a commit.

Qualification remains explicit: local/scripted evidence is not live Discord parity,
full resource/event catalog support, distributed-store certification, cross-platform
qualification or a million-connection capacity claim. Unsupported gates stay recorded.

## Execution results

The implementation and required early Gateway slice are complete. Models, HTTP and
Gateway are independent opt-in products; no external dependency was added. Current
user/application models remain partial, while Gateway discovery validates its complete
required envelope. Parity inventory updates distinguish those support levels.

Final validation passed:

- Root `swift build` and `swift test`: 297 test methods across 12 test bundles.
- Independent `Examples/RESTOnly` build, without running authenticated operations.
- `Tools/DiscordKitTools` Swift tests, inventory validation and Python discovery tests.
- Independent load package Swift tests (18 methods) and Python tests (8 methods).
- NIO/Gateway repeated regression runs after fixing the fast-peer upgrade write race.
- Matching root/example/load dependency pins, Markdown relative links and whitespace checks.

The managed environment uses a temporary Clang module cache and `--disable-sandbox`;
socket tests ran with the approved local-loopback access. No check contacted Discord
or used real credentials. Numeric HTTP/Gateway evidence is recorded by serial release
captures, with measured results and workload limits in the load-harness report.

All six HTTP and six Gateway release captures passed their recorder gates. Normal
HTTP workloads avoided 57–60% of exchanges with p99 below 11 ms. Gateway runs met
their exact event/startup/Resume expectations and released every tracked connection
and lease. These are short local scripted measurements, without a deployment claim.

The final scoped diff is reviewed and staged. No commit is created;
the commit message is supplied after verifying the complete staged snapshot.
