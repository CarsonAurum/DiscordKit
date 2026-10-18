# ``DiscordFoundationTransport``

Use explicitly owned Foundation HTTP and WebSocket adapters with application-level limits.

## Overview

This independent backend adapts URLSession to the DiscordTransport contracts. It uses ephemeral sessions with cookies, platform response caching, redirects and credential persistence disabled. Foundation remains responsible for TLS, protocol negotiation and private socket buffers; the configured bounds describe admitted operations and consumed application bytes.

Use <doc:FoundationRequests> to inject this adapter into a REST consumer, then review <doc:FoundationLimits> before choosing it for a deployment.

## Topics

### Foundation adoption

- <doc:FoundationRequests>
- <doc:FoundationLimits>

### API reference

- <doc:APIReference>
