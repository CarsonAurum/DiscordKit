/// A caller-asserted spatial/temporal identity attached to an opaque encoded video frame.
///
/// Index bounds are DiscordKit storage policy, not an RTP field layout, a codec's permitted
/// layer count or a negotiated capability. Different codecs impose narrower or different
/// semantics; the caller must validate them before publication. This value supplies no
/// dependency graph, parsing, encoding, decoding, packetization, task or I/O ownership.
public struct VideoFrameLayer: Sendable, Equatable, Hashable {
    /// Nonnegative caller-assigned spatial layer index within the local `0...63` bound.
    public let spatialIndex: Int

    /// Nonnegative caller-assigned temporal layer index within the local `0...63` bound.
    public let temporalIndex: Int

    /// Validates a bounded layer identity without interpreting an encoded bitstream.
    /// - Parameters:
    ///   - spatialIndex: Caller-assigned spatial layer in `0...63`, inclusive. Zero can label
    ///     a base layer but this value does not verify that interpretation for any codec.
    ///   - temporalIndex: Caller-assigned temporal layer in `0...63`, inclusive. This local
    ///     range is deliberately independent of codec-specific wire fields and constraints.
    /// - Throws: `MediaError.invalidEncodedFrame` if either index is outside the local range.
    ///   Failure acquires no resources; construction is synchronous and starts no work.
    public init(spatialIndex: Int, temporalIndex: Int) throws {
        guard (0...63).contains(spatialIndex), (0...63).contains(temporalIndex) else {
            throw MediaError.invalidEncodedFrame
        }
        self.spatialIndex = spatialIndex
        self.temporalIndex = temporalIndex
    }
}
