[//]: # "File: Sources/DiscordFoundationTransport/DiscordFoundationTransport.docc/Guides/FoundationLimits.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Choosing Foundation limits and understanding failures

Distinguish application admission and byte limits from platform-managed networking behavior.

## Overview

### Select finite budgets

The default configuration admits 32 operations, collects at most eight MiB per request body, consumes at most eight MiB per response body, emits chunks up to 16 KiB and caps complete WebSocket messages at one MiB. Network timeout defaults to 60 seconds; an injected earlier operation deadline still applies.

Operations include transferred response bodies and live WebSockets. Excess admission fails immediately, so callers should bound their task groups and handle overload rather than creating a task per account. Request uploads are collected within the configured bound before transmission; a BodyStream input does not make this a streaming-upload implementation.

```swift
import DiscordFoundationTransport

let smallClient = try FoundationTransportConfiguration(
    maximumConcurrentOperations: 4,
    maximumRequestBodyBytes: 256 * 1_024,
    maximumResponseBodyBytes: 512 * 1_024,
    responseChunkBytes: 4 * 1_024,
    maximumWebSocketMessageBytes: 256 * 1_024,
    networkTimeout: 20)
```

Tune the adapter ceiling together with the REST descriptor, full multipart framing, response decoder and aggregate application budgets. Raising one ceiling does not override a lower bound elsewhere.

### Account for Foundation behavior

URLSession controls socket pooling, TLS, proxies, decompression, private buffers and protocol negotiation. The adapter does not promise an exact internal socket count or total allocator bound. Measure real process memory and workload behavior when making capacity decisions.

Foundation response metadata can collapse duplicate header fields, and duplicate request field names are rejected. Choose the NIO adapter when exact repeated fields and explicitly owned socket buffering are required. Platform-specific WebSocket availability and qualification remain separate from the shared Swift protocol's existence.

### Handle closed failure categories

``FoundationTransportFailure`` distinguishes invalid request/response, rejected admission, body/message limits, numeric native networking failures and unavailable capability. Cancellation and transport deadline failures remain recognizable. Generic formatting avoids retaining native NSError userInfo that could expose URLs or secrets.

An adapter failure does not prove an unsafe request was never submitted. Leave replay and reconciliation to the higher layer. Do not respond to an admission or network error by silently creating an unlimited collection of new adapters; that defeats the shared resource policy.

### Verify cleanup and bounds

Tests should exercise exact-boundary and over-boundary bodies, abandoned responses, duplicate headers, redirects, cancellation while a pull is suspended, repeated close and adapter replacement. Use local peers and synthetic data. Keep any live or platform qualification claims tied to actual observed evidence.
