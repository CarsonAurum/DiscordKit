# DiscordKit

DiscordKit is the foundation of a modular, Swift-native Discord application and
bot library. The current runtime is a `hello()` scaffold. REST, Gateway,
interactions, OAuth2, voice, RPC, Activities, Social and commerce integrations are
not implemented.

The first roadmap milestone establishes architecture, platform capabilities,
dependency policy, a versioned parity inventory and explicit feasibility blockers.
It does not constitute a working Discord client. An available API, a planned
target or an unavailable-capability stub never counts as implemented support.

## Build and test

Use Swift 6.4 or newer. The package preserves `ApproachableConcurrency` and uses
an explicit nonisolated default for library and test declarations. See the
[concurrency policy](Docs/Concurrency.md) for the distinction between default
isolation and the executor on which an async operation runs.

Run from the repository root:

```sh
swift build
swift test
```

The runtime scaffold has no Discord behavior to exercise. Planning and inventory
validation must report their own coverage; passing the package tests alone does
not establish protocol parity or platform runtime qualification.

## Planned consumer experience

- REST services work without a Gateway connection or voice dependencies.
- Bot clients supervise heartbeats, reconnect/resume, rate limits and socket
  ownership through an async run operation.
- HTTP interactions work without loading Gateway or voice.
- Commands and routers provide conveniences over complete typed requests.
- Optional voice APIs own the media protocol and expose join, frames and leave.
- Platform and access restrictions produce explicit capability information.

These contracts describe future work. Only the current package product,
`DiscordKit`, exists today; feature products are introduced with real code.

## Scope and constraints

The roadmap includes backend APIs, Gateway, voice/media, OAuth2, local RPC,
certified devices, Activities, Social capabilities and commerce. It targets all
Swift platforms with capability-specific qualification. A compiler target does
not prove sockets, background execution, audio capture or a Discord host exists
on that platform.

Only approved Apple-origin or official Swift-project package families and their
normal maintained transitive/bundled implementations are permitted. Discord's
distributed native runtime is outside that policy. Missing public wire contracts
remain blockers even when Discord publishes an SDK method signature.

Discord applications are registered in the Developer Portal. DiscordKit will use
documented application and authentication APIs; application creation and bot-token
provisioning are not invented SDK endpoints. See Discord's
[getting started guide](https://docs.discord.com/developers/quick-start/getting-started).

## Project records

- [Architecture and API conventions](Docs/Architecture.md)
- [Concurrency and ownership](Docs/Concurrency.md)
- [Dependency policy and candidate releases](Docs/Dependencies.md)
- [Platform support and feasibility](Docs/PlatformSupport.md)
- [Parity inventory and evidence](Docs/Parity/README.md)
- [Contribution requirements](CONTRIBUTING.md)
- [Change history](CHANGELOG.md)

Protocol evidence is dated and versioned separately from library releases.
Current support claims must come from validated inventory records and linked
tests, rather than the size of the roadmap.
