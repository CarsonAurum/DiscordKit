# ``DiscordNIOTransport``

Run bounded HTTP, WebSocket, UDP and HTTP ingress adapters over SwiftNIO.

## Overview

Choose this product at the edge of an application that already uses portable transport contracts. HTTP and WebSocket owners allocate an event-loop thread during initialization, then open sockets only when explicitly requested. UDP sockets and HTTP listeners begin at their asynchronous `bind` calls. Close every owner explicitly.

Transport limits cover connections, messages and bytes. Authentication, shared credential rate admission, Discord protocol policy and retry decisions belong to the caller's higher-level product. The adapters do not turn an uncertain write into an automatic replay.

Begin with the guides for ownership and composition, then use the complete type index to explore each declaration and its members. Examples name the additional products they import so you can keep your package dependency graph explicit.

## Topics

### Guides

- <doc:NetworkAdapters>
- <doc:ServerAndDatagramIO>

### Core APIs

- ``NIOHTTPTransport``
- ``NIOHTTPConfiguration``
- ``NIOWebSocketTransport``
- ``NIOWebSocketConfiguration``
- ``NIODatagramTransport``
- ``NIOHTTPIngress``
- ``TLSPolicy``

### Complete API reference

- <doc:APIReference>
