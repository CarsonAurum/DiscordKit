# Local runtime measurements

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
EOF and closes the transport before reporting. HTTP and Gateway policy scenarios
use finite offline scripts with no sockets or credentials. Standalone cache and
soak scenarios return an explicit unsupported-scenario error.

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

## Offline HTTP policy measurements

The HTTP scenario exercises the phase-3 execution pipeline with an entirely local
scripted HTTP adapter: zero credentials, zero network requests and zero sockets.
It measures policy overhead separately from the existing loopback transport
measurements. Run all three logical populations in normal and tenfold-burst modes:

```sh
swift test --package-path Tools/DiscordKitLoadTests
swift build -c release --package-path Tools/DiscordKitLoadTests
swift run -c release --package-path Tools/DiscordKitLoadTests DiscordKitLoadTests --scenario http --profile accounts-100
python3 Tools/DiscordKitLoadTests/scripts/record_baseline.py --scenario http
```

The numeric HTTPProfiles are separate from transport profiles. Logical accounts
still mean served end users. They allocate only 2/4/16 actual opaque credential
partitions, each with one client, inside one process. No population-sized user
array, distributed worker or Discord connection is created.

| Served-user dimension | Actual identities | Logical requests | Normal / burst task cohort | Queue / in-flight caps | Queued bytes | Cache entries / payload bytes | Rate metadata cap |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | 2 | 2,000 | 8 / 80 | 16 / 8 | 32 KiB | 16 / 32 KiB | 256 |
| 10,000 | 4 | 10,000 | 16 / 160 | 32 / 16 | 64 KiB | 32 / 64 KiB | 512 |
| 1,000,000 | 16 | 20,000 | 32 / 320 | 64 / 32 | 128 KiB | 128 / 256 KiB | 2,048 |

The mix is 40% explicit 60-second TTL reads, 30% eligible coalesced read storms,
10% hot-bucket reads, 10% independent reads and 10% reads rejected once with a
429 before succeeding. Returned successes contain exactly 256 bytes. Artificial
wire latency is 1 ms; hot buckets announce a 2 ms reset and rejected retries a
1 ms delay. The synthetic initial global allowance is 1,000,000/s solely to
isolate policy overhead; it is never a Discord quota or recommended setting.

All profiles require normal successful p99 at most 100 ms and peak process RSS
at most 128 MiB. Burst runs retain the same resource caps; refusals are expected
and have no latency service-level gate. Reports retain the first 4,096 successful
latencies, request savings, retry responses, per-identity success extrema and
sampled queue/cache/metadata/active peaks. Configured caps and deterministic root
tests establish hard bounds; sampling may miss a transient peak. Every run closes
coalesced work, the coordinator and cached entries before reporting cleanup.
These local measurements do not qualify Discord quota throughput, distributed
fairness, simultaneous user connections or a 30-minute soak.

The recorders execute one process at a time. Final HTTP and Gateway captures run
serially after release compilation and validation finish, with all six HTTP runs
followed by all six Gateway runs. These finite scripts measure bounded local
policy and lifecycle work; sustained deployment capacity remains unqualified.

The final release measurements below were recorded serially on 2026-10-16 using
Apple Swift 6.4 on an Apple M3 Max (38,654,705,664 bytes RAM). The checked-in
[HTTP environment](Baselines/http-environment.json) records the source revision
basis and the uncommitted phase-3 working tree used for this run. Each JSON report
in [Baselines](Baselines) includes raw counts, CPU time, latency quantiles for successful requests,
configured budgets and sampled resource peaks.

| Served-user dimension | Mode | Successful / refused requests | Wire exchanges | Avoided exchanges | Sampled p99 (ms) | CPU (s) | Peak RSS (MiB) |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 100 | Normal | 2,000 / 0 | 1,053 | 1,147 (57.4%) | 10.939 | 0.482 | 9.97 |
| 100 | Burst | 1,235 / 765 | 166 | 1,095 (88.7%) | 30.515 | 0.242 | 12.34 |
| 10,000 | Normal | 10,000 / 0 | 5,089 | 5,911 (59.1%) | 10.080 | 1.276 | 11.50 |
| 10,000 | Burst | 6,645 / 3,355 | 978 | 5,816 (87.5%) | 56.618 | 1.310 | 14.48 |
| 1,000,000 | Normal | 20,000 / 0 | 10,020 | 11,980 (59.9%) | 4.616 | 2.202 | 13.61 |
| 1,000,000 | Burst | 14,386 / 5,614 | 2,889 | 11,979 (83.3%) | 83.184 | 3.262 | 17.45 |

Avoided exchanges equal successful logical requests minus non-retry wire
exchanges; percentages use successful logical requests as their denominator.
Normal runs exercised exactly 200/1,000/2,000 explicit retry responses, and every
identity completed its equal request share. All twelve final HTTP/Gateway captures
passed their recorder gates. The six HTTP runs had zero unexpected failures,
zero cancellation and zero retained active requests, queued requests, coalesced
flights or cache entries after shutdown. Burst refusals preserve the configured
resource caps and change the successful request mix, so their savings percentages
describe admitted work rather than the entire offered workload.

The separate Gateway scenario exercises finite local session scripts and owned
shard groups without opening sockets or reading credentials:

```sh
swift run -c release --package-path Tools/DiscordKitLoadTests DiscordKitLoadTests --scenario gateway --profile accounts-100
swift run -c release --package-path Tools/DiscordKitLoadTests DiscordKitLoadTests --scenario gateway --profile accounts-1000000 --burst
python3 Tools/DiscordKitLoadTests/scripts/record_gateway_baseline.py
```

HTTP and Gateway scenarios reject transport-only portable/deadline/settling flags;
all recorded control traffic and responses are script-produced.

Each selected shard now completes three ready-session rounds separated by two
scripted reconnects. Every round sends production presence and voice-state
commands, then completes member, soundboard and channel-info requests through
the production correlation registry. Member responses arrive as two chunks in
reverse order; all four response events per round pass typed dispatch decoding.
The report requires exactly three completions per request family, twelve typed
response events and fifteen application writes per selected shard. The raw
dispatch target remains a separate count controlled by the selected profile.

The scenario shares command authority across each synthetic bot's shards, uses
at most four pending requests and 65,536 response bytes per shard, and retains
at most eight response events per request and 32 correlation keys per shard.
It reports aggregate configured ceilings alongside actual pending request and
application write counts after shutdown; both must be zero, together with owned
connections and leases. Producer credits bound raw ingress while each request
round runs, and reconnect gates wait for that round's replies before replacing
the socket. Each socket requests at most one extra heartbeat after eight raw
events, bounding control-delay samples to three per shard while respecting
production send-rate admission. These finite scripts qualify local recovery and correlation only;
they do not establish real Discord quotas, network throughput, distributed
coordination or sustained production capacity.
