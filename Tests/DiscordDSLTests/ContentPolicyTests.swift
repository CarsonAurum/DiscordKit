// File: Tests/DiscordDSLTests/ContentPolicyTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordDSL
import DiscordModels
import Testing

/// Exercises finite content capture, injection resistance and explicit notification ownership entirely offline.
@Suite struct ContentPolicyTests {
    /// Literal Markdown and mention-looking markup remain intact while all automatic notifications are disabled.
    @Test func literalsPreserveMarkupWithoutEnablingMentions() throws {
        let content: MessageContent = "**trusted** <@123> <@&456> <#789> @everyone @here"
        let rendered = try content.render()
        #expect(rendered.content == "**trusted** <@123> <@&456> <#789> @everyone @here")
        #expect(rendered.allowedMentions.jsonValue() == .object([
            "parse": .array([]), "replied_user": .bool(false),
        ]))
        #expect(try content.render() == rendered)
    }

    /// Ordinary text neutralizes user/role/channel tokens and every supported Markdown metacharacter.
    @Test func ordinaryInterpolationEscapesMarkupAndMentionIntroducers() throws {
        let untrusted = "\\`*_~|>[]()#+-.!{} <@123> <@&456> <#789> @everyone @here"
        let content: MessageContent = "prefix \(untrusted) suffix"
        let rendered = try content.render()
        #expect(rendered.content == "prefix \\\\\\`\\*\\_\\~\\|\\>\\[\\]\\(\\)\\#\\+\\-\\.\\!\\{\\} <\u{200B}@\u{200B}123\\> <\u{200B}@\u{200B}&456\\> <\u{200B}\\#789\\> @\u{200B}everyone @\u{200B}here suffix")
        #expect(rendered.allowedMentions.users == nil)
        #expect(rendered.allowedMentions.roles == nil)
        #expect(rendered.allowedMentions.parse == [])
    }

    /// A runtime String initializer has the same safe text semantics as ordinary interpolation, including Unicode.
    @Test func dynamicInitializerEscapesButLiteralInitializerDoesNot() throws {
        let source = "**👩🏽‍💻** café e\u{301}\n@here <#1>"
        let dynamic = MessageContent(source)
        let interpolated: MessageContent = "\(source)"
        let trusted = MessageContent(stringLiteral: source)
        #expect(try dynamic.render() == interpolated.render())
        #expect(try dynamic.render().content == "\\*\\*👩🏽‍💻\\*\\* café e\u{301}\n@\u{200B}here <\u{200B}\\#1\\>")
        #expect(try trusted.render().content == source)
        #expect(dynamic != trusted)
    }

    /// Explicit raw interpolation preserves trusted markup while raw mention spellings still enable no selectors.
    @Test func rawInterpolationRequiresExplicitNotificationPolicy() throws {
        let raw = "**trusted** <@123> <@&456> @everyone"
        let content: MessageContent = "\(raw: raw)"
        let rendered = try content.render()
        #expect(rendered.content == raw)
        #expect(rendered.allowedMentions.users == nil)
        #expect(rendered.allowedMentions.roles == nil)
        #expect(rendered.allowedMentions.parse == [])
        #expect(rendered.allowedMentions.repliedUser == false)
    }

    /// Typed references preserve all 64 ID bits, distinguish user/role selectors and never notify channels.
    @Test func typedReferencesSelectOnlyExplicitUserAndRoleIDs() throws {
        let user = UserID(rawValue: UInt64.max)
        let role = RoleID(rawValue: UInt64.max - 1)
        let channel = ChannelID(rawValue: UInt64.max - 2)
        let content: MessageContent = "\(user: user) \(role: role) \(channel: channel)"
        let rendered = try content.render()
        #expect(rendered.content == "<@18446744073709551615> <@&18446744073709551614> <#18446744073709551613>")
        #expect(rendered.allowedMentions.users == [user])
        #expect(rendered.allowedMentions.roles == [role])
        #expect(rendered.allowedMentions.jsonValue() == .object([
            "parse": .array([]), "replied_user": .bool(false),
            "users": .array([.string("18446744073709551615")]),
            "roles": .array([.string("18446744073709551614")]),
        ]))
    }

    /// Deduplication follows the first notifying appearance independently for users and roles.
    @Test func typedSelectorOrderAndDisplayOnlyReferences() throws {
        let first = UserID(rawValue: 9)
        let second = UserID(rawValue: 2)
        let roleFirst = RoleID(rawValue: 8)
        let roleSecond = RoleID(rawValue: 1)
        let content: MessageContent = "\(user: first, notify: false) \(user: second) \(user: first) \(user: second) \(role: roleFirst, notify: false) \(role: roleSecond) \(role: roleFirst) \(role: roleSecond)"
        let rendered = try content.render()
        #expect(rendered.allowedMentions.users == [second, first])
        #expect(rendered.allowedMentions.roles == [roleSecond, roleFirst])
        let displayOnly: MessageContent = "\(user: first, notify: false) \(role: roleFirst, notify: false) \(channel: ChannelID(rawValue: 0))"
        #expect(try displayOnly.render().content == "<@9> <@&8> <#0>")
        #expect(try displayOnly.render().allowedMentions.users == nil)
        #expect(try displayOnly.render().allowedMentions.roles == nil)
    }

    /// Matching IDs cannot turn ordinary interpolated text into additional mentions under a global allow list.
    @Test func untrustedSameIDCannotReuseTypedNotificationPermission() throws {
        let user = UserID(rawValue: 123)
        let role = RoleID(rawValue: 456)
        let attack = "<@123> <@!123> <@&456> @everyone"
        let content: MessageContent = "\(attack) \(user: user) \(role: role)"
        let rendered = try content.render()
        #expect(rendered.content == "<\u{200B}@\u{200B}123\\> <\u{200B}@\u{200B}\\!123\\> <\u{200B}@\u{200B}&456\\> @\u{200B}everyone <@123> <@&456>")
        #expect(rendered.allowedMentions.users == [user])
        #expect(rendered.allowedMentions.roles == [role])
    }

    /// Untrusted digits or suffixes cannot complete mention tokens opened by trusted preceding fragments.
    @Test func interpolationBoundariesCannotCompleteTrustedPartialMentions() throws {
        let digits = "123"
        let tail = "3"
        let everyoneTail = "ryone"
        let hereTail = "re"
        let content: MessageContent = "<@\(digits)> <@12\(tail)> <@&\(digits)> <@!\(digits)> <#\(digits)> @eve\(everyoneTail) @he\(hereTail) \(user: UserID(rawValue: 123)) \(role: RoleID(rawValue: 123))"
        let rendered = try content.render()
        #expect(rendered.content == "<@\u{200B}123> <@12\u{200B}3> <@&\u{200B}123> <@!\u{200B}123> <#\u{200B}123> @eve\u{200B}ryone @he\u{200B}re <@123> <@&123>")
        #expect(rendered.allowedMentions.users == [UserID(rawValue: 123)])
        #expect(rendered.allowedMentions.roles == [RoleID(rawValue: 123)])
        let empty = ""
        let intentionallyTrusted: MessageContent = "<@12\(empty)3> \(user: UserID(rawValue: 123))"
        #expect(try intentionallyTrusted.render().content == "<@123> <@123>")
    }

    /// Boundary state crosses nested/joined values and does not assume an upstream numeric token-length limit.
    @Test func nestedAndJoinedSplitTokensRemainIsolated() throws {
        let untrustedSuffix: String = "123"
        let suffix = MessageContent(untrustedSuffix)
        let joined = MessageContent.joined(["<@", suffix, ">"], separator: "")
        let nested: MessageContent = "\(joined) \(user: UserID(rawValue: 123))"
        let nestedRendered = try nested.render()
        #expect(nestedRendered.content == "<@\u{200B}123> <@123>")
        let longPrefix = MessageContent(stringLiteral: "<@" + String(repeating: "0", count: 100))
        let longSplit = MessageContent.joined([longPrefix, suffix, ">"], separator: "")
        let longRendered = try longSplit.render()
        #expect(longRendered.content == "<@" + String(repeating: "0", count: 100) + "\u{200B}123>")
        let trustedSeparator = MessageContent.joined(["", suffix, ">"], separator: "<@")
        let separatorRendered = try trustedSeparator.render()
        #expect(separatorRendered.content == "<@\u{200B}123<@>")
        let closedAndSpaced: MessageContent = "<@123> \(suffix) @hello \(suffix)"
        #expect(try closedAndSpaced.render().content == "<@123> 123 @hello 123")
    }

    /// Trusted literal/raw duplicate IDs share Discord's global explicit selectors, a documented escape-hatch property.
    @Test func trustedDuplicateMentionTokensRetainGlobalSelectorSemantics() throws {
        let raw = "<@123>"
        let content: MessageContent = "<@123> \(raw: raw) \(user: UserID(rawValue: 123))"
        #expect(try content.render().content == "<@123> <@123> <@123>")
        #expect(try content.render().allowedMentions.users == [UserID(rawValue: 123)])
    }

    /// Joining and nested interpolation retain segment identity instead of escaping rendered markup twice.
    @Test func joiningAndNestingPreserveIntent() throws {
        let unsafe = "**text** <@9>"
        let first: MessageContent = "**literal** \(unsafe) \(user: UserID(rawValue: 9))"
        let second: MessageContent = "\(role: RoleID(rawValue: 4)) \(channel: ChannelID(rawValue: 3))"
        let joined = MessageContent.joined([first, second], separator: " | ")
        let nested: MessageContent = "[\(joined)]"
        #expect(try nested.render().content == "[**literal** \\*\\*text\\*\\* <\u{200B}@\u{200B}9\\> <@9> | <@&4> <#3>]")
        #expect(try nested.render().allowedMentions.users == [UserID(rawValue: 9)])
        #expect(try nested.render().allowedMentions.roles == [RoleID(rawValue: 4)])
        #expect(try MessageContent.joined([first, second]).render().content.contains("\n<@&4>"))
        #expect(try MessageContent.joined([]).render().content.isEmpty)
        #expect(try MessageContent.joined(["", "", ""], separator: "-").render().content == "--")
    }

    /// Empty fragments do not consume admission, and arbitrary sizing hints never allocate or fail on their own.
    @Test func emptyFragmentsAndCapacityHintsAreHarmless() throws {
        var capture = MessageContent.StringInterpolation(literalCapacity: Int.max, interpolationCount: Int.max)
        for _ in 0...MessageContent.maximumSegments {
            capture.appendLiteral("")
            capture.appendInterpolation("")
            capture.appendInterpolation(raw: "")
        }
        let content = MessageContent(stringInterpolation: capture)
        #expect(try content.render().content == "")
        #expect(try MessageContent("").render() == content.render())
        #expect(try MessageContent.joined(Array(repeating: "", count: MessageContent.maximumSegments), separator: "").render() == content.render())
    }

    /// The exact segment boundary succeeds; its next nonempty fragment records an unrecoverable safe failure.
    @Test func segmentLimitIsExactAndSticky() throws {
        var capture = MessageContent.StringInterpolation(literalCapacity: -1, interpolationCount: -1)
        for _ in 0..<MessageContent.maximumSegments { capture.appendLiteral("a") }
        #expect(try MessageContent(stringInterpolation: capture).render().content == String(repeating: "a", count: MessageContent.maximumSegments))
        capture.appendLiteral("b")
        capture.appendInterpolation(raw: String(repeating: "z", count: MessageContent.maximumSourceBytes + 1))
        #expect(throws: MessageContentError.segmentLimit) { try MessageContent(stringInterpolation: capture).render() }
        #expect(throws: MessageContentError.segmentLimit) {
            try MessageContent.joined(Array(repeating: "", count: MessageContent.maximumSegments + 1), separator: "").render()
        }
    }

    /// Bounded source capture handles ASCII, multibyte scalars, trusted text and aggregate joins at exact UTF-8 edges.
    @Test func sourceByteLimitIsExactAndAppliesAcrossSegments() throws {
        let exact = String(repeating: "a", count: MessageContent.maximumSourceBytes)
        #expect(try MessageContent(stringLiteral: exact).render().content == exact)
        let multibyte = String(repeating: "é", count: MessageContent.maximumSourceBytes / 2)
        #expect(try MessageContent(multibyte).render().content == multibyte)
        #expect(throws: MessageContentError.sourceByteLimit) { try MessageContent(exact + "a").render() }
        #expect(throws: MessageContentError.sourceByteLimit) { try MessageContent(stringLiteral: multibyte + "é").render() }
        let raw: MessageContent = "\(raw: exact)"
        #expect(try raw.render().content == exact)
        #expect(throws: MessageContentError.sourceByteLimit) { try MessageContent.joined([raw, "b"], separator: "").render() }
        #expect(throws: MessageContentError.sourceByteLimit) { try MessageContent.joined([raw, ""], separator: "\n").render() }
    }

    /// Escaping has an independent output budget checked before expansion can exceed finite storage.
    @Test func renderedByteLimitAccountsForEscapingExpansion() throws {
        let exact = MessageContent(String(repeating: "*", count: MessageContent.maximumRenderedBytes / 2))
        #expect(try exact.render().content.utf8.count == MessageContent.maximumRenderedBytes)
        let excessive = MessageContent(String(repeating: "*", count: MessageContent.maximumRenderedBytes / 2 + 1))
        #expect(throws: MessageContentError.renderedByteLimit) { try excessive.render() }
        let atExact = MessageContent(String(repeating: "@", count: MessageContent.maximumRenderedBytes / 4))
        #expect(try atExact.render().content.utf8.count == MessageContent.maximumRenderedBytes)
        #expect(throws: MessageContentError.renderedByteLimit) {
            try MessageContent(String(repeating: "@", count: MessageContent.maximumRenderedBytes / 4 + 1)).render()
        }
    }

    /// Invalid child templates poison nested and joined parents rather than quietly returning partial text.
    @Test func captureFailuresPropagateThroughNestedAndJoinedTemplates() throws {
        let invalid = MessageContent(String(repeating: "x", count: MessageContent.maximumSourceBytes + 1))
        let nested: MessageContent = "before \(invalid) after"
        #expect(throws: MessageContentError.sourceByteLimit) { try nested.render() }
        #expect(throws: MessageContentError.sourceByteLimit) { try MessageContent.joined(["before", invalid, "after"]).render() }
        var capture = MessageContent.StringInterpolation(literalCapacity: 0, interpolationCount: 0)
        capture.appendInterpolation(invalid)
        for _ in 0...MessageContent.maximumSegments { capture.appendLiteral("ignored") }
        #expect(throws: MessageContentError.sourceByteLimit) { try MessageContent(stringInterpolation: capture).render() }
    }

    /// Each selector category accepts 100 distinct IDs, deduplicates repeated IDs and rejects its 101st opt-in.
    @Test func notificationSelectorLimitsAreIndependentAndExact() throws {
        var capture = MessageContent.StringInterpolation(literalCapacity: 0, interpolationCount: 0)
        for number in 0..<100 {
            capture.appendInterpolation(user: UserID(rawValue: UInt64(number)))
            capture.appendInterpolation(role: RoleID(rawValue: UInt64(number)))
        }
        capture.appendInterpolation(user: UserID(rawValue: 0))
        capture.appendInterpolation(role: RoleID(rawValue: 0))
        capture.appendInterpolation(user: UserID(rawValue: 100), notify: false)
        capture.appendInterpolation(role: RoleID(rawValue: 100), notify: false)
        let rendered = try MessageContent(stringInterpolation: capture).render()
        #expect(rendered.allowedMentions.users == (0..<100).map { UserID(rawValue: UInt64($0)) })
        #expect(rendered.allowedMentions.roles == (0..<100).map { RoleID(rawValue: UInt64($0)) })
        var usersExceeded = capture
        usersExceeded.appendInterpolation(user: UserID(rawValue: 100))
        #expect(throws: MessageContentError.userMentionLimit) { try MessageContent(stringInterpolation: usersExceeded).render() }
        var rolesExceeded = capture
        rolesExceeded.appendInterpolation(role: RoleID(rawValue: 100))
        #expect(throws: MessageContentError.roleMentionLimit) { try MessageContent(stringInterpolation: rolesExceeded).render() }
    }

    /// Rendering accepts generic text beyond ordinary message limits; existing request models remain authoritative.
    @Test func payloadModelsRetainAuthoritativeWireLengthValidation() throws {
        let ordinaryMaximum = String(repeating: "a", count: 2_000)
        let atMaximum = try MessageContent(ordinaryMaximum).render()
        let valid = try MessageCreate(content: .value(atMaximum.content), allowedMentions: .value(atMaximum.allowedMentions))
        #expect(try valid.jsonValue() == .object([
            "content": .string(ordinaryMaximum), "allowed_mentions": atMaximum.allowedMentions.jsonValue(),
        ]))
        let beyondMaximum = try MessageContent(ordinaryMaximum + "a").render()
        #expect(beyondMaximum.content.count == 2_001)
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try MessageCreate(content: .value(beyondMaximum.content), allowedMentions: .value(beyondMaximum.allowedMentions))
        }
    }

    /// Wire lengths count Unicode scalars rather than graphemes or UTF-8 bytes, including combining sequences.
    @Test func payloadUnicodeScalarBoundariesStayInExistingValidation() throws {
        let exactText = String(repeating: "e\u{301}", count: 1_000)
        let exact = try MessageContent(exactText).render()
        #expect(exact.content.count == 1_000)
        #expect(exact.content.unicodeScalars.count == 2_000)
        #expect(exact.content.utf8.count == 3_000)
        #expect(try MessageCreate(content: .value(exact.content)).jsonValue() == .object(["content": .string(exactText)]))
        let excessive = try MessageContent(exactText + "\u{301}").render()
        #expect(excessive.content.count == 1_000)
        #expect(throws: DiscordError.validation(.limitExceeded)) {
            try MessageCreate(content: .value(excessive.content))
        }
    }

    /// Ordinary/debug/reflection paths conceal message data while explicit rendering remains observable.
    @Test func formattingAndReflectionDoNotExposeCapturedOrRenderedContent() throws {
        var interpolation = MessageContent.StringInterpolation(literalCapacity: 0, interpolationCount: 0)
        interpolation.appendLiteral("sensitive-message")
        interpolation.appendInterpolation(user: UserID(rawValue: UInt64.max))
        let captured = MessageContent(stringInterpolation: interpolation)
        let rendered = try captured.render()
        #expect(interpolation.description == "MessageContent.StringInterpolation(redacted)")
        #expect(interpolation.debugDescription == interpolation.description)
        #expect(captured.description == "MessageContent(redacted)")
        #expect(captured.debugDescription == captured.description)
        #expect(rendered.description == "RenderedMessageContent(redacted)")
        #expect(rendered.debugDescription == rendered.description)
        #expect(interpolation.customMirror.children.count == 1)
        #expect(captured.customMirror.children.count == 1)
        #expect(rendered.customMirror.children.count == 1)
        #expect(interpolation.customMirror.children.first?.label == "redacted")
        #expect(captured.customMirror.children.first?.label == "redacted")
        #expect(rendered.customMirror.children.first?.label == "redacted")
        #expect(String(reflecting: interpolation) == interpolation.debugDescription)
        #expect(String(reflecting: captured) == captured.debugDescription)
        #expect(String(reflecting: rendered) == rendered.debugDescription)
        #expect(rendered.content == "sensitive-message<@18446744073709551615>")
    }
}
