// File: Sources/DiscordSocial/SocialValueModels.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore

/// Sanitized construction failures for bounded, application-owned Social metadata.
public enum SocialValueError: Error, Equatable, Sendable {
    /// A configured UTF-8 string budget was negative.
    case invalidStringLimit
    /// The supplied metadata exceeds its configured aggregate UTF-8 budget.
    case stringLimitExceeded
}

/// Published Social Activity action values, preserving unknown future integers.
///
/// These values identify metadata only. A `.join` value does not authorize accepting
/// an invite, and a native SDK signature does not establish a public delivery wire.
public struct SocialActivityAction: RawRepresentable, Equatable, Hashable, Sendable {
    /// Exact published or unknown action integer.
    public let rawValue: Int32
    /// Published invalid/unset action.
    public static let invalid = Self(rawValue: 0)
    /// Published invitation to join an activity.
    public static let join = Self(rawValue: 1)
    /// Published request to join another user's activity.
    public static let joinRequest = Self(rawValue: 5)

    /// Preserves a published or unknown action without assigning new behavior.
    /// - Parameter rawValue: Any signed 32-bit integer, including unknown values.
    ///   Construction performs no validation, authorization, I/O, or allocation.
    public init(rawValue: Int32) { self.rawValue = rawValue }
}

/// Immutable application-owned equivalent of locally constructible Activity invite metadata.
///
/// Values never create, receive, accept, or validate a remote invitation. In particular,
/// `isValid` is an observation supplied by a qualified provider, not a trust decision.
/// Identifiers preserve zero/unset and the full unsigned range. C++ setters correspond
/// to constructing a replacement Swift value; no native handle lifetime is retained.
/// Party/session text is bounded and concealed in ordinary diagnostics.
public struct SocialActivityInvite: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    /// Observed inviter; zero remains an unset metadata value.
    public let senderID: UserID
    /// Observed channel; zero remains unset and does not authorize reading it.
    public let channelID: ChannelID
    /// Observed message; zero remains unset.
    public let messageID: MessageID
    /// Published or unknown action type, preserved without interpretation.
    public let action: SocialActivityAction
    /// Observed game application identifier, including an unset zero.
    public let applicationID: ApplicationID
    /// Observed publisher application identifier; nil means no supplied parent.
    public let parentApplicationID: ApplicationID?
    /// Opaque provider party identifier; it is never treated as a join secret.
    public let partyID: String
    /// Opaque provider session identifier; no socket/session is opened.
    public let sessionID: String
    /// Provider-supplied current validity observation; never proof of authorization.
    public let isValid: Bool

    /// Constructs bounded local invite metadata without inventing a remote wire format.
    /// - Parameters:
    ///   - senderID: Exact observed inviter identifier, including zero/unset.
    ///   - channelID: Exact observed channel identifier, including zero/unset.
    ///   - messageID: Exact observed message identifier, including zero/unset.
    ///   - action: Published or unknown action; defaults to invalid/unset.
    ///   - applicationID: Observed game application identifier, including zero/unset.
    ///   - parentApplicationID: Optional publisher identifier; defaults to absent.
    ///   - partyID: Opaque party text; defaults to empty and is retained verbatim.
    ///   - sessionID: Opaque session text; defaults to empty and is retained verbatim.
    ///   - isValid: Provider observation, default false; it grants no permissions.
    ///   - maximumStringBytes: Nonnegative aggregate party/session UTF-8 budget,
    ///     default 8,192. Zero permits only empty strings. No normalization occurs.
    /// - Throws: `SocialValueError.invalidStringLimit` for a negative budget, or
    ///   `.stringLimitExceeded` when aggregate string bytes exceed that budget.
    ///   No fields or external state are changed on failure. Construction is synchronous
    ///   and requires work proportional to the supplied string byte counts.
    public init(
        senderID: UserID, channelID: ChannelID, messageID: MessageID,
        action: SocialActivityAction = .invalid, applicationID: ApplicationID,
        parentApplicationID: ApplicationID? = nil, partyID: String = "", sessionID: String = "",
        isValid: Bool = false, maximumStringBytes: Int = 8_192
    ) throws {
        guard maximumStringBytes >= 0 else { throw SocialValueError.invalidStringLimit }
        let partyBytes = partyID.utf8.count
        guard partyBytes <= maximumStringBytes,
            sessionID.utf8.count <= maximumStringBytes - partyBytes
        else { throw SocialValueError.stringLimitExceeded }
        self.senderID = senderID
        self.channelID = channelID
        self.messageID = messageID
        self.action = action
        self.applicationID = applicationID
        self.parentApplicationID = parentApplicationID
        self.partyID = partyID
        self.sessionID = sessionID
        self.isValid = isValid
    }

    /// Conceals user/channel/message identity and opaque party/session data in logs.
    public var description: String { "SocialActivityInvite(redacted)" }

    /// Uses the same redaction for nested debugger-oriented string formatting.
    public var debugDescription: String { description }

    /// Prevents reflection from traversing user identity and opaque session metadata.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Published Social additional-content values, preserving unknown future integers.
