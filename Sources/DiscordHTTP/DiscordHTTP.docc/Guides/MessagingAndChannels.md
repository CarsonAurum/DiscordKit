# Messages, polls, channels and threads

Choose typed resource operations while retaining permission, content and replacement semantics.

## Overview

### Send a deliberate message

``MessageEndpoints`` covers history, individual reads, creation/editing/deletion, crossposts, reactions, search and pin operations. Build a DiscordModels request, then execute the descriptor through the shared REST client.

```swift
import DiscordCore
import DiscordHTTP
import DiscordModels

let channelID = ChannelID(rawValue: 42)
let request = try MessageCreate(content: .value("Hello"),
    allowedMentions: .value(MessageAllowedMentions(parse: [])))
let create = try MessageEndpoints.create(channelID: channelID, request: request)
let history = try MessageEndpoints.history(channelID: channelID, limit: 25)
// Execute `create` and `history` using your injected RESTClient.
```

These synthetic descriptors send nothing. Explicit allowed-mention policy is useful when displaying untrusted text. Do not infer safety from a user-provided string containing a role or user mention.

History requires applicable channel visibility/history permissions; missing history permission can produce an empty list. MESSAGE_CONTENT eligibility can redact content, embeds, attachments and components or prevent search. Empty or redacted results are not proof that a resource does not exist. Reading a voice channel may require CONNECT in addition to history permissions.

### Handle specialized message workflows

Search has typed query filters and can report indexing rather than results. Use its bounded polling/traversal helper instead of assuming a 202 body is a message array. Current pins retain their timestamp cursor and explicit continuation; deprecated pin APIs stay marked separately. Reaction emoji are supplied unescaped so path encoding happens exactly once. Poll voter traversal uses its own after-user cursor; ending a poll and finalizing results are separate observations.

Bulk deletion validates its documented count/age constraints. A nonce can reduce recent duplicate sends, but an enforced nonce does not make an ambiguous mutation automatically replayable. Uploads and attachment replacement are explained in <doc:UploadsPaginationAndWorkflows>.

### Respect channel-type constraints

``ChannelEndpoints`` contains channel edits, permission overwrites, invites, follows, typing, recipients, thread creation/membership/archive operations and forum/media messages. Payload validation uses explicit channel types; a forum's tags/default reaction and a voice channel's settings are not interchangeable fields.

Thread creation from a message, standalone private/public threads and forum/media starts have distinct descriptors and payloads. Archived traversal preserves the operation's cursor and membership requirements. Adding/removing thread members and editing permission overwrites remain explicit writes subject to current Discord permissions; decoding a channel snapshot grants none.

A group-DM recipient operation uses its specific authorized user-token contract. This does not provide a general user session or a native Social SDK. Type-specific routing and credentials still apply inside a REST-only application.

### Test the wire and user-visible outcomes

Assert route encoding, exclusive before/after/around cursors, reaction emoji encoding, 204 decoding, unknown message fields, V2 layouts and exact multipart metadata. Exercise permission errors, known 404s, redacted/empty history, search indexing, continuation boundaries and uncertain sends. Refer to the [REST catalog](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/RESTCatalog.md) and [channel guide](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/Channels.md) for the operation-by-operation contract.
