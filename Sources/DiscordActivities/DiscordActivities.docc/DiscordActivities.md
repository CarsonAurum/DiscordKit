# ``DiscordActivities``

Coordinate a Discord Activity host through an authenticated, bounded message bridge.

## Overview

``ActivityClient`` implements Activity protocol v1 over an injected ``ActivityTransport``. It starts no I/O until explicit `start()`. The embedding browser adapter authenticates the exact message source and origin; parsing Discord-injected URL parameters does not authenticate messages. An Activity requires a real authorized Discord host, and this module does not create one.

Begin with the guides for ownership and composition, then use the complete type index to explore each declaration and its members. Examples name the additional products they import so you can keep your package dependency graph explicit.

## Topics

### Guides

- <doc:HostAuthentication>
- <doc:BrowserBridge>
- <doc:HostCommands>

### Core APIs

- ``ActivityClient``
- ``ActivityTransport``
- ``ActivityHostParameters``
- ``ActivityRequests``
- ``ActivityRequest``
- ``ActivityClientLimits``
- ``ActivitySubscription``
- ``ActivityEventPayload``

### Complete API reference

- <doc:APIReference>
