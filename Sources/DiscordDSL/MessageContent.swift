// File: Sources/DiscordDSL/MessageContent.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels

/// A finite authoring failure that never includes retained message text or identifiers.
public enum MessageContentError: Error, Sendable, Equatable {
    /// More than 4,096 nonempty segments or joined content values were supplied.
    case segmentLimit
    /// More than 1 MiB of source UTF-8 text was supplied.
    case sourceByteLimit
    /// Escaping would produce more than 1 MiB of rendered UTF-8 text.
    case renderedByteLimit
    /// More than 100 distinct users explicitly requested notification.
    case userMentionLimit
    /// More than 100 distinct roles explicitly requested notification.
    case roleMentionLimit
}

/// Observable rendered text and its explicit notification policy, ready for existing payload validation.
/// This is an authoring value: rendering performs no I/O, permission checks or notification delivery.
/// The content remains subject to the selected message payload's ordinary length/combination rules.
public struct RenderedMessageContent: Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    /// Final text, including preserved trusted markup and escaped ordinary interpolation.
    public let content: String
    /// Automatic parsing and reply-author mentions are disabled; typed opt-ins use explicit ID lists.
    public let allowedMentions: MessageAllowedMentions

    /// Retains already rendered values without introducing transport or execution ownership.
    /// - Parameters:
    ///   - content: Final observable text, validated by the message payload when adopted.
    ///   - allowedMentions: Explicit policy produced by the finite renderer.
    fileprivate init(content: String, allowedMentions: MessageAllowedMentions) {
        self.content = content
        self.allowedMentions = allowedMentions
    }

    /// Conceals rendered content and notification identifiers during ordinary formatting.
    public var description: String { "RenderedMessageContent(redacted)" }
    /// Retains the same safe marker for debugger formatting.
    public var debugDescription: String { description }
    /// Prevents reflection from traversing explicitly observable but potentially sensitive rendered values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// A synchronous, finite message template retaining text and typed mention intent until rendering.
