[//]: # "File: Sources/DiscordLogHandlers/DiscordLogHandlers.docc/DiscordLogHandlers.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# ``DiscordLogHandlers``

Choose optional file, Apple unified-log and callback outputs for native SwiftLog events.

## Overview

Runtime products never select these handlers. An application opens
``DiscordFileLogSink`` explicitly, constructs value-semantic handlers and chooses
its own SwiftLog bootstrap. Standard `StreamLogHandler` supplies console output;
standard `MultiplexLogHandler` combines destinations. Wrap individual outputs with
``DiscordLevelFilterLogHandler`` to preserve minimum severities when logger thresholds change.
All dynamic Apple unified-log payloads are private by default.

## Topics

### Output ownership

- <doc:OutputOwnership>
- <doc:APIReference>
