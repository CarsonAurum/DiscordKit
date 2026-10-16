# Local transport measurements

This development-only Swift package exercises the implemented NIO HTTP adapter
against an owned Python HTTP/1.1 loopback peer. It is separate from runtime
products, root unit tests and Discord's services. It never reads credentials.

Run from the repository root:

```sh
swift test --package-path Tools/DiscordKitLoadTests
python3 -m unittest discover -s Tools/DiscordKitLoadTests/scripts -p 'test_*.py'
swift run -c release --package-path Tools/DiscordKitLoadTests DiscordKitLoadTests --profile accounts-100 --scenario transport
swift run -c release --package-path Tools/DiscordKitLoadTests DiscordKitLoadTests --profile accounts-1000000 --scenario transport --burst
swift build -c release --package-path Tools/DiscordKitLoadTests
python3 Tools/DiscordKitLoadTests/scripts/record_baseline.py
```

Python 3 must be on PATH. The source checkout supplies profiles and the peer
script. The harness creates/reaps its peer, consumes every successful body to
EOF and closes the transport before reporting. HTTP/Gateway/cache/soak scenarios
return an explicit unsupported-scenario error until their runtime slices exist.

## Version 1 workloads

Accounts mean **served end users**. Bot identities, workers, guilds and shards
are workload dimensions simulated arithmetically inside one client process;
there are no actual bot credentials, Gateway sessions or distributed workers.
Each active logical user contributes 100 GET operations, with a fixed 1,024-byte
response. No full account population is allocated.

| Logical accounts | Bot identities | Simulated workers | Guilds / shards | Active users | Exchanges | Normal task cohort / pool slots |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 1 | 1 | 10 / 1 | 100 | 10,000 | 8 / 8 |
| 10,000 | 4 | 4 | 1,000 / 4 | 1,000 | 100,000 | 16 / 16 |
| 1,000,000 | 16 | 4 | 10,000 / 16 | 1,000 | 100,000 | 32 / 32 |

All profiles use one origin, no upload, a 1,024-byte response cap, a 4,096-byte
header budget and 1,024-byte read chunks. The response consumer immediately
pulls to EOF; slow subscribers are not simulated in this milestone. Admission
is fail-fast: queued count/bytes/age are zero, cache count/bytes are zero, and
pool ownership records are bounded by the configured connection cap. The
`maximumMetadataEntries` budget counts those ownership slots, not every runtime
allocation. Live malloc gauges and process RSS expose the additional overhead.

A burst offers ten times the task cohort while retaining the same socket cap.
The harness creates at most 80/160/320 child tasks, replenished as each completes;
it never creates a task or socket per logical account. Refused requests are
counted separately, without retry. This is a closed-loop saturation test, not
an arrival-rate simulator or a claim about admitted REST/Gateway throughput.

The initial reference-hardware acceptance thresholds for normal runs are p99 at
most **25 ms** over the bounded successful latency sample and at least **5,000
successful exchanges/s**. All runs have **64 MiB peak client RSS** and **32 MiB
end-of-workload live heap** budgets. These are versioned local acceptance
thresholds, not promised runtime capacity. Burst runs measure saturation and
refusals; their latency and throughput do not establish a service level.
Recheck budgets when the workload, hardware, payload, adapter or runtime changes.

## Recorded baseline

The committed release measurements ran on an Apple M3 Max, 14 processors,
36 GiB RAM, macOS 27.0.1 and Swift 6.4. The normal runs met their local acceptance
thresholds, with zero refused or failed requests. Physical accepted and peak
socket counts were exactly 8/16/32, so these runs reused their original sockets.

| Logical accounts | Successful exchanges/s | p50 / p95 / p99, ms | Client CPU, one-core % | Peak client RSS, MiB | EOF live heap / settled live heap, MiB | Actual peak sockets |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 16,559.6 | 0.391 / 0.918 / 1.386 | 275.2 | 15.17 | 3.98 / 0.76 | 8 |
| 10,000 | 18,626.2 | 0.743 / 1.424 / 1.931 | 285.0 | 16.50 | 4.63 / 0.98 | 16 |
| 1,000,000 | 20,133.8 | 1.402 / 2.539 / 4.018 | 298.3 | 17.52 | 5.28 / 1.05 | 32 |

With ten times the offered task cohort, admitted/refused counts were
112/9,888, 1,200/98,800 and 1,216/98,784 respectively. These runs had no failed
requests and kept physical socket peaks at 8/16/32. Burst p99 values were
6.332/10.198/24.893 ms; burst latency is recorded without a service-level gate.
All six runs closed every client-owned pool slot. JSON evidence retains exact
CPU, byte, latency, deadline and counter values; settled gauges were sampled one
second after cleanup. Peak RSS in this table includes that settling interval.

## Measurement scope

Each JSON result reports offered/admitted/refused/failed work, actual payload
bytes, wall duration, successful exchanges/s, sampled pool slots, p50/p95/p99,
client CPU and peak/current RSS. The peer separately counts accepted, active and
peak physical TCP connections. Its active count is captured immediately before
process termination, so it may include sockets whose client FIN has not yet been
observed; the process is then reaped. Latencies cover headers plus full body EOF and
retain at most the first 4,096 successful samples. The `steady` memory field
is an **end-of-workload snapshot**, not proof of a steady-state process.

On Darwin, malloc-zone live block/byte gauges expose live heap retention; they
are not cumulative allocation events, allocation call stacks or a substitute
for an Instruments allocation trace. CPU/RSS exclude the Python peer and other
processes. CPU percentage is relative to one core and can exceed 100%. Pool
slot peaks are sampled after headers and can miss transient peaks; the fixed
configured cap and zero active/idle slots after shutdown are reported separately.

The committed environment record names hardware, OS, compiler, configuration,
time and source-commit basis. The working tree was dirty because these are
measurements of the change being prepared. A short local baseline does not
qualify a distributed fleet, a million simultaneous identities/connections,
Gateway control delay, request reduction, minimum-OS behavior or a 30-minute
fixed-working-set soak. Those remain separate qualification gates.

Allocation diagnostics preserve the same workload and allow isolation without
network sockets or deadline races:

```sh
swift run -c release --package-path Tools/DiscordKitLoadTests DiscordKitLoadTests --profile accounts-100 --scenario transport --portable
swift run -c release --package-path Tools/DiscordKitLoadTests DiscordKitLoadTests --profile accounts-100 --scenario transport --without-deadline
swift run -c release --package-path Tools/DiscordKitLoadTests DiscordKitLoadTests --profile accounts-100 --scenario transport --portable --settle-seconds 12
```

The optional wall-time settling delay is a performance diagnostic; deterministic
unit tests use no sleeps. Disabling deadlines is an explicit diagnostic and is
never the ordinary baseline configuration.

The diagnostics found a cancelled native `ContinuousClock.sleep` allocation
history that persisted until its original ten-second deadline. The transport
deadline helper now checkpoints continuous-clock waits at most 100 ms ahead,
preserving clock semantics while shortening that retention window. In the
portable diagnostic, increasing work from 10,000 to 100,000 exchanges left
21.29/24.00 MB of live heap at EOF and 0.79/1.43 MB after one second. These
decimal-byte figures and the original isolation runs are preserved in
`Baselines/deadline-allocation-regression.json`; they are diagnostics, not socket
capacity results. Allocator RSS can stay elevated after live blocks are freed.
