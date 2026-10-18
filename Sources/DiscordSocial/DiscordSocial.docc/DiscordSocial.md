# ``DiscordSocial``

Compose consented social features from explicit HTTP, desktop RPC, Activity and local PCM providers.

## Overview

``SocialClient`` coordinates narrow providers with application-verified account consent. It does not load a native Discord runtime, infer user authority from a bot token or automatically fall back between hosts. Construction starts no tasks, authorization UI, sockets, devices or persistence. Public protocol equivalents retain their actual scope; they do not imply native SDK parity.

Begin with the guides for ownership and composition, then use the complete type index to explore each declaration and its members. Examples name the additional products they import so you can keep your package dependency graph explicit.

## Topics

### Guides

- <doc:ConsentAndProviders>
- <doc:ObservationsAndAudio>

### Core APIs

- ``SocialClient``
- ``SocialScope``
- ``SocialHTTPProvider``
- ``SocialHTTPApplicationProvider``
- ``SocialRPCProvider``
- ``SocialActivityProvider``
- ``SocialRelationshipStore``
- ``SocialAudioControls``
- ``SocialAudioInputMonitor``

### Complete API reference

- <doc:APIReference>
