[//]: # "File: Sources/DiscordApplePlatform/DiscordApplePlatform.docc/DiscordApplePlatform.md | Created by Carson Rau. | Copyright (c) 2026 Aurum Studios. | https://aurum-studios.com"

# ``DiscordApplePlatform``

Own Apple transport lifecycle policy and bounded native PCM capture and playback.

## Overview

Use ``AppleLifecycle`` to apply app-reported lifecycle policy to closeable resources, and ``AppleAudioDevice`` for explicit native audio ownership on supported Apple SDKs. The lifecycle owner does not observe UI frameworks or grant background execution. Native audio has its own MainActor, permission, route and queue contracts; capability policy alone does not establish hardware qualification.

Begin with the guides for ownership and composition, then use the complete type index to explore each declaration and its members. Examples name the additional products they import so you can keep your package dependency graph explicit.

## Topics

### Guides

- <doc:LifecycleOwnership>
- <doc:NativeAudio>

### Core APIs

- ``AppleLifecycle``
- ``AppleHost``
- ``AppleLifecycleState``
- ``AppleAudioDevice``
- ``AppleAudioConfiguration``
- ``AppleAudioBackend``
- ``AppleAudioEndpoint``

### Complete API reference

- <doc:APIReference>