public struct SocialAdditionalContentKind: RawRepresentable, Equatable, Hashable, Sendable {
    /// Exact published or unknown kind integer.
    public let rawValue: Int32
    /// Other/unclassified content.
    public static let other = Self(rawValue: 0)
    /// File/image attachment metadata.
    public static let attachment = Self(rawValue: 1)
    /// Poll metadata.
    public static let poll = Self(rawValue: 2)
    /// Voice-message metadata.
    public static let voiceMessage = Self(rawValue: 3)
    /// Thread metadata.
    public static let thread = Self(rawValue: 4)
    /// Embed metadata.
    public static let embed = Self(rawValue: 5)
    /// Sticker metadata.
    public static let sticker = Self(rawValue: 6)

    /// Preserves a published or unknown additional-content kind without guessing behavior.
    /// - Parameter rawValue: Any signed 32-bit integer; unknown values remain distinct.
    ///   This synchronous value construction has no side effects or I/O.
    public init(rawValue: Int32) { self.rawValue = rawValue }
}

/// Bounded immutable equivalent of locally constructible Social additional-content metadata.
///
/// This value describes display information supplied by the application. It performs
/// no fetching/rendering and is not a new JSON or SDK event codec. Unknown kinds and
/// nil versus empty titles remain distinct; equality compares all supplied fields.
public struct SocialAdditionalContent: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable {
    /// Published or unknown content kind.
    public let kind: SocialAdditionalContentKind
    /// Optional display title, preserving absence separately from an empty title.
    public let title: String?
    /// Exact published unsigned eight-bit item count, including zero.
    public let count: UInt8

    /// Creates bounded local display metadata without authorizing access to content.
    /// - Parameters:
    ///   - kind: Published or unknown content kind; defaults to other.
    ///   - title: Optional exact display title; defaults to absent. Consumers must
    ///     escape this text for their presentation surface.
    ///   - count: Item count from zero through 255, default zero; no count is inferred.
    ///   - maximumTitleBytes: Nonnegative UTF-8 title budget, default 4,096. Zero
    ///     accepts absent or empty titles. Text is not normalized or truncated.
    /// - Throws: `SocialValueError.invalidStringLimit` for a negative title budget,
    ///   or `.stringLimitExceeded` when a supplied title exceeds that budget.
    ///   Construction is synchronous with no state changes, network or persistence.
    public init(
        kind: SocialAdditionalContentKind = .other, title: String? = nil,
        count: UInt8 = 0, maximumTitleBytes: Int = 4_096
    ) throws {
        guard maximumTitleBytes >= 0 else { throw SocialValueError.invalidStringLimit }
        guard title.map({ $0.utf8.count <= maximumTitleBytes }) ?? true else {
            throw SocialValueError.stringLimitExceeded
        }
        self.kind = kind
        self.title = title
        self.count = count
    }

    /// Conceals display text when metadata is interpolated into ordinary diagnostics.
    public var description: String { "SocialAdditionalContent(redacted)" }

    /// Uses the same redaction for nested debugger-oriented string formatting.
    public var debugDescription: String { description }

    /// Prevents reflective diagnostics from traversing user-controlled display text.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