///
/// Literals preserve developer-authored Markdown. Ordinary interpolated strings escape Markdown
/// metacharacters and insert U+200B after `<` and `@`, preventing untrusted mention tokens from
/// matching even an explicitly allowed typed ID elsewhere in the message. An additional U+200B
/// precedes ordinary text when trusted preceding fragments contain a still-open `<` or `@` token,
/// so splitting a mention between literals and interpolation cannot bypass neutralization.
/// `raw:` is the explicit
/// trusted escape hatch. Typed `user:`/`role:` interpolation opts the given ID into notifications
/// unless `notify: false` is supplied; `channel:` only formats a reference.
///
/// Discord applies allowed-mentions selectors to the entire message. A literal or raw mention of
/// an ID also opted in by a typed segment can therefore notify that ID. Never place untrusted
/// input in literals, raw segments or the trusted join separator. Raw text alone enables no IDs.
/// Mention permissions, suppression flags and actual delivery remain Discord's responsibility.
///
/// Capture admits at most 4,096 nonempty segments and 1 MiB of source UTF-8. A nonthrowing literal
/// or interpolation that exceeds admission records a terminal failure without retaining the
/// oversized input; `render()` throws that failure. Escaped output is separately bounded to 1 MiB.
/// These are authoring resource limits; existing payload models enforce Discord message limits.
public struct MessageContent: ExpressibleByStringLiteral, ExpressibleByStringInterpolation,
    Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
{
    /// Maximum nonempty captured segments and joined content values, independent of wire limits.
    public static let maximumSegments = 4_096
    /// Maximum aggregate source UTF-8 bytes retained by a template.
    public static let maximumSourceBytes = 1_048_576
    /// Maximum rendered UTF-8 bytes, including escaping expansion.
    public static let maximumRenderedBytes = 1_048_576

    private var storage: MessageContentStorage

    /// Captures a dynamic string as ordinary escaped text rather than trusted literal markup.
    /// - Parameter text: Arbitrary Unicode text; oversized input records a later rendering failure.
    public init(_ text: String) {
        storage = MessageContentStorage()
        storage.append(.text(text))
    }

    /// Captures a trusted literal without formatting or enabling any mention selectors.
    /// - Parameter value: Developer-authored markup; oversized input fails when rendered.
    public init(stringLiteral value: String) {
        storage = MessageContentStorage()
        storage.append(.literal(value))
    }

    /// Adopts interpolation's bounded segments without evaluating any asynchronous work.
    /// - Parameter stringInterpolation: Already captured segments and any terminal admission failure.
    public init(stringInterpolation: StringInterpolation) {
        storage = stringInterpolation.storage
    }

    /// Conceals trusted/raw source and typed mention identifiers during ordinary formatting.
    public var description: String { "MessageContent(redacted)" }
    /// Retains the same safe marker for debugger formatting.
    public var debugDescription: String { description }
    /// Prevents reflective traversal into captured source, including poisoned templates.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

    /// Combines templates while preserving each segment's escaping and typed notification intent.
    /// - Parameters:
    ///   - contents: At most 4,096 content values, visited in array order; empty input produces empty text.
    ///   - separator: Trusted literal inserted between values, default newline; it enables no mentions.
    /// - Returns: An inert template with sticky admission failures, reported by `render()`.
    public static func joined(_ contents: [MessageContent], separator: String = "\n") -> MessageContent {
        var result: MessageContent = ""
        guard contents.count <= maximumSegments else {
            result.storage.fail(.segmentLimit)
            return result
        }
        for (index, content) in contents.enumerated() {
            if index > 0 { result.storage.append(.literal(separator)) }
            result.storage.merge(content.storage)
            if result.storage.failure != nil { break }
        }
        return result
    }

    /// Produces bounded text with automatic parsing/reply mentions disabled and typed ID opt-ins.
    /// - Returns: Text plus at most 100 distinct user IDs and 100 role IDs, deduplicated in first-use order.
    ///   Empty selectors are omitted. Repeated rendering is deterministic and does not consume state.
    /// - Throws: `MessageContentError` for sticky capture failure, escaping expansion or excessive
    ///   distinct notification IDs; existing allowed-mentions validation errors if its invariants change.
    ///   No partial output is returned. Existing message payloads separately enforce message lengths.
    public func render() throws -> RenderedMessageContent {
        if let failure = storage.failure { throw failure }
        var users: [UserID] = []
        var roles: [RoleID] = []
        var seenUsers: Set<UserID> = []
        var seenRoles: Set<RoleID> = []
        for segment in storage.segments {
            switch segment {
            case .user(let id, true):
                if seenUsers.insert(id).inserted {
                    guard users.count < 100 else { throw MessageContentError.userMentionLimit }
                    users.append(id)
                }
            case .role(let id, true):
                if seenRoles.insert(id).inserted {
                    guard roles.count < 100 else { throw MessageContentError.roleMentionLimit }
                    roles.append(id)
                }
            default: break
            }
        }
        let policy = try MessageAllowedMentions(parse: [], roles: roles.isEmpty ? nil : roles,
            users: users.isEmpty ? nil : users, repliedUser: false)
        var output = ""
        var renderedBytes = 0
        var boundary = MessageContentBoundaryState()
        for segment in storage.segments {
            switch segment {
            case .literal(let text), .raw(let text):
                try Self.appendRendered(text, to: &output, byteCount: &renderedBytes, boundary: &boundary)
            case .text(let text):
                if boundary.needsFence {
                    try Self.appendRendered("\u{200B}", to: &output, byteCount: &renderedBytes, boundary: &boundary)
                }
                for scalar in text.unicodeScalars {
                    let part: String
                    switch scalar {
                    case "<", "@": part = String(scalar) + "\u{200B}"
                    case "\\", "`", "*", "_", "~", "|", ">", "[", "]", "(", ")", "#", "+", "-", ".", "!", "{", "}":
                        part = "\\" + String(scalar)
                    default: part = String(scalar)
                    }
                    try Self.appendRendered(part, to: &output, byteCount: &renderedBytes, boundary: &boundary)
                }
            case .user(let id, _):
                try Self.appendRendered("<@\(id)>", to: &output, byteCount: &renderedBytes, boundary: &boundary)
            case .role(let id, _):
                try Self.appendRendered("<@&\(id)>", to: &output, byteCount: &renderedBytes, boundary: &boundary)
            case .channel(let id):
                try Self.appendRendered("<#\(id)>", to: &output, byteCount: &renderedBytes, boundary: &boundary)
            }
        }
        return RenderedMessageContent(content: output, allowedMentions: policy)
    }

    /// Appends only after checking remaining output capacity, including for a single large raw segment.
    /// - Parameters:
    ///   - text: Next already formatted piece; copied only when the complete piece fits.
    ///   - output: Caller-owned partial output; never returned after any failure.
    ///   - byteCount: Exact bytes already appended, maintained within `0...maximumRenderedBytes`.
    ///   - boundary: Finite trailing-token state used to isolate the next ordinary interpolation.
    /// - Throws: `MessageContentError.renderedByteLimit` before appending an excessive piece.
    private static func appendRendered(_ text: String, to output: inout String,
                                       byteCount: inout Int, boundary: inout MessageContentBoundaryState) throws {
        let remaining = maximumRenderedBytes - byteCount
        let bytes = text.utf8.prefix(remaining + 1).count
        guard bytes <= remaining else { throw MessageContentError.renderedByteLimit }
        output.append(text)
        byteCount += bytes
        boundary.consume(text)
    }

    /// Finite capture hooks selected by Swift's string interpolation syntax.
    public struct StringInterpolation: StringInterpolationProtocol, Sendable, Equatable,
        CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable
    {
        fileprivate var storage = MessageContentStorage()

        /// Starts empty capture, ignoring untrusted capacity hints to avoid eager allocations.
        /// - Parameters:
        ///   - literalCapacity: Compiler sizing hint; deliberately does not reserve storage.
        ///   - interpolationCount: Compiler expression-count hint; actual segments determine admission.
        public init(literalCapacity: Int, interpolationCount: Int) {}

        /// Conceals partially captured source during ordinary formatting.
        public var description: String { "MessageContent.StringInterpolation(redacted)" }
        /// Retains the same safe marker for debugger formatting.
        public var debugDescription: String { description }
        /// Prevents reflective traversal before interpolation is adopted by its final template.
        public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }

        /// Retains literal markup without inferring or enabling mention IDs from its spelling.
        /// - Parameter literal: Trusted source fragment; empty fragments consume no segment budget.
        public mutating func appendLiteral(_ literal: String) { storage.append(.literal(literal)) }

        /// Retains ordinary text for Markdown escaping and mention-token neutralization at rendering.
        /// - Parameter value: Untrusted Unicode string, including empty strings and mention-looking text.
        public mutating func appendInterpolation(_ value: String) { storage.append(.text(value)) }

        /// Explicitly retains trusted text verbatim, without automatically allowing any notifications.
        /// - Parameter value: Developer-approved markup; never pass untrusted input through this escape hatch.
        public mutating func appendInterpolation(raw value: String) { storage.append(.raw(value)) }

        /// Preserves a nested template's segment intent and any terminal admission failure.
        /// - Parameter value: Previously captured template; this does not render or execute it.
        public mutating func appendInterpolation(_ value: MessageContent) { storage.merge(value.storage) }

        /// Formats a typed user reference with explicit notification intent.
        /// - Parameters:
        ///   - value: Complete unsigned user ID; existence and permissions remain server checked.
        ///   - notify: Default `true` adds the ID to the global user allow list; `false` only displays it.
        ///     Another notifying segment or explicit payload override can still allow the same ID globally.
        public mutating func appendInterpolation(user value: UserID, notify: Bool = true) {
            storage.append(.user(value, notify))
        }

        /// Formats a typed role reference with explicit notification intent.
        /// - Parameters:
        ///   - value: Complete unsigned role ID; mentionability/permissions remain server checked.
        ///   - notify: Default `true` adds the ID to the global role allow list; `false` only displays it.
        ///     Another notifying segment or explicit payload override can still allow the same ID globally.
        public mutating func appendInterpolation(role value: RoleID, notify: Bool = true) {
            storage.append(.role(value, notify))
        }

        /// Formats a channel reference without adding any notification selectors.
        /// - Parameter value: Complete unsigned channel ID; visibility and existence remain server checked.
        public mutating func appendInterpolation(channel value: ChannelID) { storage.append(.channel(value)) }
    }
}

