[//]: # "File: Sources/DiscordTransport/DiscordTransport.docc/Guides/ImplementingAdapters.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Implementing adapters and deterministic peers

Honor single-send semantics, finite admission and cleanup contracts in production and test backends.

## Overview

### HTTP and WebSocket boundaries

``HTTPTransport`` accepts a complete `HTTPRequest` and returns an `HTTPResponse` with a transferred body. Preserve duplicate header fields where the backend supports them, reject invalid framing and never follow redirects or retry internally. The policy layer must see the original status and decide what it means. Credential origin policy belongs above a generic transport, so do not copy authentication to a redirect destination.

``WebSocketTransport`` creates an owned connection. `WebSocketConnection` exchanges complete text/binary messages; `WebSocketSessionConnection` adds session information needed by protocols such as Gateway. Bound message bytes, pending reads, application writers and control replies independently. Ping/pong, heartbeat and close traffic must remain serviceable when application consumers are slow.

Datagram transport preserves packet and peer boundaries, including empty datagrams. IPC is an ordered byte stream and supplies no message framing by itself. HTTP ingress transfers accepted exchanges and exactly-once response ownership. Higher products add Voice, RPC and signed interaction semantics; a generic adapter should not guess them.

### Bound the entire resource graph

Cap connecting and live resources, queued messages, per-message bytes, aggregate bytes and pending writers. Define fail-fast overload or a finite queue; an unlimited collection of suspended tasks is still an unlimited queue. Cancellation must remove waiting work and close resources that have not been transferred. Shared cleanup callers should await one retained cleanup operation.

Use sanitized error categories rather than retaining native error objects with URLs, headers, request bodies or TLS paths. Continue validating TLS certificates and hostnames. Explicit test trust roots can select a local test authority without disabling verification.

### Test observable ownership

Supply a scripted HTTP peer that records request method, path, repeated query items and permitted headers, then returns bounded body chunks or a chosen failure. Count opens, pulls, sends and closes. Assert that invalid descriptors send nothing, redirects send only once, early consumer termination closes the body and cancellation releases admission. Test malformed framing, oversize chunks, repeated close, concurrent readers, late producer completion and deadline cleanup.

For WebSockets, script complete frames, connection close codes, heartbeat acknowledgements and cancellation barriers. For datagrams, assert exact peer and packet boundaries. Use synthetic credentials and never print the recorded full request by default.

### Shard ownership is a separate authority

``ShardIdentity`` validates fixed topology. `ShardLeaseStore` defines atomic leases with expiry and fencing, while `InProcessShardLeaseStore` is a process-local bounded implementation. Distributed deployments need a common external store that rejects stale fences and fails closed during outages. A new topology generation does not by itself stop old owners; explicitly drain the old topology before starting replacements.
