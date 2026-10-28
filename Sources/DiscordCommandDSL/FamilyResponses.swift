// File: Sources/DiscordCommandDSL/FamilyResponses.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordModels

/// Immediate command callbacks, constrained separately from component and modal submissions.
/// Implementations return a validated message or modal. Lowering validates the allowed callback
/// again before using the existing unique responder; no implementation acquires response ownership.
public protocol CommandInitialResponse: Sendable {
    var interactionResponse: InteractionResponse {
        /// Returns one inert message or modal callback without I/O or acknowledgement.
        get
    }
}

/// Immediate component callbacks: a new message, source-message update, or modal.
public protocol ComponentInitialResponse: Sendable {
    var interactionResponse: InteractionResponse {
        /// Returns the inert callback; the source message and existing lifecycle remain authoritative.
        get
    }
}

/// Immediate modal-submit callbacks: a new message or update of an attached source message.
/// A modal cannot produce another modal through this protocol's supplied response wrappers.
public protocol ModalInitialResponse: Sendable {
    static var requiresSourceMessage: Bool {
        /// Reports whether input admission must require a triggering message before user execution.
        get
    }
    var interactionResponse: InteractionResponse {
        /// Returns the inert callback without taking acknowledgement or continuation ownership.
        get
    }
}

public extension ModalInitialResponse {
    /// Permits message-less modal submissions unless the response family explicitly requires an update.
    static var requiresSourceMessage: Bool { false }
}

extension MessageResponse: CommandInitialResponse, ComponentInitialResponse, ModalInitialResponse {
    /// Wraps the already validated message without transmitting it or changing visibility.
    public var interactionResponse: InteractionResponse { .message(message) }
}

/// An already validated modal callback, available to commands and component handlers only.
public struct ModalResponse: CommandInitialResponse, ComponentInitialResponse,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let modal: InteractionModal

    /// Retains a validated modal without executing its later submission handler or performing I/O.
    /// - Parameter modal: Finite existing-model modal; construction has already validated its component tree.
    public init(_ modal: InteractionModal) { self.modal = modal }

    /// Returns a type-9 callback without acknowledging or opening any UI locally.
    public var interactionResponse: InteractionResponse { .modal(modal) }
    /// Conceals custom IDs and nested field defaults in ordinary formatting.
    public var description: String { "ModalResponse(redacted)" }
    /// Preserves redaction for debugger formatting.
    public var debugDescription: String { description }
    /// Prevents reflection from traversing retained modal content.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Validated immediate source-message edit, available only to components and modal submissions.
/// A modal update additionally requires a triggering message, checked before invoking its handler.
public struct UpdateMessageResponse: ComponentInitialResponse, ModalInitialResponse,
    CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let edit: InteractionMessageEdit
    /// Requires an attached source message before a modal update handler is allowed to execute.
    public static var requiresSourceMessage: Bool { true }

    /// Validates an immediate JSON-only update while preserving absent/null/value edit semantics.
    /// - Parameter edit: Existing edit with `deferredResponse` false; new multipart uploads are unsupported.
    /// - Throws: Existing update validation errors, including deferred-only edits and upload placeholders.
    public init(_ edit: InteractionMessageEdit) throws {
        _ = try InteractionResponse.update(edit).jsonValue(interactionType: .messageComponent)
        self.edit = edit
    }

    /// Returns the already validated type-7 callback without transmitting it.
    public var interactionResponse: InteractionResponse { .update(edit) }
    /// Conceals content and retained attachment metadata.
    public var description: String { "UpdateMessageResponse(redacted)" }
    /// Preserves redaction during debugger formatting.
    public var debugDescription: String { description }
    /// Prevents reflective traversal of submitted edits.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}
