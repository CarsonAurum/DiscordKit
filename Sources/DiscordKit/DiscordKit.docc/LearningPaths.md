# Choose a learning path

Follow an ordered route from local values to a deployed consumer or host integration.

## Overview

### Learn the foundations

Read <doc:GettingStarted>, then open DiscordCore's value and JSON guides from <doc:TableOfContents>. Learn tagged snowflakes, absent/null/value updates, unknown raw values, bounded JSON and redacted credentials before handling real payloads. Continue to DiscordModels for response projections and validated request bodies, then DiscordTransport for cancellation, deadlines and pull-based bodies.

### Build a bot

1. Complete <doc:DefineACommand> to validate payloads locally.
2. Follow <doc:BuildARESTConsumer> to compose REST execution and cleanup.
3. Follow <doc:SuperviseABot> to subscribe before starting a bot.
4. Read DiscordHTTP's rate, retry, pagination and resource-family guides.
5. Read DiscordGateway and DiscordClient lifecycle guides, then DiscordCache's freshness and permission guides if retaining state.
6. Use <doc:TestingApplications>, <doc:ErrorHandling> and <doc:DeploymentState> before operating the application.

### Serve HTTP commands and OAuth

1. Validate command definitions with <doc:DefineACommand>.
2. Work through <doc:ServeSignedInteractions>; retain original signed bytes and one response owner.
3. Read DiscordCommands routing/reconciliation and DiscordInteractions acknowledgement/defer guides.
4. Follow <doc:PrepareOAuth> for state, issuer and PKCE ownership.
5. Read DiscordOAuth storage/refresh/device-polling guides and the GameServices/Commerce guides for backend account and entitlement policy.

### Integrate a host

1. Choose <doc:PrepareDesktopRPC> for the local desktop host or <doc:ComposeAnActivity> for a Discord-owned iframe.
2. Read the corresponding RPC/Activities guides and the browser bridge example.
3. Use <doc:CoordinateSocialState> for consent-scoped provider composition.
4. Add CertifiedDevices or Apple audio only when your actual host supplies native identifiers and device permission/routing.

### Explore media and encrypted voice

1. Complete <doc:ProcessOfflineVoice> with synthetic PCM and public fixture keys.
2. Read DiscordMedia's format, resampling, pacing and stream guides.
3. Read DiscordVoiceCodecs for packet framing, modes, loss, FEC and codec limits.
4. Read DiscordVoiceCrypto for key/counter ownership and authenticated RTP headers.
5. Read DiscordVoice for sessions, discovery, SSRC authority, jitter and recording.
6. Add DiscordMLS and DiscordDAVE only after understanding participant identity trust, authenticated transitions and replay/counter bounds.

Offline examples teach contracts. A real Discord host, physical device, independent cryptographic review and complete-client interoperability each need their own evidence.

### Browse all tutorials

<doc:DiscordKitTutorials> presents these exercises as a DocC tutorial table of contents. <doc:ExampleCookbook> maps each tutorial to its source package, supporting tests and exact build/run behavior.
