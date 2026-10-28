// File: Examples/SocialApp/Sources/SocialApp/SocialApp.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordMedia
import DiscordSocial

/// Offline independent consumer of Social authorization, local state and PCM controls.
/// No credentials, provider connections, devices or authenticated requests are created.
@main struct SocialApp {
    /// Exercises the public concurrency surface from MainActor and closes local ownership.
    /// - Throws: Local value/admission errors if the synthetic fixture becomes invalid.
    @MainActor static func main() async throws {
        let client = try SocialClient(clock: ContinuousClock(), stateLimits: SocialStateLimits())
        let scope = SocialScope(applicationID: .init(rawValue: 1), accountID: .init(rawValue: 2), consentGeneration: 1)
        try await client.activate(scope: scope, grantedScopes: [])
        let friend = SocialUser(id: .init(rawValue: UInt64.max), username: "synthetic-friend")
        _ = try await client.synchronize(SocialStateSnapshot(scope: scope, generation: 1, sequence: 0,
            users: [friend], relationships: [SocialRelationship(userID: friend.id, kind: .friend)]))
        let friends = try await client.relationshipView().users(in: .friend)
        let audio = try SocialAudioControls(maximumCalls: 1)
        try await audio.setCall(1, settings: SocialAudioSettings(muted: true))
        let pcm = try PCMBuffer(format: PCMFormat(channelCount: 1), samples: [0.5, -0.5])
        let captured = try await audio.capture(pcm, callID: 1)
        print("Offline Social: \(friends.count) local friend; muted PCM \(captured.samples.allSatisfy { $0 == 0 })")
        await client.close(); await audio.close()
        print("Closed: \(await client.snapshot().closed); retained local calls: \(await audio.retainedCalls())")
    }
}
