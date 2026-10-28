[//]: # "File: Sources/DiscordCore/DiscordCore.docc/DiscordCore.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# ``DiscordCore``

Represent Discord identifiers, field presence, exact JSON and redacted credentials as portable values.

## Overview

DiscordCore supplies immutable building blocks shared by model, transport and runtime products. It depends on DiscordBits and starts no tasks or I/O. Typed snowflakes prevent accidental resource substitution; presence-aware fields distinguish omission from clearing; lossless JSON retains future data; credential wrappers keep ordinary diagnostics redacted.

Read <doc:IdentifiersAndPresence> before constructing requests, and <doc:LosslessJSONAndSecrets> before handling unknown payloads or credentials.

## Topics

### Value modeling

- <doc:IdentifiersAndPresence>
- <doc:LosslessJSONAndSecrets>

### API reference

- <doc:APIReference>
