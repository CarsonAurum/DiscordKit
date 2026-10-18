# Publishing complete device state

Report actual host metadata, preserve priority and replace the entire device array.

## Overview

### Construct metadata without touching hardware

A ``CertifiedDevice`` names one audio input, audio output or video input using a host-supplied native identifier. This product does not invent identifiers or inspect devices. ``CertifiedDeviceProduct`` stores descriptive vendor/model names and public URLs; the URLs are never fetched.

```swift
import DiscordCertifiedDevices
import Foundation

/// Describes a host-observed input; the supplied identifier must come from the native host.
func describeInput(nativeID: String) throws -> CertifiedDevice {
    let product = try CertifiedDeviceProduct(
        name: "Example microphone",
        url: URL(string: "https://example.com/microphone")!
    )
    return try CertifiedDevice(
        type: .audioInput,
        id: nativeID,
        vendor: product,
        model: product,
        audioProcessing: CertifiedDeviceAudioProcessing(hardwareMute: false)
    )
}
```

An absent processing flag means unreported; false explicitly reports disabled. Processing metadata is allowed only for audio input and reports native state rather than requesting Discord settings changes. Related identifiers preserve order and must be unique. Ordinary descriptions/reflection redact native IDs and names, but explicit field access still contains sensitive local hardware metadata.

### Choose a publication path

``CertifiedDeviceRPCPublisher`` uses an already connected and appropriately authorized RPC client. ``CertifiedDeviceHTTPPublisher`` uses an injected caller-owned HTTP transport and a fixed loopback endpoint. ``CertifiedDeviceWebSocketConnector`` retains the separately documented Certified Devices port range.

```swift
import DiscordCertifiedDevices
import DiscordTransport

/// Publishes one fresh full state through a caller-owned, proxy-free loopback transport.
func publishDeviceState(
    clientID: String,
    devices: [CertifiedDevice],
    transport: any HTTPTransport,
    clock: ContinuousClock
) async throws {
    let publisher = try CertifiedDeviceHTTPPublisher(
        clientID: clientID,
        port: 6463,
        transport: transport,
        maximumDevices: 32
    )
    do {
        try await publisher.publish(
            devices,
            context: TransportContext(
                clock: clock,
                deadline: clock.now.advanced(by: .seconds(5))
            )
        )
        await publisher.close()
    } catch {
        await publisher.close()
        throw error
    }
}
```

Use the HTTP helper only after selecting an authorized local host. Its transport must not proxy loopback traffic, follow redirects or automatically replay mutations. Closing the publisher cancels its operation; it does not close a shared injected pool. The HTTP/Certified Devices documentation lists ports 6463 through 6473, while generic desktop RPC lists a different bound. Select a known port explicitly instead of inferring universal scanning policy.

### Preserve replacement and ambiguity semantics

Supply the entire current array, highest priority first. Empty clears the list. `(type, id)` pairs must be unique; different types may share an ID. Removed devices are not merged into later publications. Republish after relevant host-observed device or processing changes, and serialize publications so a stale snapshot cannot overtake a fresh one.

Overlapping HTTP publication fails immediately. Request, response and device-count limits are local resource policy rather than published Discord quotas. A send failure can leave the remote mutation indeterminate; acquire a fresh host snapshot before an explicit new publication. Do not blindly retry the old list.

Test duplicate IDs, optional flags, empty clearing, order, response correlation, oversized responses, overlap and cancellation with synthetic peers. Successful validation does not prove certification, actual hardware enumeration, desktop acceptance or Windows identifier correctness.
