// File: Sources/DiscordHTTP/Resources/InviteTargetUsersCSV.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Foundation

/// Bounded Invite acceptance-list CSV export with the documented user_id header.
/// Original bytes and complete UInt64 IDs remain exact; diagnostics conceal the acceptance list.
public struct InviteTargetUsersCSV: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let bytes: Data
    public let userIDs: [UserID]

    /// Validates a complete exported file in one pass without unbounded per-row temporary strings.
    /// - Parameters:
    ///   - data: CSV beginning with the exact user_id header, followed by zero or more decimal ID rows.
    ///     LF/CRLF and an optional final newline are accepted; quoted/multicolumn/blank rows, whitespace,
    ///     BOMs, non-UTF8 bytes and overflowing IDs are rejected. Order and duplicates remain unchanged.
    ///   - maximumBytes: Local whole-file cap in 1...8 MiB, default 1 MiB.
    ///   - maximumUsers: Local decoded-ID cap in 1...1,000,000, default 100,000; not an upstream quota.
    /// - Throws: Safe invalid-value for invalid limits; transport limitExceeded for oversized data/lists,
    ///   or sanitized invalidResponse for malformed CSV. Work is synchronous, linear and allocation-bounded;
    ///   it performs no I/O, credential access, task creation or cooperative cancellation checks.
    public init(data: Data, maximumBytes: Int = 1_048_576, maximumUsers: Int = 100_000) throws {
        try inviteCSVConfiguration(maximumBytes: maximumBytes, maximumUsers: maximumUsers)
        guard data.count <= maximumBytes else { throw DiscordError.transport(.limitExceeded) }
        userIDs = try inviteCSVRows(data, hasHeader: true, maximumUsers: maximumUsers, response: true)
        bytes = data
    }

    /// Conceals all CSV bytes and target IDs from ordinary interpolation.
    public var description: String { "InviteTargetUsersCSV(redacted)" }
    /// Uses the same safe diagnostic marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflection from exposing stored file data or acceptance targets.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Validates local CSV materialization caps without implying unpublished Discord row/byte quotas.
/// - Parameters:
///   - maximumBytes: Inclusive whole-file bound in 1...8 MiB.
///   - maximumUsers: Inclusive decoded-ID bound in 1...1,000,000.
/// - Throws: Safe invalid-value for an invalid cap. No allocation, I/O or suspension occurs.
func inviteCSVConfiguration(maximumBytes: Int, maximumUsers: Int) throws {
    guard (1...8_388_608).contains(maximumBytes), (1...1_000_000).contains(maximumUsers)
    else { throw DiscordError.validation(.invalidValue) }
}

/// Scans decimal allowlist rows with constant auxiliary state and optional bounded result retention.
/// - Parameters:
///   - data: Entire nonempty headerless upload, or headered export with zero or more numeric rows.
///   - hasHeader: True requires and consumes exact ASCII user_id followed by LF/CRLF or end of file.
///   - maximumUsers: Nil validates without retaining IDs, used by uploads; positive values bound output rows.
///   - response: True classifies malformed/oversized wire data as transport errors; false uses validation errors.
/// - Returns: IDs in original order when maximumUsers is supplied, otherwise an empty validation-only result.
/// - Throws: Sanitized invalidResponse/invalidValue for malformed input or exact UInt64 overflow;
///   limitExceeded for a retained-row cap violation. LF/CRLF and one trailing newline are accepted,
///   duplicates retained, and no undocumented upstream user-count cap is imposed on uploads.
/// Scanning is linear in bounded bytes, opens no files, and performs no asynchronous work.
func inviteCSVRows(_ data: Data, hasHeader: Bool, maximumUsers: Int?, response: Bool) throws -> [UserID] {
    let invalid = response ? DiscordError.transport(.invalidResponse) : DiscordError.validation(.invalidValue)
    let exceeded = response ? DiscordError.transport(.limitExceeded) : DiscordError.validation(.limitExceeded)
    var start = data.startIndex
    if hasHeader {
        let header = Array("user_id".utf8)
        guard data.count >= header.count else { throw invalid }
        for byte in header {
            guard data[start] == byte else { throw invalid }
            start = data.index(after: start)
        }
        if start == data.endIndex { return [] }
        if data[start] == 13 {
            start = data.index(after: start)
            guard start != data.endIndex else { throw invalid }
        }
        guard data[start] == 10 else { throw invalid }
        start = data.index(after: start)
    } else if data.isEmpty { throw invalid }
    var hasDigits = false, pendingCR = false
    var value: UInt64 = 0
    var ids: [UserID] = []
    for byte in data[start...] {
        guard !pendingCR || byte == 10 else { throw invalid }
        switch byte {
        case 48...57:
            let product = value.multipliedReportingOverflow(by: 10)
            let sum = product.partialValue.addingReportingOverflow(UInt64(byte - 48))
            guard !product.overflow, !sum.overflow else { throw invalid }
            value = sum.partialValue; hasDigits = true
        case 13:
            guard hasDigits else { throw invalid }
            pendingCR = true
        case 10:
            guard hasDigits else { throw invalid }
            if let maximumUsers {
                guard ids.count < maximumUsers else { throw exceeded }
                ids.append(UserID(rawValue: value))
            }
            hasDigits = false; pendingCR = false; value = 0
        default: throw invalid
        }
    }
    guard !pendingCR else { throw invalid }
    if hasDigits, let maximumUsers {
        guard ids.count < maximumUsers else { throw exceeded }
        ids.append(UserID(rawValue: value))
    }
    return ids
}
