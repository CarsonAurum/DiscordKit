[//]: # "File: Sources/DiscordModels/DiscordModels.docc/Guides/ConstructingPayloads.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# Constructing validated request payloads

Express an operation's legal fields and validate combinations before acquiring network resources.

## Overview

### Build values first

Request types differ from response types because not every returned field can be written. ``MessageCreate`` validates message creation fields and exposes a JSON representation that can incorporate actual uploaded file identifiers.

```swift
import DiscordCore
import DiscordModels

let request = try MessageCreate(content: .value("Hello from Swift"))
let json = try request.jsonValue()
if case .object(let fields) = json {
    assert(fields["content"] == .string("Hello from Swift"))
}
```

No request is sent by construction. DiscordHTTP accepts the value in a typed endpoint descriptor and performs authentication, admission and decoding when you execute it.

For partial edits, use `.absent` to preserve existing fields, `.null` only where clearing is legal and `.value` for replacement. Empty collections may explicitly remove all members, attachments, components or tags. Read the operation's initializer contract before replacing an array or nested object; nested updates are not universally deep merges.

### Validate complete combinations

Message content, embeds, components, polls, forwarding and voice attachments have interacting rules. Components V2 requires its flag and excludes traditional fields in the combinations documented by the request types. Voice messages need valid audio attachment metadata. File-only payloads cannot be validated completely until the HTTP upload layer supplies actual file IDs and content types.

``MessageComponent`` retains future response variants, while outbound factories and request validation select supported sendable layouts. A received component is not automatically a valid component for a new message. Keep custom IDs bounded and treat them as untrusted routing data on receipt; they do not carry user authorization by themselves.

Other request families follow the same pattern: type-specific channel edits, guild administration, Auto Moderation actions, scheduled-event transitions, command options, webhooks, voice-state edits and lobby/profile writes validate their own legal fields. Resource existence, permissions, application approvals and server state transitions can still fail remotely after local validation succeeds.

### Keep retries outside payload values

An enforced message nonce is a recent deduplication mechanism, not proof that arbitrary sends can be replayed safely. Descriptors declare retry safety. When a write may have reached Discord, reconcile observable state before submitting again. Payload construction neither owns retry tasks nor changes credential scope.

### Test before integrating transport

Assert exact JSON keys and values for ordinary and boundary inputs. Cover omitted/null/empty distinctions, incompatible flags, oversized content, duplicate IDs, mismatched attachment references and invalid state transitions. Then test the endpoint's path, credential selection and response separately using an injected transport. This separates local payload failures from HTTP errors and uncertain sends.
