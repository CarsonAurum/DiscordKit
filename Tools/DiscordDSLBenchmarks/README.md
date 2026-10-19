# Independent offline DSL benchmarks

Part 15K development tooling compares direct handwritten routes and real DSL
lowering through the same typed decoder, manual handler, existing `CommandRouter`
and `InteractionResponder`. It is a downstream package; no runtime product selects
it. It starts no listener and uses no credentials, hydration provider, registration
reconciler or remote transport. Synthetic normalized interactions bypass HTTP
signature verification and Gateway ingestion.
The executable sends SwiftLog diagnostics to stderr; stdout or `--output` contains only the JSON report.

Run from the repository root with Swift 6.4 or newer:

```sh
swift test --package-path Tools/DiscordDSLBenchmarks --explicit-target-dependency-import-check error
python3 -m unittest discover -s Tools/DiscordDSLBenchmarks/scripts -p 'test_*.py'
swift run -c release --package-path Tools/DiscordDSLBenchmarks DiscordDSLBenchmarks --output /tmp/dsl-runtime.json
python3 Tools/DiscordDSLBenchmarks/scripts/compile_benchmarks.py --output /tmp/dsl-compile.json
```

The default runtime matrix performs **1,000,000 invocations for each direct/DSL path
at 10, 100 and 1,000 declarations**: six million invocations in total, eight offered
workers, a fixed 64-byte string, and at most 10,000 latency samples per path. Each
worker reuses fixed input snapshots, schemas and the router. A fresh typed argument
value and response owner are created per invocation. Sink validation checks the
exact callback payload, and every child is joined before measurements finish.
No live registration limits or connection counts are inferred from declarations.

| Option | Default | Valid range |
| --- | --- | --- |
| `--invocations` | 1,000,000 per workload | 1...10,000,000 |
| `--handlers` | `10,100,1000` | Unique nonempty subset of those counts |
| `--concurrency` | 8 | 1...64 |
| `--payload-bytes` | 64 | 1...1,024 ASCII bytes |
| `--sample-limit` | 10,000 | 1...100,000 |
| `--minimum-duration-seconds` | 0 | 0...1,800 per workload |
| `--output` | stdout | Explicit local JSON destination |

Duration-floor execution repeats the same population after the invocation floor;
it fails at a hard 100,000,000-invocation ceiling. Memory observations retain at
most 121 checkpoints. A focused sustained handler run is:

```sh
swift run -c release --package-path Tools/DiscordDSLBenchmarks DiscordDSLBenchmarks --handlers 1000 --invocations 1000000 --minimum-duration-seconds 60 --output /tmp/dsl-handler-soak.json
```

Reports identify exact dimensions and hardware/compiler metadata. Plan compilation
measures schema/definition authoring, DSL lowering where selected, and router
admission; fixed interaction preparation is outside that timer. Invocation timing
includes fresh response ownership, decoding, routing, handler execution and callback
validation. Throughput includes all successful invocations and worker-round joins.
Quantiles use a bounded **prefix** sample and nearest rank; they are not an unbiased
full-duration latency distribution. Direct runs precede DSL runs. Runtime warm-up,
allocator history, instrumentation and concurrent host work affect observations;
these measurements do not isolate a causal abstraction overhead.

Accounted state records finite retained JSON bytes and cardinality limits, not every
Swift object or exact heap size. macOS reports actual current/peak RSS and live malloc
blocks/bytes. Linux currently reports actual peak RSS; unsupported current RSS/live
allocator gauges are omitted. Live allocations are not cumulative allocation events.
CPU and peak RSS are process-wide, and earlier matrix rows affect later observations.
All owned active handler/worker/acknowledgement counters must be zero after cleanup;
allocator page retention is reported separately.

The compiler script generates six independent executable consumers with concrete
manual or macro handlers, ten declarations per file. The same Swift toolchain and
native SwiftPM build engine measure both paths. Dependency/plugin bootstrap is
reported separately. A clean consumer build deletes only that consumer's outputs,
keeping dependencies and the macro plugin warm; it includes SwiftPM planning,
type checking, code generation and linking. Incremental builds edit one literal in
the first handler file and restore the source even on failure. Each executable
constructs its catalog and verifies the exact declaration/route count without
executing handlers. Compiler maximum RSS is the maximum-resident-set observation reported by `time`
for each build command, not a sum of simultaneous compiler-process RSS or an
instantaneous whole-host memory measurement.

`--samples` accepts 1...5 (default 1), `--jobs` 1...32 (default 4), and per-build
`--timeout` 1...3,600 seconds (default 1,800). The workspace must be empty or marked
by the runner; it defaults to the ignored root build directory. Use `--workspace`
and `--cache-path` for isolated writable paths. Pinned dependencies must already be
available to the selected cache; resolution and dependency updates are disabled.
Measurements use the native backend without its optional explicit-import checker;
the repository's independent graph/import audit checks product isolation separately.

Record observations **before** choosing tolerances:

```sh
python3 Tools/DiscordDSLBenchmarks/scripts/baseline.py record --compile-report /tmp/dsl-compile.json --runtime-report /tmp/dsl-runtime.json --output /tmp/dsl-baseline.json
python3 Tools/DiscordDSLBenchmarks/scripts/baseline.py budgets --baseline /tmp/dsl-baseline.json --output /tmp/dsl-budgets.json
python3 Tools/DiscordDSLBenchmarks/scripts/baseline.py check --baseline /tmp/dsl-baseline.json --budgets /tmp/dsl-budgets.json --compile-report /tmp/dsl-compile.json --runtime-report /tmp/dsl-runtime.json --output /tmp/dsl-check.json
```

After inspecting the first recorded submillisecond invocation observations, the
reviewed budgets use 10% relative tolerances, a 1 microsecond absolute timing floor
and a 1 MiB RSS/live-byte floor. The timing floor is an observation tolerance,
not a clock-resolution claim. Every collected cost metric receives a finite
bound; throughput has a minimum and time/state/memory have maxima. Hard functional
invariants are checked separately and are never relaxed by tolerances. Baseline
and budgets are hash-bound; hardware, compiler, configuration, compiler fixture and
resolution identities must match. The complete six-row matrices are required.
Reduced CI smoke runs cannot substitute for the qualified default matrix.
A single overrun fails the local check. Three matching runs are required before
attributing a >10% regression to a change. A first baseline self-check validates
budget wiring; it does not establish a comparison against a previous implementation.

The committed [15K evidence](../../Docs/Release/phase15k-validation.json) records
actual commands, sources, executable identities, timings and limitations. The
existing [cache/broadcast 30-minute soak](../DiscordKitLoadTests/README.md) and the
new handler soak remain independent evidence. Neither establishes production/fleet
capacity, live Discord, HTTP/Gateway host throughput, another platform, hardware,
independent crypto review or full Phase 15 release certification.
