# Macro-authored HTTP commands

Run a signed synthetic `/ping` without credentials, sockets or registration:

```sh
swift run --package-path Examples/DSLCommands DSLCommands --offline
```

The example compiles actual `@CommandArguments` and `@SlashCommand` expansions,
verifies Ed25519 ingress and asserts one ephemeral builder-authored `Pong!` callback
with an explicit empty mention-parse list and no reply-author notification. The
synthetic signing key is fixed test material. It never authenticates to Discord.

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

Part 15F's `FamilyExamples.swift` also executes a complete slash invocation, an empty
nested group/subcommand, macro-authored user/message context menus, partial typed
autocomplete, an exact-ID button and a label-wrapped typed modal submission. Every
case passes genuine synthetic Ed25519 verification and checks exact callback JSON.
The component and modal deliberately share an ID in separate namespaces. All target
IDs and keys are synthetic; the example constructs no registration client and never
contacts Discord. Run the same offline mode or `swift test --package-path Examples/DSLCommands`.
These checks establish local protocol composition only; live registration/rendering,
other platforms and Gateway hosts remain separate.

Part 15G's `PolicyExamples.swift` adds signed allow/deny exchanges with injected
authorization, `audit >>> metrics` ordering and one shared fixed-count concurrency
authority. Construction executes no service checks; denial sends an explicit ephemeral
message before middleware/handler work. The example asserts exact successful traversal,
denial effects and zero active permits after cleanup. See the
[policy guide](../../Docs/CommandPolicies.md) for finite bounds, cancellation and response ownership.
