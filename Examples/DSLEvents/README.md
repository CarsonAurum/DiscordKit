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

It reads no credentials and creates no sockets, client, cache, command registration,
concrete adapter or compiler-plugin dependency. Its async entry point owns only the
event pipelines; a supervised bot application remains Part 15I. Finite offline tests
do not qualify live Discord, complete model coverage, other platforms or capacity.
