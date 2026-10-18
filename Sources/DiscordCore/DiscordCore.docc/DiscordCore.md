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
