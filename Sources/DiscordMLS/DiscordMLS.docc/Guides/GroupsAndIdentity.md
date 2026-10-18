# Establishing groups and trusted identity

Bind authenticated participants and external sender keys before processing MLS messages.

## Overview

### Know the implemented profile

DiscordMLS implements MLS 1.0 ciphersuite 2: P-256 key agreement/signatures, AES-128-GCM, SHA-256 and the corresponding HPKE suite. Owned wire framing, credentials, trees and secret derivation support the restricted public group-handshake profile used by DAVE. This does not imply every optional MLS proposal, credential type, private application-message policy or full client feature.

The module imports Swift Crypto and owns no network, device, timer or persistent store. Constructors do not start background work. Applications carry bytes over an authenticated delivery service and supply its authorization policy. They must also assign a unique group ID and prevent its unintended reuse.

### Supply identity authorization externally

``MLSGroupPolicy`` contains an exact ``MLSExternalSender`` and expected participant user IDs. Obtain both from authenticated session membership, not an incoming key package, Welcome or RTP packet. The policy authorizes basic credential/key associations through that trusted sender; it does not establish human out-of-band identity verification.

```swift
import DiscordMLS
import Foundation

/// Creates a fresh group only after the app has authenticated sender and membership policy.
func createAuthenticatedGroup(
    userID: UInt64,
    groupID: Data,
    externalSender: MLSExternalSender,
    expectedParticipants: Set<UInt64>,
    sharedSigningPrivateKey: Data
) async throws -> MLSGroup {
    let owner = try MLSKeyPackageOwner(
        userID: userID,
        signaturePrivateKey: sharedSigningPrivateKey
    )
    do {
        let policy = try MLSGroupPolicy(
            externalSender: externalSender,
            expectedParticipants: expectedParticipants,
            maximumMembers: 32
        )
        let group = try await owner.createGroup(groupID: groupID, policy: policy)
        await owner.close()
        return group
    } catch {
        await owner.close()
        throw error
    }
}
```

The supplied signing scalar is secret and must be a valid P-256 key. Use a shared signing identity when related DAVE sessions require continuity, while creating fresh HPKE/init keys for new key packages and recovery. The example's returned group has independent cleanup ownership; its caller must await `close()`.

### Treat key packages as single-use owners

``MLSKeyPackageOwner`` creates fresh key agreement/init material with a CSPRNG. Its public key package can be encoded for delivery without exposing private keys. Successful ordinary group creation or Welcome joining consumes the private package atomically. A rejected Welcome leaves it available for an explicitly valid later attempt.

`createGroup(..., retainForWelcome: true)` is a narrow candidate-selection path: it preserves the package for a competing creator's addressed Welcome. Close the unused candidate/package after selection. Do not reuse a consumed owner to join a second group or persist a package's private keys as a shortcut around recovery.

Group, key schedule and ratchet debug descriptions redact key material. Explicit exports and raw Data remain secrets, and logical cleanup does not promise physical memory erasure in Swift/Crypto storage.

### Bound messages and exported material

Policy caps member count, proposal count, aggregate proposal bytes and individual message bytes. Wire readers validate lengths and canonical structure before admitting state. Group mutations are actor-owned and errors do not advance an accepted epoch.

`export(label:context:length:)` derives purpose-bound material from the current epoch. Match exact label/context/length across peers and keep domains distinct. Group snapshots expose counts/epoch/closed state without keys. ``MLSSecretTree`` is a low-level owned component; its presence does not make the restricted group actor a complete private-application-message client.

The [offline MLS example](https://github.com/CarsonAurum/DiscordKit/blob/main/Examples/VoiceBot/Sources/VoiceBot/MLSExample.swift) demonstrates two members and a synthetic external sender. Fixed test keys in that example are public fixtures, never deployment credentials.
