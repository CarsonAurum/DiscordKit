<!--
File: Examples/LoggingApp/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Offline logging consumer

```sh
swift build --package-path Examples/LoggingApp
swift test --package-path Examples/LoggingApp
swift run --package-path Examples/LoggingApp
```

The standalone process bootstraps SwiftLog exactly once. It multiplexes an info-level
console with a trace-level rotating NDJSON file, injects a dynamic metadata provider,
applies dotted component thresholds and scoped context, emits semantic `info`/`notice`
events and triggers one synthetic transport deadline inside a correlated operation.
It checks the closed file for semantic and subsystem records, provider/scoped context,
trace/span correlation and monotonic completion timing,
then removes its temporary directory. No credentials, network or devices are used.
Runtime products do not select output handlers. See [logging adoption](../../Docs/Logging.md).
