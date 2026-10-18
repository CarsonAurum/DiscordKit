import DiscordMedia
import DiscordSocial
import Testing

/// Local PCM controls prove routing, bounds and policy; no native or remote call is implied.
@Suite("Social local audio")
struct SocialAudioControlsTests {
    /// Nonfinite/excess gains and invalid call capacities fail before retaining resources.
    @Test func settingsBounds() throws {
        for gain: Float in [-1, 4.01, .infinity, -.infinity, .nan] {
            #expect(throws: MediaError.invalidGain) { try SocialAudioSettings(inputGain: gain) }
            #expect(throws: MediaError.invalidGain) { try SocialAudioSettings(outputGain: gain) }
        }
        #expect(try SocialAudioSettings().inputGain == 1)
        #expect(try SocialAudioSettings(inputGain: 0, outputGain: 4).outputGain == 4)
        for count in [0, 1025] {
            #expect(throws: SocialFailure.invalidConfiguration) { try SocialAudioControls(maximumCalls: count) }
        }
    }

    /// Combined gains clip once; global and per-call mute/deafen affect their documented directions.
    @Test func independentCaptureAndPlayback() async throws {
        let audio = try SocialAudioControls()
        let pcm = try PCMBuffer(format: PCMFormat(channelCount: 1), samples: [0.5, -0.5, 1, -1])
        try await audio.setCall(1, settings: SocialAudioSettings(inputGain: 2, outputGain: 0.5))
        try await audio.setCall(2, settings: SocialAudioSettings(muted: true))
        try await audio.setGlobal(SocialAudioSettings(inputGain: 2, outputGain: 0.5))
        #expect(try await audio.globalSettings().inputGain == 2)
        #expect(try await audio.globalSettings().outputGain == 0.5)
        #expect(try await audio.callSettings(1).inputGain == 2)
        #expect(try await audio.callSettings(2).muted)
        #expect(try await audio.capture(pcm, callID: 1).samples == [1, -1, 1, -1])
        #expect(try await audio.playback(pcm, callID: 1).samples == [0.125, -0.125, 0.25, -0.25])
        #expect(try await audio.capture(pcm, callID: 2).samples == [0, 0, 0, 0])
        #expect(try await audio.playback(pcm, callID: 2).samples == [0.25, -0.25, 0.5, -0.5])
        try await audio.setGlobal(SocialAudioSettings(muted: true))
        #expect(try await audio.capture(pcm, callID: 1).samples == [0, 0, 0, 0])
        #expect(try await audio.playback(pcm, callID: 1).samples == [0.25, -0.25, 0.5, -0.5])
        try await audio.setGlobal(SocialAudioSettings(deafened: true))
        #expect(try await audio.capture(pcm, callID: 1).samples == [0, 0, 0, 0])
        #expect(try await audio.playback(pcm, callID: 1).samples == [0, 0, 0, 0])
        try await audio.setGlobal(SocialAudioSettings())
        try await audio.setCall(1, settings: SocialAudioSettings(deafened: true))
        #expect(try await audio.capture(pcm, callID: 1).samples == [0, 0, 0, 0])
        #expect(try await audio.playback(pcm, callID: 1).samples == [0, 0, 0, 0])
        let empty = try PCMBuffer(format: pcm.format, samples: [])
        #expect(try await audio.capture(empty, callID: 1) == empty)
        #expect(pcm.samples == [0.5, -0.5, 1, -1])
    }

    /// Replacements work at capacity, missing routes fail closed, and repeat close releases all ownership.
    @Test func admissionAndClosure() async throws {
        let audio = try SocialAudioControls(maximumCalls: 1)
        let settings = try SocialAudioSettings()
        let pcm = try PCMBuffer(format: PCMFormat(channelCount: 2), samples: [0.25, -0.25])
        await #expect(throws: SocialFailure.invalidConfiguration) { try await audio.setCall(0, settings: settings) }
        try await audio.setCall(1, settings: settings)
        try await audio.setCall(1, settings: settings)
        await #expect(throws: SocialFailure.overloaded) { try await audio.setCall(2, settings: settings) }
        #expect(await audio.retainedCalls() == 1)
        #expect(try await audio.capture(pcm, callID: 1) == pcm)
        await #expect(throws: SocialFailure.missingProvider) { try await audio.playback(pcm, callID: 9) }
        await audio.removeCall(1); await audio.removeCall(1)
        await #expect(throws: SocialFailure.missingProvider) { try await audio.capture(pcm, callID: 1) }
        await #expect(throws: SocialFailure.missingProvider) { try await audio.callSettings(1) }
        try await audio.setCall(2, settings: settings)
        await audio.close(); await audio.close(); await audio.removeCall(2)
        #expect(await audio.retainedCalls() == 0)
        await #expect(throws: SocialFailure.closed) { try await audio.globalSettings() }
        await #expect(throws: SocialFailure.closed) { try await audio.callSettings(2) }
        await #expect(throws: SocialFailure.closed) { try await audio.setGlobal(settings) }
        await #expect(throws: SocialFailure.closed) { try await audio.setCall(1, settings: settings) }
        await #expect(throws: SocialFailure.closed) { try await audio.capture(pcm, callID: 2) }
        await #expect(throws: SocialFailure.closed) { try await audio.playback(pcm, callID: 2) }
    }
}
