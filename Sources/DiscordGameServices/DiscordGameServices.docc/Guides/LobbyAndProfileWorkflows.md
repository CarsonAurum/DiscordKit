[//]: # "File: Sources/DiscordGameServices/DiscordGameServices.docc/Guides/LobbyAndProfileWorkflows.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Reducing lobby and game-profile writes

Use supplied snapshots for deliberate no-ops while preserving full replacement and partial bulk outcomes.

## Overview

### Avoid redundant channel linking

``GameServiceOperations`` provides `linkIfChanged` over a caller-supplied Lobby snapshot. A matching linked channel returns nil without a hidden GET. A differing/missing projection returns the existing typed bearer-authenticated link descriptor.

The caller still establishes current membership, sdk.social_layer consent and CanLinkLobby authority. A stale matching snapshot can suppress a write that is needed after an external change; decide whether to refresh first. Nil is a comparison result, not a guarantee that Discord still has the desired state.

### Compare explicit profile fields only

`profileIfChanged` validates the provider-issued user key and typed request before checking requested root fields against the supplied profile. Omitted/equal fields return nil. Changed fields return the same typed unsafe update used by DiscordHTTP.

Including profile `data` replaces the complete statistics object. Missing nested fields are removed; an empty object clears data. The helper never merges old statistics behind the caller's back. If you intend to preserve a statistic, include it in the complete desired data object after choosing a trustworthy source snapshot.

Profile bot ownership and target-user application_identities.write consent remain upstream requirements. Exact numeric statistics preserve decimal spelling. Public media URLs are configuration, and local URL validation cannot prove that Discord can fetch them.

### Bound incremental membership updates

`linkedLobbyMembers` builds the existing finite ``GameServiceOperations`` membership plan through typed HTTP values. Inputs are explicit unique upserts/removals; documented chunks contain at most 25 entries. The plan executes sequentially and retains input correlation, acknowledged progress, silent omissions and removals.

An absent response member may be a silently dropped upsert, not proof of removal or admission. A failed later chunk leaves earlier changes applied. Do not convert a modify-lobby full-replacement array into incremental chunks; those operations have different semantics. No helper creates a hidden reconciliation timer or repairs omissions automatically.

### Separate lobby delivery from forwarding

A linked channel can fail to receive a forwarded message even when the lobby message succeeded. Treat lobby acknowledgement, channel forwarding, membership and user visibility as distinct observations. The recent-message API has a finite limit but no documented history cursor to invent.

### Test useful no-op and failure behavior

Assert matching snapshots produce zero descriptors/sends, changed fields produce exactly the expected descriptor, invalid external keys still fail on otherwise equal input and full stats are never deep-merged. For member plans, assert exact chunk boundaries, returned/dropped correlation, explicit removals, failure stop and cancellation/uncertainty. Use synthetic snapshots and injected executors without Discord credentials.

See the [lobby/profile contract](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/SocialGame.md) for credential scopes and replacement details.
