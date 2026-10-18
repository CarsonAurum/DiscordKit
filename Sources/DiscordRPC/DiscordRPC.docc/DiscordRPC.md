# ``DiscordRPC``

Speak local desktop RPC v1 with bounded framing, correlated commands and explicit sessions.

## Overview

This product controls a connected Discord desktop host through an injected local connector. It is separate from bot Gateway, REST, Activity iframe messaging and native Social runtime APIs. ``RPCClient`` starts no tasks or I/O during construction. Connect, authorize/authenticate, subscribe and close explicitly, using a registered application and the scopes required by each operation.

Begin with the guides for ownership and composition, then use the complete type index to explore each declaration and its members. Examples name the additional products they import so you can keep your package dependency graph explicit.

## Topics

### Guides

- <doc:DesktopSessions>
- <doc:CommandsAndSubscriptions>

### Core APIs

- ``RPCClient``
- ``RPCConnector``
- ``RPCIPCConnector``
- ``RPCWebSocketConnector``
- ``RPCRequest``
- ``RPCResponsePayload``
- ``RPCEventPayload``
- ``RPCFrameDecoder``

### Complete API reference

- <doc:APIReference>
