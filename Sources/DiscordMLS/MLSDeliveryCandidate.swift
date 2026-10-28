// File: Sources/DiscordMLS/MLSDeliveryCandidate.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

extension MLSTentativeCommit {
    /// Splits DAVE's self-delimiting public Commit and optional bare Welcome candidate.
    ///
    /// This performs bounded canonical structural decoding only. It verifies no
    /// signature, membership MAC, confirmation tag, recipient authorization, or
    /// epoch authenticity. A delivery owner must pass the selected Commit/Welcome
    /// to the matching MLS/DAVE group for authentication before changing state.
    /// The returned Welcome restores its MLS 1.0 message wrapper; the input's
    /// Commit retains its wrapper, exactly as emitted by DAVE client opcode 28.
    /// - Parameters:
    ///   - bytes: Complete opcode-28 payload after removing the client opcode byte;
    ///     one canonical public member Commit followed by zero or one bare Welcome.
    ///   - maximumBytes: Positive complete payload limit through 1,048,576, default
    ///     one MiB. No transport, group mutation, task or key derivation occurs.
    /// - Returns: Exact Commit, optionally wrapped Welcome, and the unauthenticated
    ///   target epoch (`Commit.epoch + 1`). Empty Welcome bytes produce `nil`.
    /// - Throws: `invalidConfiguration` for an invalid limit; `capacityExceeded`
    ///   above the byte budget; MLS wire/version/suite errors for malformed data;
    ///   `invalidCommit` for proposals, nonmember senders, or epoch overflow.
    public static func decodeDAVECommitWelcome(_ bytes: Data, maximumBytes: Int = 1_048_576) throws -> Self {
        guard (1...1_048_576).contains(maximumBytes) else { throw MLSError.invalidConfiguration }
        guard bytes.count <= maximumBytes else { throw MLSError.capacityExceeded }
        var reader = try MLSReader(bytes, maximumBytes: maximumBytes)
        let message = try MLSPublicMessage.decode(&reader)
        guard case .commit = message.body, case .member = message.sender, message.epoch < UInt64.max else {
            throw MLSError.invalidCommit
        }
        let commit = try message.encoded()
        guard bytes.starts(with: commit) else { throw MLSError.malformedEncoding }
        let tail = try reader.readRaw(count: reader.remainingCount)
        let welcome: Data?
        if tail.isEmpty { welcome = nil }
        else {
            let wrapped = Data([0, 1, 0, 3]) + tail
            let parsed = try MLSWelcome.decode(wrapped)
            guard try parsed.encoded() == wrapped else { throw MLSError.malformedEncoding }
            welcome = wrapped
        }
        return Self(commit: commit, welcome: welcome, epoch: message.epoch + 1)
    }
}
