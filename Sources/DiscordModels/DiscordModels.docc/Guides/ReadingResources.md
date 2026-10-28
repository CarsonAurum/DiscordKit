[//]: # "File: Sources/DiscordModels/DiscordModels.docc/Guides/ReadingResources.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Reading resources without losing future data

Decode immutable snapshots while preserving optionality, unknown fields and future discriminators.

## Overview

### Start from a complete bounded object

Resource types such as ``User`` expose a `data:limits:` initializer. They parse through DiscordCore's lossless JSON path rather than a floating-point intermediate.

```swift
import DiscordModels
import Foundation

let bytes = Data(#"{"id":"18446744073709551615","username":"reader","discriminator":"0","global_name":null,"avatar":null,"future_flag":9007199254740993}"#.utf8)
let user = try User(data: bytes)
assert(user.id.rawValue == UInt64.max)
assert(user.rawFields["future_flag"] != nil)
```

Required nullable keys still have to exist. In this example, `global_name` and `avatar` may be null, while deleting either key is invalid. Optional response properties use `Field` to retain absent, null and value as the contract permits. Reading an omitted OAuth property does not establish that its scope was granted or that the user lacks that feature.

### Inspect known values and retain unknown values

Many enums use the open `RawValue` wrapper from DiscordCore. Switch on a known value where available, and provide a deliberate fallback for future values. Unknown numeric types and unknown object keys survive decoding. Do not coerce an unknown channel, interaction, entitlement or component type into a familiar default.

`rawFields` is useful for forwarding or investigating newly documented fields, but it can contain personal information, tokens and user-controlled text. The models' ordinary descriptions are redacted; directly printing `rawFields` bypasses that protection. Bound any explicit evidence you retain and authorize access to it separately.

### Separate full snapshots from sparse events

REST resources and Gateway updates serve different purposes. A partial update can omit fields that must remain untouched in a cache. A guild's embedded child arrays need not describe every member, channel or role. Preserve provenance, field completeness, nullability and ordering when deriving state; the DiscordCache product supplies those policies.

``GatewayDispatch`` lets you decode known dispatch names while retaining unknown dispatch data. Decode only the payload needed by the consumer, handle malformed known payloads explicitly and retain the bounded original event when recovery needs it. Parsing a payload does not establish current permissions, membership, authenticated provenance or durable delivery.

### Build useful fixtures

Use realistic required fields and synthetic identifiers. Test missing required keys, wrong types, allowed nulls, future discriminators, unknown nested fields and exact large numeric values. Test response redaction separately from intentional direct property access. A local decoding fixture validates the model contract; it does not verify a live application's scopes or Discord's current response policy.
