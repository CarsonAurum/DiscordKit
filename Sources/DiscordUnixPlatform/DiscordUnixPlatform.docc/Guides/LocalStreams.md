# Connecting and framing local streams

Keep path authorization, stream framing and native cleanup explicit.

## Overview

### Open only a caller-selected socket

The application selects and authorizes a Unix socket path. ``UnixIPCTransport`` performs no discovery, file creation, TCP fallback or retry. Paths are excluded from diagnostic failures. Supply a finite startup context for a missing or unresponsive service.

```swift
import DiscordTransport
import DiscordUnixPlatform

/// Opens an authorized absolute Unix socket path with bounded unread and write bytes.
func openIPC(path: String) async throws -> UnixIPCTransport {
    let clock = ContinuousClock()
    return try await UnixIPCTransport.connect(
        path: path,
        maximumBufferedBytes: 262_144,
        maximumWriteBytes: 65_536,
        context: TransportContext(
            clock: clock,
            deadline: clock.now.advanced(by: .seconds(5))
        )
    )
}
```

Call this helper only with a path obtained from trusted local configuration or validated host discovery. A local pathname is not an authenticated Discord user session. Protect the socket directory and verify the peer's protocol before sending private data.

### Treat input as an arbitrary byte stream

A write need not match a read. One read can contain a prefix of a frame, several frames or a suffix left from an earlier write. Maintain one bounded incremental decoder above this adapter. For desktop RPC, use the independently adopted DiscordRPC connection/framing layer rather than decoding arbitrary reads as JSON.

Read requests require a positive maximum. Returned chunks are nonempty; `nil` means EOF. At peer EOF, already buffered input remains readable until drained. Explicit close, cancellation and overflow discard unread bytes. An empty write succeeds only on an open stream, without transmitting data.

Only one reader and one admitted writer may be active. A concurrent writer fails immediately rather than creating an implicit queue. Once a write is admitted, cancellation or expiration closes the entire stream. Bytes already written cannot be recalled; retrying the same application mutation can duplicate it.

### Finish the complete resource lifetime

The returned transport owns a channel and one event-loop thread. Await `close()` on success and failure. Repeated or concurrent closure shares cleanup, unblocks a pending read with EOF and releases native resources. Keep shutdown outside an abandoned child task so a parent's cancellation cannot leave the event loop running.

Test with a temporary local socket peer: fragment a header one byte at a time, combine multiple frames, close after writing a final buffered suffix, cancel an admitted write and overflow unread capacity. These checks qualify the byte-stream adapter on the tested host. They do not qualify Windows named-pipe behavior, real Discord desktop discovery or application approval.

The [desktop RPC example](https://github.com/CarsonAurum/DiscordKit/tree/main/Examples/RPCApp) shows the separate protocol consumer boundary.
