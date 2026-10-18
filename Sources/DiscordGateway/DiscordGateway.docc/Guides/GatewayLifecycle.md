# Owning Gateway discovery, sharding and session lifetime

Use explicit topology, shared Identify authority and bounded heartbeat/resume supervision.

## Overview

### Separate pure state from effects

``GatewaySessionState`` is a synchronous transition reducer. It returns the action the owner should perform and rejects invalid edges without changing state.

```swift
import DiscordGateway

var state = GatewaySessionState()
let connect = try state.apply(.start)
let receive = try state.apply(.connected)
let authenticate = try state.apply(.hello(resumable: false))
let ready = try state.apply(.ready)
assert(connect == .connect)
assert(receive == .receive)
assert(authenticate == .authenticate(resume: false))
assert(ready == .receive)
assert(state.phase == .ready)
```

This example opens no connection. ``GatewayShard`` owns actual injected socket work and applies generation fences around reconnects. Constructors remain inert; the run owner starts and supervises work and stop closes it.

### Discover before allocating sessions

``GatewayEndpoints`` exposes authenticated discovery, and ``GatewayDiscovery`` validates the recommended shard count and session-start limit. Choose a fixed subset of indices and a finite local maximum. Public bot identity, topology generation, shard index and shard count form a complete source identity.

All workers for a bot credential share startup admission and opcode authority. Identify consumes server allowance before the write and is not refunded after uncertain submission. Resume follows its distinct retained-session path. A discovery reset is not an indefinitely recurring replenishment timer; refresh current discovery when required by the coordinator.

Use one lease authority to prevent duplicate shard ownership. Distributed workers need a common atomic, fail-closed store with expiry and fencing. Before changing shard count/topology, drain old owners explicitly; assigning another generation label alone does not stop an old socket.

### Keep control work independent

The shard bounds received envelopes, queued bytes, pending requests and sends. Heartbeats, acknowledgements and connection supervision do not run through user handlers or cache I/O. Missing heartbeat acknowledgement, invalid sessions, reconnect requests and close codes select documented bounded recovery rather than an infinite retry loop.

``GatewayCloseDisposition`` classifies authentication/configuration errors as fatal, invalid-session/normal closures as requiring Identify and other recoverable closures as candidates for Resume when retained state permits it. Do not restart a fatal configuration unchanged or reset shared quotas by constructing new authorities.

### End ownership explicitly

Cancellation must stop discovery/connect/read/write work, close the active connection and release leases before handoff. Inspect the run task's failure after shutdown, because cancellation of a sibling does not make another cleanup failure irrelevant. Sessions and credentials can be sensitive; snapshots and ordinary error descriptions avoid exposing them.

Use [GatewayBot](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/GatewayBot) for complete host composition, and the [Gateway contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Gateway.md) for protocol bounds and recovery behavior. Local scripted peers validate state ownership; they do not establish live Discord or fleet qualification.
