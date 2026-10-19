# Test applications with deterministic boundaries

Validate values, policy, lifecycle and failure recovery without depending on live Discord.

## Overview

### Test pure values first

Use Swift Testing to check tagged identifiers, payload validation, presence-aware updates, unknown raw values and wire encoding. The command example's tests assert both ephemeral and public reply payloads and exact component custom IDs:

```sh
swift test --package-path Examples/CommandsApp
```

Use large identifiers and malformed fixtures alongside normal inputs. Assert observable wire values rather than only checking that a constructor can run.

### Inject time and I/O

The public transport contracts let an application supply deterministic HTTP, WebSocket, datagram, IPC, ingress or Activity peers. Inject clocks so deadline, replay, retry and expiry tests advance deterministically. Repository test-support types are development-only and are intentionally excluded from published products; consumers can implement their own narrow test doubles using the public protocols.

When testing asynchronous code, assert cancellation cleanup, pending-count and byte accounting, concurrent caller ordering, duplicate/late response behavior and closure of owned resources. A scripted successful response alone does not test recovery.

### Test compiled modules and their hosts

Follow <doc:AuthorCommandModules>, <doc:ComposeGatewayModules> and <doc:HostAModuleBot> for independently compiled offline consumers. Test exact direct/DSL definitions and callback JSON, fresh argument values, absent/null/wrong-kind rejection, source diagnostics and structural bounds. Assert zero service/handler/registration effects during compilation, short-circuit policy behavior and zero owned counters after joined cancellation or failure. Macro external positive/negative fixtures prove real plugin compilation; expansion text alone does not establish runtime parity.

Actor dependencies retain ordinary Swift isolation and the same application-owned reference across modules. Inject finite clocks/peers and reuse compiled schemas/routes across invocations. Keep separate handler/compiler measurements and cache/broadcast soak evidence with their actual workload, duration and host; offline results do not qualify a live fleet.

### Use local peers for framing and ownership

Root tests include bounded loopback adapter peers. Browser tests simulate a postMessage host and verify exact source/origin checks and correlation. Activity backend tests exercise authenticated session and entitlement policy without an actual purchase:

```sh
swift test
swift test --package-path Examples/ActivityHost
node --test Browser/DiscordActivityBridge/*.test.mjs
```

Run host-specific checks on a host that supports those adapters. Managed environments may require writable compiler caches or loopback access; record that scope rather than treating an unavailable check as a pass.

### Validate example isolation

Build the independent package that matches your application. This verifies its selected dependency graph instead of relying on an umbrella import. CommandsApp, VoiceBot and SocialApp are designed for offline runs. RESTOnly and GatewayBot can make authenticated requests when their environment is configured; HTTPApp can bind a listener. Build those examples during ordinary verification and run them only in a deliberately configured environment.

### Measure capacity with a workload

The [local load harness](https://github.com/CarsonAurum/DiscordKit/tree/main/Tools/DiscordKitLoadTests) measures bounded request, socket, cache and event scenarios. Record actual connections, credential count, workload, queue bounds, throughput, tail latency, RSS and recovery. Logical accounts or a successful short test cannot establish fleet or long-duration behavior.

Published vectors and synthetic media round trips validate named algorithms and framing. They do not establish complete codec interoperability, independent crypto review, a qualified device route or authorized Discord media.
