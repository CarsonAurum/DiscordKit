[//]: # "File: Sources/DiscordGateway/DiscordGateway.docc/Guides/GatewayCommandsAndRequests.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Sending commands and correlating responses

Use typed outbound payloads, independent opcode admission and bounded request ownership.

## Overview

### Select the documented command shape

Typed outgoing commands describe presence, voice-state changes and bounded request families. Unknown inbound events remain readable, but unknown outbound opcodes are not guessed. Explicit intents, readiness, shard selection and payload validation precede the send.

Opcode admission is separate from REST and Identify budgets. Share its authority across the credential's shards and workers. Control work has independent admission from application commands so that overload cannot consume the ability to heartbeat or close. A new shard or reconnected socket does not create new REST allowance.

``GatewayCommandCoordinator`` and the request APIs bound pending count, retained bytes and lifetime. A locally accepted send means ownership was admitted, not that Discord completed the requested action. Cancellation before submission differs from cancellation after bytes may have been sent.

### Correlate with exact request identity

Requests that have protocol correlation use their documented nonce and response rules. Register bounded ownership before a response can race the outgoing send. Reject conflicting or excessive pending requests instead of collecting unbounded waiters. Connection generations and shard identity fence late replies from an older session.

Member/soundboard request families can return multiple chunks or partial data. Completion follows their actual count/index/correlation contract. An empty chunk does not universally mean completion, and another consumer's unrelated event must not satisfy the request. Keep unknown and duplicate events available to ordinary event consumers while resolving only the matching request owner.

Missing required intents, a nonready shard, timeout, disconnect, request conflict and admission exhaustion are explicit failures. Recovery may require waiting for readiness, supplying approved intents, reducing work or resynchronizing state. Retrying a mutation after an uncertain socket write needs an application decision; it is not generic command replay.

### Build deterministic request tests

Inject a WebSocket peer and clock. Assert exact opcode/body, nonce ownership, intent checks, one send, reply-before-suspension races, duplicate/out-of-order chunks, concurrent distinct requests, conflicting nonces, capacity exhaustion, deadline expiry and disconnect cleanup. Assert that pending slots and bytes return to zero and late replies cannot complete a new generation's request.

Keep diagnostics bounded and opaque. A request nonce can be a correlation aid, but never put credentials or personal identifiers into it merely to make logs readable. See the [Gateway command contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Gateway.md) for the supported request families and limits.
