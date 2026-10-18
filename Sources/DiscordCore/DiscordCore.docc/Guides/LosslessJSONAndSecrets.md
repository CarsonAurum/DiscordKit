# Lossless JSON and credential boundaries

Preserve unknown wire data while keeping sensitive values out of ordinary diagnostics.

## Overview

### Use the exact JSON path

``JSONValue`` stores an immutable tree, and ``JSONNumber`` stores the original numeric lexeme. Parse and serialize through the owned bounded APIs when arbitrary numeric data matters.

```swift
import DiscordCore
import Foundation

let bytes = Data(#"{"future":18446744073709551616,"ratio":1.2300}"#.utf8)
let tree = try JSONValue.parse(bytes)
let output = try tree.serialized()
let reparsed = try JSONValue.parse(output)
assert(tree == reparsed)
```

The semantic round trip keeps number spelling and Unicode scalar content. It does not retain whitespace, object key ordering or original escape choices. Serialization sorts object keys. Duplicate decoded keys fail because a dictionary cannot preserve both occurrences.

Do not decode arbitrary JSON through the Codable bridge and expect exact numbers. Decoder protocols do not expose original number tokens; DiscordCore's JSONValue Codable decoding rejects numbers rather than silently rounding them. The encoding bridge accepts only canonical decimal Int64/UInt64 integers. Use `parse` and `serialized` for complete numeric payloads.

### Set explicit resource bounds

``JSONLimits`` defaults to one MiB, 64 nested containers and 100,000 values. It enforces input/output UTF-8 bytes, depth and node count; its hard depth ceiling is 128. Invalid limits fail on use. Bound the complete document before projecting subobjects, and keep aggregate event queues bounded separately from each document.

Test malformed numeric tokens, repeated keys, nested inputs at the depth boundary, excessive bytes and large unknown integers. These checks are synchronous and own no tasks or transport resources.

### Keep credential categories distinct

``Secret`` rejects empty strings, whitespace and controls, and hides values from ordinary formatting and reflection. Typed aliases distinguish bot, bearer, interaction, webhook and confidential client secrets.

```swift
let token = try BotToken("synthetic-test-token")
let credential = Credential.bot(token)
assert(token.description == "[REDACTED]")
```

This example is local value construction; the token is not valid for Discord. Redaction is diagnostic hygiene, not encrypted storage or guaranteed memory erasure. `withUnsafeValue` deliberately exposes a string to an adapter closure, which can copy it. Restrict that boundary to the exact authenticated origin and never return secrets into logs, URLs, metrics labels or crash reports.

A credential wrapper does not prove server acceptance, scope, consent or expiry. Endpoint and host policy remain responsible for selecting the permitted credential and destination. Prefer fixed error categories over descriptions containing response bodies or user-controlled fields.
