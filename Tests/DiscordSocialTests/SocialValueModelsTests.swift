import DiscordCore
import Testing
@testable import DiscordSocial

/// Deterministic local metadata tests; no native SDK, remote provider or device is used.
@Suite struct SocialValueModelsTests {
    /// Known values match the current published enums; unknown integers remain distinct.
    /// - Parameter raw: Signed boundary or unknown integer, retained without behavior inference.
    @Test(arguments: [Int32.min, -1, 0, 1, 5, 6, Int32.max])
    func unknownKinds(_ raw: Int32) {
        #expect(SocialActivityAction(rawValue: raw).rawValue == raw)
        #expect(SocialAdditionalContentKind(rawValue: raw).rawValue == raw)
        #expect(SocialActivityAction.invalid.rawValue == 0)
        #expect(SocialActivityAction.join.rawValue == 1)
        #expect(SocialActivityAction.joinRequest.rawValue == 5)
        #expect([
            SocialAdditionalContentKind.other, .attachment, .poll, .voiceMessage, .thread, .embed, .sticker,
        ].map(\.rawValue) == [0, 1, 2, 3, 4, 5, 6])
    }

    /// Full unsigned identifiers and all invite fields remain intact, with redacted logs.
    /// Reconstructing a value replaces metadata without retaining native handle identity.
    @Test func inviteFieldsAndReplacement() throws {
        let invite = try SocialActivityInvite(
            senderID: UserID(rawValue: .max), channelID: ChannelID(rawValue: 2),
            messageID: MessageID(rawValue: 3), action: .joinRequest,
            applicationID: ApplicationID(rawValue: 4), parentApplicationID: ApplicationID(rawValue: 5),
            partyID: "party", sessionID: "session", isValid: true, maximumStringBytes: 12
        )
        #expect(invite.senderID.rawValue == .max)
        #expect(invite.channelID.rawValue == 2)
        #expect(invite.messageID.rawValue == 3)
        #expect(invite.action == .joinRequest)
        #expect(invite.applicationID.rawValue == 4)
        #expect(invite.parentApplicationID?.rawValue == 5)
        #expect(invite.partyID == "party")
        #expect(invite.sessionID == "session")
        #expect(invite.isValid)
        #expect(invite.description == "SocialActivityInvite(redacted)")
        #expect(String(reflecting: invite) == "SocialActivityInvite(redacted)")
        #expect(invite.customMirror.children.map(\.label) == ["redacted"])
        let replacement = try SocialActivityInvite(
            senderID: invite.senderID, channelID: invite.channelID, messageID: invite.messageID,
            action: invite.action, applicationID: invite.applicationID,
            parentApplicationID: invite.parentApplicationID, partyID: invite.partyID,
            sessionID: invite.sessionID, isValid: false
        )
        #expect(replacement != invite)
        #expect(invite.isValid)
        #expect(!replacement.isValid)
    }

    /// Zero identifiers and empty metadata remain representable without implying validity.
    @Test func unsetInviteAndExactUTF8Bounds() throws {
        let empty = try SocialActivityInvite(
            senderID: UserID(rawValue: 0), channelID: ChannelID(rawValue: 0),
            messageID: MessageID(rawValue: 0), applicationID: ApplicationID(rawValue: 0), maximumStringBytes: 0
        )
        #expect(empty.senderID.rawValue == 0 && empty.channelID.rawValue == 0 && empty.messageID.rawValue == 0)
        #expect(empty.applicationID.rawValue == 0 && empty.parentApplicationID == nil)
        #expect(empty.action == .invalid && !empty.isValid)
        #expect(empty.partyID.isEmpty && empty.sessionID.isEmpty)
        let unicode = try SocialActivityInvite(
            senderID: .init(rawValue: 1), channelID: .init(rawValue: 2), messageID: .init(rawValue: 3),
            applicationID: .init(rawValue: 4), partyID: "é", sessionID: "🐾", maximumStringBytes: 6
        )
        #expect(unicode.partyID == "é" && unicode.sessionID == "🐾")
        #expect(throws: SocialValueError.stringLimitExceeded) {
            try SocialActivityInvite(
                senderID: .init(rawValue: 1), channelID: .init(rawValue: 2), messageID: .init(rawValue: 3),
                applicationID: .init(rawValue: 4), partyID: "é", sessionID: "🐾", maximumStringBytes: 5
            )
        }
        #expect(throws: SocialValueError.stringLimitExceeded) {
            try SocialActivityInvite(
                senderID: .init(rawValue: 1), channelID: .init(rawValue: 2), messageID: .init(rawValue: 3),
                applicationID: .init(rawValue: 4), partyID: "x", maximumStringBytes: 0
            )
        }
        #expect(throws: SocialValueError.invalidStringLimit) {
            try SocialActivityInvite(
                senderID: .init(rawValue: 1), channelID: .init(rawValue: 2), messageID: .init(rawValue: 3),
                applicationID: .init(rawValue: 4), maximumStringBytes: -1
            )
        }
    }

    /// Additional-content optionality, all count boundaries and immutable equality are exact.
    /// - Parameter count: Published unsigned eight-bit count boundary or ordinary value.
    @Test(arguments: [UInt8(0), 1, 255])
    func additionalContentOptionalityAndBounds(_ count: UInt8) throws {
        let absent = try SocialAdditionalContent(count: count, maximumTitleBytes: 0)
        let empty = try SocialAdditionalContent(title: "", count: count, maximumTitleBytes: 0)
        #expect(absent.kind == .other && absent.title == nil && absent.count == count)
        #expect(empty.title == "" && empty != absent)
        let value = try SocialAdditionalContent(kind: .sticker, title: "é", count: count, maximumTitleBytes: 2)
        #expect(value.kind == .sticker && value.title == "é" && value.count == count)
        #expect(value == (try SocialAdditionalContent(kind: .sticker, title: "é", count: count)))
        #expect(value.description == "SocialAdditionalContent(redacted)")
        #expect(String(reflecting: value) == "SocialAdditionalContent(redacted)")
        #expect(value.customMirror.children.map(\.label) == ["redacted"])
        #expect(throws: SocialValueError.stringLimitExceeded) {
            try SocialAdditionalContent(title: "é", maximumTitleBytes: 1)
        }
        #expect(throws: SocialValueError.invalidStringLimit) {
            try SocialAdditionalContent(maximumTitleBytes: -1)
        }
    }
}
