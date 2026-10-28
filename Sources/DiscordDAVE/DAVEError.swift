// File: Sources/DiscordDAVE/DAVEError.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import Foundation

/// Payload-free failures from DAVE v1 sender ratchets and encoded-frame transforms.
public enum DAVEError: Error, Sendable, Equatable {
    /// A resource, time, counter, or security policy lies outside the supported bounds.
    case invalidConfiguration
    /// The frame, footer, range list, or codec structure is invalid or truncated.
    case malformedFrame
    /// The encoded frame exceeds the configured combined ciphertext and associated-data bound.
    case frameTooLarge
    /// The sender exporter secret is not exactly sixteen bytes.
    case invalidSecret
    /// The requested generation has already been logically erased.
    case generationExpired
    /// Deriving the requested generation would exceed the bounded forward-work budget.
    case generationTooFarAhead
    /// The absolute sender counter has reached its configured lifetime cap.
    case nonceExhausted
    /// The eight-byte authentication tag does not authenticate the supplied frame.
    case authenticationFailed
    /// The nonce was accepted before or lies outside the bounded replay window.
    case replayedFrame
    /// A generation's total or failed verification-attempt budget has been exhausted.
    case verificationLimit
    /// Retaining another media epoch would exceed the configured ownership bound.
    case epochLimit
    /// Reinstalling a used key domain would reset nonce or replay ownership.
    case epochReuse
    /// Ten distinct H26x encryption attempts all produced a forbidden start-code sequence.
    case codecRetryLimit
    /// This cipher has been permanently closed and no longer owns usable keys.
    case closed
}

/// Explicit media context for the narrowly specified SFU-generated Opus silence exception.
public enum DAVEMediaType: Sendable, Equatable {
    /// Encoded audio; the caller may explicitly permit the exact three-byte silence packet.
    case audio
    /// Encoded video; no plaintext silence exception is available.
    case video
}
