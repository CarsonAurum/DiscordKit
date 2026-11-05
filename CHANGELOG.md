<!--
File: CHANGELOG.md
Created by Carson Rau.
Copyright (c) 2026 Aurum Studios.
https://aurum-studios.com
-->

# Changelog

## Unreleased

### Discord API documentation update — 2026-11-05

- Add guild and channel member/role permission endpoints, including optional
  channel masking and exact arbitrary-width permission responses.
- Add attachment/embed content-scanning flags and typed scan metadata for
  component media, including results delivered in later message updates.
- Support Components V2 messages when starting forum and media threads.
- Recognize channel-position and role-position audit events, and document merged
  audit counts and Gateway notification behavior.
- Support audit reasons when reordering guild channels. Stop sending the removed
  channel-position `flags` field; the deprecated initializer accepts only absent
  flags. Use channel modification for supported flag changes.
- Stop sending audit reasons for single-message deletion. The deprecated overload
  ignores its reason; use the overload without that argument. Bulk deletion keeps
  its documented audit-reason support.
- Refresh OAuth issuer, linked-role, guild availability, voice-status and native
  Social SDK guidance against the official documentation. Preserve existing
  access boundaries and the November 16 channel-obfuscation transition.
- Record pinned source hashes, supplemental parity contracts, migration notes,
  regression coverage and updated API documentation.

### Initial publication

Original DiscordKit material is now licensed under the [Apache License, Version
2.0](LICENSE), allowing use, modification and redistribution in open source and paid
products with the required license and attribution notices. [NOTICE](NOTICE)
credits Carson Rau and Aurum Studios; third-party material retains its own terms.

DiscordKit's initial publication includes independently adoptable Swift libraries
for Discord applications and bots:

- Typed REST models, validated requests, bounded uploads and explicit workflows for
  messages, channels, guilds, moderation, expressions, events, applications, users,
  webhooks, interactions, monetization and game-account resources.
- Supervised sharded Gateway sessions, typed dispatches, bounded subscriptions and
  ordered handlers, optional entity caching and permission resolution.
- Signed HTTP interactions, explicit response ownership, command routing and
  registration reconciliation.
- Modular Swift authoring for typed commands, messages, components, policies,
  Gateway events and bot applications, with an optional separate macro package.
- OAuth authorization and token ownership, public game-account services and
  server-authoritative entitlement verification.
- Local RPC, Certified Devices, an Activity client and browser bridge, and
  explicit Social provider composition.
- Optional media processing, Opus coding, voice transport, MLS and DAVE products.
- Structured diagnostics, independently compiled examples and DocC guides and
  tutorials.

REST/Gateway v10, Voice v8, RPC v1, MLS 1.0/ciphersuite 2 and DAVE v1 are versioned
independently of the package. Platform, live-service, device, cryptographic review,
interoperability and production-capacity limitations are described in the
[platform](Docs/PlatformSupport.md) and [voice](Docs/Voice.md) guides. This entry
describes unpublished source and does not establish a release tag or completed
external qualification.
