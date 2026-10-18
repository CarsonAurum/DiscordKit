# ``DiscordMLS``

Establish bounded MLS 1.0 ciphersuite-2 epochs with trusted membership and owned key material.

## Overview

``MLSKeyPackageOwner`` and ``MLSGroup`` implement the restricted group-handshake profile used by DAVE v1. They own key packages, signed proposals/commits, TreeKEM state, Welcome processing and epoch exporters without transport, media, device or persistence ownership. Applications supply the authenticated external sender and expected participants. The product is not a general-purpose complete MLS client or an independent audit.

Begin with the guides for ownership and composition, then use the complete type index to explore each declaration and its members. Examples name the additional products they import so you can keep your package dependency graph explicit.

## Topics

### Guides

- <doc:GroupsAndIdentity>
- <doc:DeliveryAndRecovery>

### Core APIs

- ``MLSKeyPackageOwner``
- ``MLSGroup``
- ``MLSGroupPolicy``
- ``MLSKeyPackage``
- ``MLSExternalSender``
- ``MLSTentativeCommit``
- ``MLSCommitOutcome``
- ``MLSCipherSuite2``
- ``MLSSecretTree``

### Complete API reference

- <doc:APIReference>
