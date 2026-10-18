# Identifiers, timestamps and field presence

Keep exact identity and represent omitted, cleared and supplied fields separately.

## Overview

### Preserve all identifier bits

``Snowflake`` is an unsigned 64-bit value tagged with a resource type. `UserID`, `ChannelID`, `GuildID` and the other aliases cannot be interchanged accidentally. JSON encodes them as decimal strings. Parsing rejects signs, whitespace, non-ASCII digits and overflow; zero is allowed for pagination boundaries.

```swift
import DiscordCore

let user = UserID("18446744073709551615")!
let channel = ChannelID(rawValue: 42)
assert(user.rawValue == UInt64.max)
assert(channel.description == "42")
let boundary = try MessageID(timestampMilliseconds: Snowflake<MessageTag>.epochMilliseconds)
assert(boundary.rawValue == 0)
```

These synthetic identifiers do not identify existing resources. A snowflake timestamp is encoded metadata, not a trustworthy server clock or proof of creation. `ExternalIdentifier` deliberately retains an opaque provider string, including leading zeroes; do not parse external account keys as Discord snowflakes.

### Distinguish three update states

``Field`` represents `.absent`, `.null` and `.value`. Omission usually preserves the server's existing value in a partial update; explicit null requests clearing only where that endpoint permits it. Empty strings and arrays are values and may have different meanings again.

```swift
let preserve: Field<String> = .absent
let clear: Field<String> = .null
let replace: Field<String> = .value("new value")
```

When writing your own Codable payload, use keyed-container `encodeField` and `decodeField`. A single-value encoder cannot omit the containing object's key. `decodeIfPresent` collapses missing and null, so it is unsuitable when the distinction matters. Do not encode the same key twice expecting `.absent` to remove its earlier value.

``Nullable`` is different: the field is required, but its value can be null. A synthesized model with a `Nullable` property rejects a missing key. Select the representation from the actual resource contract rather than making every property optional.

### Treat timestamps as domain values

``DiscordTimestamp`` preserves supported timestamp precision without using a display string as an ordering key. Use a monotonic `Clock` for local deadlines and elapsed time. Use trusted wall time for persisted token expiry and entitlement time windows. A process-local monotonic instant cannot be persisted across a restart.

### Test the distinctions

For every partial payload, test missing, null, nonnull and invalid-type cases independently. Include identifiers above the signed 64-bit range, canonicalized leading zeroes and overflow. When a nullable property is required, deleting its key must fail even though setting it to null succeeds.