/// Conservative constant-space detection of trusted fragments that might continue a mention token.
/// It intentionally does not parse Discord markup or infer valid snowflake lengths. False positives
/// only insert an invisible separator; arbitrary-length or leading-zero fragments remain isolated.
fileprivate struct MessageContentBoundaryState {
    var needsFence = false

    /// Tracks token introducers until an unambiguous boundary, including across raw/literal joins.
    /// - Parameter text: Already bounded rendered fragment, inspected once without retaining text.
    mutating func consume(_ text: String) {
        for scalar in text.unicodeScalars {
            switch scalar {
            case "<", "@": needsFence = true
            case ">", " ", "\t", "\r", "\n", "\u{200B}": needsFence = false
            default: break
            }
        }
    }
}

/// Segment identity retained until rendering so escaping cannot accidentally grant mention intent.
fileprivate enum MessageContentSegment: Sendable, Equatable {
    case literal(String)
    case text(String)
    case raw(String)
    case user(UserID, Bool)
    case role(RoleID, Bool)
    case channel(ChannelID)
}

/// Capture state shared by literals, interpolation and finite template joining.
fileprivate struct MessageContentStorage: Sendable, Equatable {
    var segments: [MessageContentSegment] = []
    var sourceBytes = 0
    var failure: MessageContentError?

    /// Admits one complete segment before retaining its source; failures permanently poison this capture.
    /// - Parameter segment: Finite typed reference or text whose UTF-8 prefix is inspected only up to capacity.
    mutating func append(_ segment: MessageContentSegment) {
        guard failure == nil else { return }
        let bytes: Int
        switch segment {
        case .literal(let text), .text(let text), .raw(let text):
            if text.isEmpty { return }
            bytes = text.utf8.prefix(MessageContent.maximumSourceBytes - sourceBytes + 1).count
        case .user(let id, _): bytes = id.description.utf8.count + 3
        case .role(let id, _): bytes = id.description.utf8.count + 4
        case .channel(let id): bytes = id.description.utf8.count + 3
        }
        guard segments.count < MessageContent.maximumSegments else { fail(.segmentLimit); return }
        guard bytes <= MessageContent.maximumSourceBytes - sourceBytes else { fail(.sourceByteLimit); return }
        sourceBytes += bytes
        segments.append(segment)
    }

    /// Adopts another capture in order, propagating its original failure without exposing partial output.
    /// - Parameter other: Already bounded capture; no segments are inspected after the first failure.
    mutating func merge(_ other: MessageContentStorage) {
        guard failure == nil else { return }
        if let failure = other.failure { fail(failure); return }
        for segment in other.segments {
            append(segment)
            if failure != nil { break }
        }
    }

    /// Records only the first failure and drops retained text so failed templates do not keep source bytes alive.
    /// - Parameter error: Safe admission failure; further appends and merges become inert.
    mutating func fail(_ error: MessageContentError) {
        guard failure == nil else { return }
        failure = error
        segments.removeAll(keepingCapacity: false)
        sourceBytes = 0
    }
}
