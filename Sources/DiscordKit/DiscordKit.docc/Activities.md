[//]: # "File: Sources/DiscordKit/DiscordKit.docc/Activities.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Embed an Activity in its Discord host

Keep browser source/origin authentication and the confidential backend separate.

```sh
swift build --package-path Examples/ActivityHost
swift test --package-path Examples/ActivityHost
node --test Browser/DiscordActivityBridge/*.test.mjs
```

The [ActivityHost consumer](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/ActivityHost)
compiles a portable Activities client and separate OAuth/Commerce backend target.
The browser bridge has no npm runtime dependency. Configure the public client ID,
approved URL mapping and exact Discord host origin, then run inside Discord's
actual Activity iframe. A standalone web page cannot provide the host.

The bridge checks both message source and origin. Explicit command/nonce
correlation and bounded subscriptions own pending work. Authorization code exchange
and entitlement verification use a separately authenticated HTTPS backend with
CSRF/replay protection and server-derived user/SKU expectations. Keep the client
secret out of the iframe/mobile bundle. A purchase response alone does not grant
an entitlement.

The Node tests simulate a host and Swift tests exercise local backend policy.
Neither qualifies Discord Web/iOS/Android embedding, real purchases, Swift/browser
bindings or native browser policy. See the
[Activities contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Activities.md).
