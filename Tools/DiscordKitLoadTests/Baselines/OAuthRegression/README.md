<!--
File: Tools/DiscordKitLoadTests/Baselines/OAuthRegression/README.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# OAuth HTTP regression measurements

Six release HTTP policy profiles ran on macOS arm64 with Swift 6.4. The normal
and tenfold offered-cohort burst profiles passed their configured latency/RSS,
bounded resource, request-reduction, identity participation and cleanup checks.
Normal runs served 2,000 / 10,000 / 20,000 logical requests with no refusals.
Burst refusals are intentional bounded admission, not retries or a latency promise.
All active, queued, coalesced-flight and cache-entry counters returned to zero.

These finite offline scripts use zero sockets or credentials. They measure the
shared HTTP execution policy used by the new products; they do not execute OAuth
consent, token refresh/storage, publisher accounts, OS UI, Activity payment or
Social Commerce. Logical served-user profiles do not allocate a user population
or establish live Discord, distributed/fleet or sustained-soak qualification.

The environment record includes exact executable and ordered source SHA-256
fingerprints, the pre-commit dirty source basis and actual host/toolchain metadata.
Root Swift Testing separately validates new OAuth, account and entitlement behavior.
Reproduce after a release harness build using:

```sh
python3 Tools/DiscordKitLoadTests/scripts/record_baseline.py --scenario http --output-dir Tools/DiscordKitLoadTests/Baselines/OAuthRegression
```
