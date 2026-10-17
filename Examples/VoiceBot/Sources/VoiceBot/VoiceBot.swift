import Foundation
import DiscordVoice
import DiscordVoiceCodecs
import DiscordVoiceCrypto

/// Offline integration example for the initial Phase 12 release, without a Discord session.
@main struct VoiceBot {
    /// Round-trips synthetic Opus silence through RTP-size protection and a bounded reorder queue.
    /// Uses a fixed, public test-only key that must never be used for real media. No network,
    /// device, authentication, DAVE context or background task is created. The two cipher
    /// instances model one sender and one receive-only peer, never two sending nonce owners.
    /// - Throws: Validation/authentication errors, including any round-trip invariant failure.
    static func main() async throws {
        let key = Data(0..<32)
        let sender = try VoiceTransportCipher(mode: .aeadXChaCha20Poly1305RTPSize, key: key)
        let receiver = try VoiceTransportCipher(mode: .aeadXChaCha20Poly1305RTPSize, key: key)
        do {
            var packetizer = OpusRTPPacketizer(ssrc: 1, sequence: 65_534, timestamp: .max - 959)
            var playout = try VoiceJitterBuffer(ssrc: 1, nextSequence: 65_534, capacity: 8, maximumBytes: 1024)
            for _ in 0..<5 {
                let packet = try packetizer.silencePacket()
                let plaintext = packet.serialized()
                let length = try RTPPacket.authenticatedHeaderLength(in: plaintext)
                let header = Data(plaintext.prefix(length))
                let encrypted = try await sender.seal(payload: Data(plaintext.dropFirst(length)), authenticatedHeader: header)
                let opened = try await receiver.open(sealedPayload: encrypted, authenticatedHeader: header)
                let received = try RTPPacket(bytes: header + opened)
                _ = try OpusPacket(received.payload)
                try playout.insert(received)
            }
            for _ in 0..<5 {
                guard case .packet = playout.pop() else { throw VoicePacketError.malformedPacket }
            }
            guard playout.bufferedBytes == 0 else { throw VoicePacketError.capacityExceeded }
            print("Five synthetic Opus packets authenticated and drained across RTP rollover.")
            print("Offline transport example only; MLS/DAVE and live voice sessions remain unimplemented.")
            await sender.close()
            await receiver.close()
        } catch {
            await sender.close()
            await receiver.close()
            throw error
        }
    }
}
