[//]: # "File: Sources/DiscordCache/DiscordCache.docc/Guides/PermissionCalculations.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Calculating permissions from complete facts

Resolve the implemented permission arithmetic or return explicit indeterminacy.

## Overview

### Supply facts rather than a cached conclusion

``PermissionResolver`` accepts ``PermissionGuildState``, ``PermissionMemberState`` and optional channel/parent facts. Each captures missing data explicitly. A nil role assignment set, unknown timeout or missing thread metadata is not equivalent to an empty set or false.

```swift
import DiscordBits
import DiscordCache
import DiscordCore

let guildID = GuildID(rawValue: 1)
let userID = UserID(rawValue: 2)
let guild = PermissionGuildState(id: guildID, ownerID: userID)
let member = PermissionMemberState(guildID: guildID, userID: userID,
    roleIDs: [], timeoutActive: false)
let result = PermissionResolver.resolve(guild: guild, member: member)
switch result {
case .resolved(let permissions):
    assert(permissions.unrestricted)
case .indeterminate:
    assertionFailure("The supplied owner facts suffice for this local calculation")
}
```

This synthetic owner example calculates supplied facts only. It does not authorize a Discord request or validate current ownership.

### Retain unknown bits without inventing all permissions

The resolver combines the everyone role and assigned roles, applies owner/administrator bypass and resolves documented channel/member overwrites and implicit denials. Arbitrary-width bitsets preserve future bits. Owner/administrator bypass is represented explicitly by `unrestricted`, not by a finite mask pretending to contain every future permission.

Threads use their matching parent channel's overwrites. Private-thread membership, archive/lock state and timeout restrictions need the required facts. Categories do not silently substitute inherited overwrites for an arbitrary child. Unknown/obfuscated channel types and inconsistent scopes can yield an indeterminate result.

``PermissionResolutionLimits`` bounds role count, overwrite count, individual mask width and aggregate mask work before expensive operations. Bound all supplied input, including irrelevant entries; callers cannot bypass resource limits merely by selecting a single relevant role.

### Treat indeterminacy as a request for facts

``PermissionResolution`` separates a resolved calculation from a ``PermissionIndeterminacy`` reason. Refresh missing facts or reject the local operation according to application policy. Do not map missing data to an allow result. For UI hints, explain uncertainty without silently claiming the user has a permission.

Even a resolved result leaves role hierarchy, MFA, verification, screening, application-command permissions, quarantine, live voice state and endpoint-specific rules outside its arithmetic. Data can become stale immediately. Discord's response remains authoritative for the attempted operation.

### Test meaningful combinations

Cover owner/administrator bypass, everyone plus several roles, overwrite ordering, unknown high bits, member-specific allow/deny, private/public threads, timeout, missing parents, duplicate overwrite targets, cross-guild facts and every resource-bound failure. Use table-driven Swift Testing cases; no network calls or sleeps are required for this pure calculation.
