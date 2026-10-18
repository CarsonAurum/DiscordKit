# Coordinate public Social providers

Model explicit consent and host capabilities without inventing native SDK wire.

```sh
swift build --package-path Examples/SocialApp
swift run --package-path Examples/SocialApp
```

The [SocialApp consumer](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/SocialApp)
activates a synthetic scope, synchronizes one local relationship, mutes synthetic
PCM and awaits closure. It opens no provider, device or credential-bearing session.
The graph excludes Gateway/Client/Cache, Voice/MLS/DAVE and concrete adapters.

DiscordSocial composes narrow owned HTTP/RPC/Activity providers. User consent,
bot authority, host capability and local media are distinct. Keep observations
scoped by application/account/consent generation, bound relationships and queues,
and explicitly resynchronize on stale or overflowed state. PCM controls do not
implement a platform device route or a native call.

The exhaustive SDK/Commerce/mobile catalog marks unsupported, approval-gated and
unpublished-contract rows. A public SDK signature or successful local provider
test cannot establish an absent protocol. Never distribute a native Discord
runtime dependency or guess undocumented Commerce wire to make a parity row pass.
See the [Social contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Social.md).
