# Offline logging consumer

```sh
swift build --package-path Examples/LoggingApp
swift test --package-path Examples/LoggingApp
swift run --package-path Examples/LoggingApp
```

The standalone process bootstraps SwiftLog exactly once. It multiplexes an info-level
console with a trace-level rotating NDJSON file, injects a dynamic metadata provider,
emits application `info`/`notice` events and triggers one synthetic transport deadline.
It checks the closed file for both semantic and subsystem records and provider context,
then removes its temporary directory. No credentials, network or devices are used.
Runtime products do not select output handlers. See [logging adoption](../../Docs/Logging.md).
