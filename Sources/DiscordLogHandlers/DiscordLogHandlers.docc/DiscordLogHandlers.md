# ``DiscordLogHandlers``

Choose optional file, Apple unified-log and callback outputs for native SwiftLog events.

## Overview

Runtime products never select these handlers. An application opens
``DiscordFileLogSink`` explicitly, constructs value-semantic handlers and chooses
its own SwiftLog bootstrap. Standard `StreamLogHandler` supplies console output;
standard `MultiplexLogHandler` combines independent destinations and thresholds.
All dynamic Apple unified-log payloads are private by default.

## Topics

### Output ownership

- <doc:OutputOwnership>
- <doc:APIReference>
