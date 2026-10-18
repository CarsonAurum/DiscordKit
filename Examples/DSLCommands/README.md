# Macro-authored HTTP commands

Run a signed synthetic `/ping` without credentials, sockets or registration:

```sh
swift run --package-path Examples/DSLCommands DSLCommands --offline
```

The example compiles actual `@CommandArguments` and `@SlashCommand` expansions,
verifies Ed25519 ingress and asserts one ephemeral `Pong!` callback. The synthetic
signing key is fixed test material. It never authenticates to Discord.

To opt into a local listener, supply your application ID and public verification
key through `DISCORD_APPLICATION_ID` and `DISCORD_PUBLIC_KEY`, then run with
`--listen`. `DISCORD_HTTP_PORT` defaults to 8080. The listener binds loopback only;
deployments supply HTTPS termination and preserve original signed request bytes.
Cancel the run to close the owned listener and await admitted handlers.

Register `/ping` separately using the existing `CommandApplication.synchronize`
with a caller-owned REST client, or your application registration tooling. Ordinary
construction and serving make zero command-registration requests. This example
does not read a bot token or enable automatic defer. It selects no Gateway, Client,
Cache, OAuth, voice or Social product; macros and the concrete listener are chosen
by this application rather than by the runtime DSL product.

The evidence is local/offline. Authorized Discord behavior, other platforms,
deployment security and DSL capacity remain separately qualified gates.
