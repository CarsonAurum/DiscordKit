# Proposal delivery, candidate selection and recovery

Advance only the commit selected by the authenticated delivery service.

## Overview

### Cache proposals within a trusted membership domain

Deliver authenticated public proposal bytes through `cacheProposal`. The actor validates group/epoch/sender/signature and expected participant authorization before retaining bounded bytes. Revoke a proposal by its reference when the service withdraws it. Change `expectedParticipants` only from trusted session membership, not by accepting a self-announced identity from MLS wire data.

A proposal can be valid while still inappropriate for the application's current consent/call domain. Keep group ID and external sender pinned to the authenticated call. Never use a successful parser as membership authorization.

### Distinguish preparation from acceptance

`prepareCommit()` creates one ``MLSTentativeCommit`` containing public commit bytes and an optional Welcome. Preparation does not advance the active epoch. The delivery service may select another participant's candidate; accept the selected commit through `acceptCommit`, or join the specifically addressed Welcome with the expected group/policy.

```swift
import DiscordMLS
import Foundation

/// Accepts an already authenticated delivery decision, without choosing a candidate locally.
func acceptSelectedCommit(
    group: MLSGroup,
    selectedCommit: Data
) async throws -> MLSCommitOutcome {
    try await group.acceptCommit(selectedCommit)
}
```

The helper does not authenticate the delivery channel; the caller must do so first. `advanced` means a fully checked epoch was installed. `removed` means this owner was authentically removed and must stop using the old epoch. Do not discard an authentication error and continue sending with stale key material.

A Welcome is checked against the expected group and exact trusted policy. It is not accepted solely because it decrypts to one published key package. Candidate selection and addressed Welcome handling are important when several participants concurrently prepare a commit.

``MLSProposal`` provides bounded external-message splitting, and ``MLSTentativeCommit`` decodes a DAVE Commit/Welcome candidate. Preserve exact message boundaries rather than guessing by searching for TLS-like prefixes inside opaque bytes. Do not process an unlimited concatenated proposal stream.

### Recover with fresh ephemeral material

For a lost/invalidated group, stop media authorization and create a new key-package owner with fresh HPKE/init keys. Keep the long-lived signing identity only under the application session policy. A new key package does not justify resetting an old media sender counter under the same exporter domain.

Close superseded groups and unused candidates. An application using the DAVE coordinator should let that owner manage selected epoch/transition ordering instead of advancing MLS independently behind it. The media send gate must reflect the actually executed transition, not the existence of a tentative local commit.

### Test complete boundaries

Use deterministic public fixtures and independent published vectors for wire framing, signatures, HPKE, key schedules and tree operations. Test tampered commit/Welcome, wrong group/epoch, unauthorized participant, duplicate key package, stale candidate, concurrent creators, removal, proposal count/byte exhaustion and repeated closure. Compare exporter agreement only after both peers accept the same epoch.

A local two-member exchange establishes owned implementation behavior. It does not establish an independent audit, complete external-client interoperability, live Discord acceptance or production qualification. Keep those claims distinct when integrating the [DAVE profile](https://github.com/CarsonAurum/DiscordKit/blob/main/Docs/MLS.md).
