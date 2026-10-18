# ``DiscordUnixPlatform``

Connect bounded Unix-domain byte streams through the portable IPC contract.

## Overview

``UnixIPCTransport`` opens an explicitly selected absolute socket path. It preserves byte order but does not attach application message boundaries, discover Discord, authorize a host or perform a local RPC handshake. The adapter is compiled for native non-Windows, non-WASI hosts. Windows named pipes require a separate implementation.

Begin with the guides for ownership and composition, then use the complete type index to explore each declaration and its members. Examples name the additional products they import so you can keep your package dependency graph explicit.

## Topics

### Guides

- <doc:LocalStreams>

### Core APIs

- ``UnixIPCTransport``
- ``UnixIPCFailure``

### Complete API reference

- <doc:APIReference>
