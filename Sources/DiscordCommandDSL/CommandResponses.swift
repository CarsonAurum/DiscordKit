import DiscordModels

/// Visibility of an explicit deferred-message acknowledgement. Discord fixes this state when
/// the initial response succeeds; completing the original cannot switch between these cases.
public enum CommandResponseVisibility: Sendable, Equatable {
    case `public`
    case ephemeral
}

/// Validated immediate-message result for `SlashCommandHandler`. This family cannot represent
/// a defer, original edit, modal, autocomplete result or manual responder escape. It wraps the
/// existing message model, preserving its explicit mentions, flags, content and component semantics.
public struct MessageResponse: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let message: InteractionMessageCreate

    /// Validates a complete JSON-only message without acknowledging, executing handlers or performing I/O.
    /// - Parameter message: Existing validated interaction message; ephemeral visibility uses its explicit flags.
    ///   New upload placeholders fail because typed response sinks own no multipart/file transport.
    /// - Throws: Existing complete message/attachment validation errors, including an empty body or missing uploads.
    ///   Nothing is transmitted on failure; the exact existing responder owns later admission and deadlines.
    public init(_ message: InteractionMessageCreate) throws {
        _ = try message.jsonValue()
        self.message = message
    }

    /// Conceals content, mentions, attachments and nested message data from ordinary formatting.
    public var description: String { "MessageResponse(redacted)" }
    /// Preserves the safe marker for debugger string formatting.
    public var debugDescription: String { description }
    /// Prevents reflective traversal into the retained message payload.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Validated original-message edit for `DeferredSlashCommandHandler`. Lowering submits this exactly
/// once through `editOriginal`, after the deferred initial acknowledgement and successful user work.
/// No follow-up, automatic retry, fallback response, hidden hydration or multipart transport is created.
public struct DeferredMessageResponse: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let edit: InteractionMessageEdit

    /// Validates a JSON-only partial original edit without taking acknowledgement or continuation ownership.
    /// - Parameter edit: Existing presence-aware edit; absence preserves, null clears, and empty collections clear.
    ///   Poll creation requires its existing `deferredResponse: true` evidence. Either value is accepted for
    ///   ordinary edits because the route independently verifies actual confirmed deferred ownership.
    ///   Existing retained attachments remain valid; new upload placeholders require a separate transport.
    /// - Throws: Existing edit/attachment validation errors. Visibility cannot be changed through editable flags;
    ///   the existing responder enforces confirmed ownership, overlap, cancellation and token expiry on submission.
    public init(_ edit: InteractionMessageEdit) throws {
        _ = try edit.jsonValue()
        self.edit = edit
    }

    /// Conceals nullable edits, poll text and attachment metadata in ordinary formatting.
    public var description: String { "DeferredMessageResponse(redacted)" }
    /// Uses the same safe marker during debugger string formatting.
    public var debugDescription: String { description }
    /// Prevents reflection from revealing the retained partial-update payload.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
