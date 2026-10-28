<!--
File: Examples/DSLEvents/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Typed Gateway event modules

This independent, macro-free consumer runs only an offline synthetic `RESUMED`
dispatch. Two separately identified modules receive the existing typed payload
in declaration order through one bounded subscription. A custom selector uses the
existing dispatch decoder; unknown fields retain their exact JSON values.

```sh
swift build --package-path Examples/DSLEvents --explicit-target-dependency-import-check error
swift test --package-path Examples/DSLEvents
swift run --package-path Examples/DSLEvents
```

It reads no credentials and creates no sockets, client, cache or command registration.
The selected BotDSL graph includes Client and CommandDSL; this
example executes only the event pipelines and selects no concrete adapter or compiler
plugin. See [DSLBot](../DSLBot/README.md) for supervised offline host composition. Finite offline tests
do not qualify live Discord, complete model coverage, other platforms or capacity.
