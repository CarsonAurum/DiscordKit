# Own output lifetime and retention

Open outputs deliberately and close them after their runtime producers have joined.

## Overview

``DiscordFileLogSink`` writes bounded NDJSON synchronously with finite record,
metadata and file-retention budgets. Handler copies share the writer while keeping
thresholds and metadata independent. Oversized records are rejected; I/O failures
close admission. Inspect ``DiscordFileLogSink/snapshot()`` and sanitized diagnostics
for dropped records. The parent directory and numbered archive slots must belong
exclusively to the application. Existing content is preserved, not repaired.

``DiscordCallbackLogHandler`` invokes an application callback on the logging caller;
the callback owns concurrency, forwarding and any queue bounds. File output blocks
the caller and must stay outside realtime audio callbacks. No handler bootstraps
the process or starts a task. Attached errors contribute only an error-presence flag;
messages and application metadata still require deliberate redaction.

Use SwiftLog's console and multiplex handlers for standard streams or multiple outputs.
The Apple-only `DiscordOSLogHandler` maps all severities to unified logging and marks
the entire dynamic message/context payload private. Physical-device capture and
production throughput require separate qualification.
