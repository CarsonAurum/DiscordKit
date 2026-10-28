// File: Tests/DiscordMediaTests/MediaDescriptorTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation
import Testing
@testable import DiscordMedia

@Suite("Opaque video codec and layer metadata")
struct MediaDescriptorTests {
    /// Accepts every local index while preserving both dimensions, equality and hashing.
    /// These metadata-only values do not assert a codec supports any particular layer pair.
    @Test func layerStorageRangeAndIdentity() throws {
        for index in 0...63 {
            let layer = try VideoFrameLayer(spatialIndex: index, temporalIndex: 63 - index)
            #expect(layer.spatialIndex == index && layer.temporalIndex == 63 - index)
            #expect(layer == (try VideoFrameLayer(spatialIndex: index, temporalIndex: 63 - index)))
            #expect(Set([layer, layer]).count == 1)
        }
        #expect(try VideoFrameLayer(spatialIndex: 0, temporalIndex: 1) != VideoFrameLayer(spatialIndex: 1, temporalIndex: 0))
        #expect(try VideoFrameLayer(spatialIndex: 0, temporalIndex: 0).spatialIndex == 0)
        #expect(try VideoFrameLayer(spatialIndex: 63, temporalIndex: 63).temporalIndex == 63)
    }

    /// Rejects either out-of-range index independently, including hostile integer extremes.
    /// - Parameters:
    ///   - spatial: Valid or invalid spatial index paired with at least one invalid index.
    ///   - temporal: Valid or invalid temporal index paired with at least one invalid index.
    @Test(arguments: [(-1, 0), (64, 0), (Int.min, 0), (Int.max, 0),
                      (0, -1), (0, 64), (0, Int.min), (0, Int.max), (-1, 64)])
    func invalidLayer(spatial: Int, temporal: Int) {
        #expect(throws: MediaError.invalidEncodedFrame) {
            try VideoFrameLayer(spatialIndex: spatial, temporalIndex: temporal)
        }
    }

    /// Preserves opaque bytes and caller-supplied timing, dimensions, keyframe and layer labels.
    /// Existing initializer calls omit the new parameter and continue to produce nil metadata.
    /// - Parameters:
    ///   - codec: Every declared video label, including H.265 without a codec implementation.
    ///   - keyFrame: Both caller-asserted random-access classifications.
    @Test(arguments: [
        (MediaCodec.h264, false), (.h264, true), (.h265, false), (.h265, true),
        (.vp8, false), (.vp8, true), (.vp9, false), (.vp9, true), (.av1, false), (.av1, true)
    ])
    func encodedVideoLayerMetadata(codec: MediaCodec, keyFrame: Bool) throws {
        let time = try MediaTime(value: .max, timescale: .max)
        let layer = try VideoFrameLayer(spatialIndex: 63, temporalIndex: 0)
        var bytes = Data([0x12, 0x34, 0x56])
        let frame = try EncodedVideoFrame(codec: codec, bytes: bytes, timestamp: time,
                                         width: 1, height: 8_192, isKeyFrame: keyFrame, layer: layer)
        bytes[0] = 0xff
        #expect(frame.codec == codec && frame.bytes == Data([0x12, 0x34, 0x56]))
        #expect(frame.timestamp == time && frame.width == 1 && frame.height == 8_192)
        #expect(frame.isKeyFrame == keyFrame && frame.layer == layer)
        let same = try EncodedVideoFrame(codec: codec, bytes: frame.bytes, timestamp: time,
                                        width: 1, height: 8_192, isKeyFrame: keyFrame, layer: layer)
        #expect(frame == same)
        let withoutLayer = try EncodedVideoFrame(codec: codec, bytes: frame.bytes, timestamp: time,
                                                width: 1, height: 8_192, isKeyFrame: keyFrame)
        #expect(withoutLayer.layer == nil)
        #expect(frame != withoutLayer)
        let differentLayer = try EncodedVideoFrame(codec: codec, bytes: frame.bytes, timestamp: time,
                                                  width: 1, height: 8_192, isKeyFrame: keyFrame,
                                                  layer: VideoFrameLayer(spatialIndex: 0, temporalIndex: 63))
        #expect(frame != differentLayer)
    }

    /// Checks H.265's metadata label and rejects it in the audio-only constructor.
    /// Raw strings are local labels and are not advertised as Discord negotiation names.
    @Test func h265LabelIsVideoMetadataOnly() throws {
        #expect(MediaCodec.h265.rawValue == "h265")
        #expect(MediaCodec(rawValue: "h265") == .h265)
        let time = try MediaTime(value: 0, timescale: 48_000)
        let duration = try MediaTime(value: 960, timescale: 48_000)
        #expect(throws: MediaError.invalidEncodedFrame) {
            try EncodedAudioFrame(codec: .h265, bytes: Data([0]), timestamp: time, duration: duration)
        }
        let layer = try VideoFrameLayer(spatialIndex: 0, temporalIndex: 0)
        #expect(throws: MediaError.invalidEncodedFrame) {
            try EncodedVideoFrame(codec: .opus, bytes: Data([0]), timestamp: time,
                                  width: 1, height: 1, isKeyFrame: false, layer: layer)
        }
    }

    /// Preserves video payload and dimension bounds when H.265 and optional layers are used.
    /// Empty/oversize payloads and each invalid dimension must fail without payload inspection.
    @Test func h265PayloadAndDimensionBounds() throws {
        let time = try MediaTime(value: 0, timescale: 1)
        let layer = try VideoFrameLayer(spatialIndex: 63, temporalIndex: 63)
        let maximum = try EncodedVideoFrame(codec: .h265, bytes: Data(repeating: 0, count: 4_194_304),
                                            timestamp: time, width: 8_192, height: 8_192,
                                            isKeyFrame: true, layer: layer)
        #expect(maximum.bytes.count == 4_194_304 && maximum.layer == layer)
        for count in [0, 4_194_305] {
            #expect(throws: MediaError.invalidEncodedFrame) {
                try EncodedVideoFrame(codec: .h265, bytes: Data(repeating: 0, count: count), timestamp: time,
                                      width: 1, height: 1, isKeyFrame: false, layer: layer)
            }
        }
        for (width, height) in [(0, 1), (-1, 1), (8_193, 1), (Int.max, 1), (Int.min, 1),
                                (1, 0), (1, -1), (1, 8_193), (1, Int.max), (1, Int.min)] {
            #expect(throws: MediaError.invalidEncodedFrame) {
                try EncodedVideoFrame(codec: .h265, bytes: Data([0]), timestamp: time,
                                      width: width, height: height, isKeyFrame: false, layer: layer)
            }
        }
    }
}
