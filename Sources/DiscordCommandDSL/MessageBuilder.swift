// File: Sources/DiscordCommandDSL/MessageBuilder.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordDSL
import DiscordModels

/// A finite message contribution, evaluated synchronously and lowered through existing interaction models.
/// Conforming values describe authoring data; they never acquire response, registration or transport ownership.
public protocol MessageBuilderValue: Sendable {
    /// Finite ordered structural contribution, without invoking a command or performing I/O.
    var messageBody: MessageBody {
        /// Returns the synchronous finite contribution without taking response or runtime ownership.
        get
    }
}

/// Safe message content contribution. Multiple text contributions are joined by a single newline in source order.
public struct Text: MessageBuilderValue {
    private let content: MessageContent

    /// Retains safe interpolated content without rendering, acknowledging or executing handlers.
    /// - Parameter content: Text whose typed mentions contribute to the complete message's explicit allowlist.
    public init(_ content: MessageContent) { self.content = content }

    /// Returns the inert text contribution; output limits are enforced when constructing the response.
    public var messageBody: MessageBody { MessageBody(.text(content)) }
}

/// Exact existing rich embed contribution; Models remains authoritative for writable fields and aggregate bounds.
public struct Embed: MessageBuilderValue {
    private let embed: MessageEmbed

    /// Adopts an existing embed without changing missing, null or unknown fields.
    /// - Parameter embed: Typed existing model; response-only/unsupported outgoing data is rejected on lowering.
    public init(_ embed: MessageEmbed) { self.embed = embed }

    /// Returns an inert embed contribution without serializing or sending it.
    public var messageBody: MessageBody { MessageBody(.embed(embed)) }
}

/// An explicitly present ordered component replacement with independently selectable legacy or V2 grammar.
/// An empty value clears components on edit; multiple contributions must agree on an explicit mode.
public struct Components: MessageBuilderValue {
    private let components: ComponentList
    private let mode: MessageComponentMode

    /// Evaluates a synchronous component builder without executing handlers or opening resources.
    /// - Parameters:
    ///   - mode: Automatic by default; non-row top-level nodes or observed prior V2 flags require V2.
    ///     Explicit legacy rejects existing V2 state, and complete requests validate the selected grammar.
    ///   - content: Finite ordered component declarations, supporting branches, arrays and loops.
    public init(mode: MessageComponentMode = .automatic, @ComponentBuilder _ content: () -> ComponentList) {
        components = content(); self.mode = mode
    }

    /// Returns a finite inert component contribution; complete contextual validation occurs in the response initializer.
    public var messageBody: MessageBody { MessageBody(.components(components, mode)) }
}

/// Bounded message builder storage, retaining at most sixty-four contributions and sticky overflow evidence.
/// Bounds constrain retained authoring data; they cannot interrupt arbitrary work or infinite loops in user closures.
public struct MessageBody: MessageBuilderValue, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private var elements: [MessageElement] = []
    private var invalid = false

    /// Starts an empty structural block without evaluating handlers or performing I/O.
    init() {}

    /// Retains one explicit contribution, preserving its field identity and source order.
    /// - Parameter element: Inert text, embed or component contribution.
    fileprivate init(_ element: MessageElement) { elements = [element] }

    /// Appends finite fragments and preserves overflow even when excess retained declarations are dropped.
    /// - Parameter other: Next ordered contribution block; at most sixty-four elements are stored in total.
    mutating func append(_ other: MessageBody) {
        invalid = invalid || other.invalid || other.elements.count > 64 - elements.count
        elements.append(contentsOf: other.elements.prefix(max(0, 64 - elements.count)))
    }

    /// Returns this finite block for composition by helper functions without changing its admission evidence.
    public var messageBody: MessageBody { self }

    /// Lowers a complete declaration into exact existing model fields and an aggregate mention policy.
    /// - Parameters:
    ///   - override: Optional explicit whole-message parsing policy, replacing the safe derived allowlist.
    ///   - existingComponentsV2: Whether observed prior message flags already require the V2 grammar; defaults to false.
    ///     Automatic mode honors this state, while an explicit legacy declaration fails instead of requesting a downgrade.
    /// - Returns: Presence-aware existing-model fields; omitted text/embeds/components stay omitted.
    /// - Throws: Safe authoring overflow, conflicting modes, invalid text/mentions, JSON budget or model errors.
    ///   Models validates final field combinations, count limits and component placement in the response initializer.
    fileprivate func lower(override: MessageAllowedMentions?, existingComponentsV2: Bool = false) throws -> LoweredMessageBody {
        guard !invalid else { throw DiscordError.validation(.invalidValue) }
        var texts: [MessageContent] = [], embeds: [MessageEmbed] = [], components: [MessageComponent] = []
        var policies: [MessageAllowedMentions] = [], hasComponents = false
        var explicitMode: MessageComponentMode?
        for element in elements {
            switch element {
            case .text(let content):
                texts.append(content)
                policies.append(try content.render().allowedMentions)
            case .embed(let embed): embeds.append(embed)
            case .components(let list, let mode):
                guard !list.invalid else { throw DiscordError.validation(.invalidValue) }
                hasComponents = true
                if mode != .automatic {
                    guard explicitMode == nil || explicitMode == mode else { throw DiscordError.validation(.invalidValue) }
                    explicitMode = mode
                }
                for component in list.values { components.append(try component.lower(mentions: &policies)) }
                guard components.count <= 40 else { throw DiscordError.validation(.invalidValue) }
            }
        }
        let content: Field<String>
        if texts.isEmpty { content = .absent }
        else {
            let rendered = try MessageContent.joined(texts).render()
            content = .value(rendered.content)
        }
        guard !existingComponentsV2 || explicitMode != .legacy else { throw DiscordError.validation(.invalidValue) }
        let declaredV2 = explicitMode == .v2 || (explicitMode == nil && components.contains { $0.type.knownValue != .actionRow })
        let v2 = existingComponentsV2 || declaredV2
        if hasComponents {
            _ = try JSONValue.array(try components.map { try $0.jsonValue() }).serialized(limits: componentJSONLimits)
            try MessageComponent.validateMessage(components, componentsV2: v2)
        }
        let mentions: Field<MessageAllowedMentions>
        if let override { mentions = .value(override) }
        else if !texts.isEmpty || hasComponents { mentions = .value(try mergedMentionPolicy(policies)) }
        else { mentions = .absent }
        return LoweredMessageBody(content: content, embeds: embeds.isEmpty ? .absent : .value(embeds),
            allowedMentions: mentions, components: hasComponents ? .value(components) : .absent, componentsV2: declaredV2)
    }

    /// Conceals retained content, embeds and identities during ordinary formatting.
    public var description: String { "MessageBody(redacted)" }
    /// Uses the same redacted marker for debugger formatting.
    public var debugDescription: String { description }
    /// Prevents reflection from traversing retained authoring data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Exact inert contribution storage; field presence remains separate from string/array emptiness.
private enum MessageElement: Sendable {
    case text(MessageContent)
    case embed(MessageEmbed)
    case components(ComponentList, MessageComponentMode)
}

/// Presence-aware fields consumed only by existing interaction request initializers.
private struct LoweredMessageBody {
    let content: Field<String>
    let embeds: Field<[MessageEmbed]>
    let allowedMentions: Field<MessageAllowedMentions>
    let components: Field<[MessageComponent]>
    let componentsV2: Bool
}

/// Joins safe typed mention allowlists in first-use order without enabling broad automatic parsing.
/// - Parameter policies: Safe rendered text policies; repeated user/role identities are deduplicated globally.
/// - Returns: Explicit parse-empty/reply-disabled policy with at most one hundred user and role identities.
/// - Throws: Existing mention policy validation errors, including either aggregate list exceeding one hundred IDs.
private func mergedMentionPolicy(_ policies: [MessageAllowedMentions]) throws -> MessageAllowedMentions {
    var users: [UserID] = [], roles: [RoleID] = [], seenUsers = Set<UserID>(), seenRoles = Set<RoleID>()
    for policy in policies {
        for user in policy.users ?? [] where seenUsers.insert(user).inserted {
            users.append(user)
            guard users.count <= 100 else { throw DiscordError.validation(.invalidValue) }
        }
        for role in policy.roles ?? [] where seenRoles.insert(role).inserted {
            roles.append(role)
            guard roles.count <= 100 else { throw DiscordError.validation(.invalidValue) }
        }
    }
    return try MessageAllowedMentions(parse: [], roles: roles.isEmpty ? nil : roles,
        users: users.isEmpty ? nil : users, repliedUser: false)
}

/// Finite message declaration builder. Structural evaluation starts no tasks, handler execution, registration or I/O.
/// All branches, arrays and loops preserve declaration order; overflow fails at response construction.
@resultBuilder public enum MessageBuilder {
    /// Adopts one finite text/embed/components contribution or another prebuilt body.
    /// - Parameter expression: Inert contribution whose structural accessor is evaluated synchronously.
    /// - Returns: Its finite structural body, without lowering or transmitting payloads.
    public static func buildExpression<Value: MessageBuilderValue>(_ expression: Value) -> MessageBody { expression.messageBody }

    /// Adopts a homogeneous ordered array without retaining more than sixty-four contributions.
    /// - Parameter expression: Finite contributions; overflow is sticky and rejects the whole response later.
    /// - Returns: Bounded ordered body.
    public static func buildExpression<Value: MessageBuilderValue>(_ expression: [Value]) -> MessageBody {
        var result = MessageBody()
        for element in expression { result.append(element.messageBody) }
        return result
    }

    /// Starts an incremental declaration block.
    /// - Parameter first: First finite contribution body.
    /// - Returns: Unchanged body without executing command work.
    public static func buildPartialBlock(first: MessageBody) -> MessageBody { first }

    /// Combines adjacent fragments in source order with sticky overflow evidence.
    /// - Parameters:
    ///   - accumulated: Prior finite body.
    ///   - next: Next finite body, appended after prior declarations.
    /// - Returns: A body retaining at most sixty-four contributions.
    public static func buildPartialBlock(accumulated: MessageBody, next: MessageBody) -> MessageBody {
        var result = accumulated; result.append(next); return result
    }

    /// Supplies an empty message declaration; immediate response validation still rejects an empty payload.
    /// - Returns: Empty body, suitable for a no-op deferred edit.
    public static func buildBlock() -> MessageBody { MessageBody() }

    /// Includes an optional branch without evaluating an omitted branch.
    /// - Parameter component: Present body or nil for omission.
    /// - Returns: The branch or an empty declaration.
    public static func buildOptional(_ component: MessageBody?) -> MessageBody { component ?? MessageBody() }

    /// Includes the selected first branch.
    /// - Parameter component: Already evaluated first branch.
    /// - Returns: Unchanged finite body.
    public static func buildEither(first component: MessageBody) -> MessageBody { component }

    /// Includes the selected second branch.
    /// - Parameter component: Already evaluated second branch.
    /// - Returns: Unchanged finite body.
    public static func buildEither(second component: MessageBody) -> MessageBody { component }

    /// Flattens finite loop iterations while preserving order and sticky overflow.
    /// - Parameter components: Iteration bodies created synchronously by Swift's builder lowering.
    /// - Returns: A finite combined declaration.
    public static func buildArray(_ components: [MessageBody]) -> MessageBody {
        var result = MessageBody()
        for component in components { result.append(component) }
        return result
    }

    /// Preserves an availability-checked branch as finite authoring data.
    /// - Parameter component: Available branch's body.
    /// - Returns: Unchanged declaration without runtime ownership.
    public static func buildLimitedAvailability(_ component: MessageBody) -> MessageBody { component }
}

extension MessageResponse {
    /// Builds and validates a complete JSON-only interaction message through existing Models, before admission.
    /// - Parameters:
    ///   - visibility: Public by default; ephemeral sets the existing immutable initial-response visibility flag.
    ///   - allowedMentions: Optional explicit whole-message override. Nil derives a parse-empty typed-ID allowlist;
    ///     raw component markup cannot enable notifications implicitly. Explicit overrides retain Models semantics.
    ///   - content: Synchronous finite message builder. Text blocks join with newlines; embeds/components preserve order.
    /// - Throws: Authoring count/depth/byte errors, safe interpolation errors and all existing complete-message errors,
    ///   including content/embed/V2 conflicts, invalid layouts, empty creates or unsupported upload associations.
    ///   Construction starts no tasks, acknowledgement, registration or transport; existing response owners send later.
    public init(visibility: CommandResponseVisibility = .public, allowedMentions: MessageAllowedMentions? = nil,
                @MessageBuilder _ content: () -> MessageBody) throws {
        let fields = try content().lower(override: allowedMentions)
        var flags: InteractionMessageFlags = []
        if visibility == .ephemeral { flags.insert(.ephemeral) }
        if fields.componentsV2 { flags.insert(.isComponentsV2) }
        let message = try InteractionMessageCreate(content: fields.content, embeds: fields.embeds,
            allowedMentions: fields.allowedMentions, components: fields.components,
            flags: flags.isEmpty ? .absent : .value(flags))
        _ = try message.jsonValue().serialized(limits: componentJSONLimits)
        try self.init(message)
    }
}

extension DeferredMessageResponse {
    /// Builds a JSON-only deferred-original edit while preserving every undeclared message field.
    /// - Parameters:
    ///   - previousFlags: Optional explicitly observed flags for retaining immutable bits and existing V2 state;
    ///     automatic component mode honors existing V2 state, and explicit legacy mode rejects it. No hidden fetch
    ///     occurs. Changing visibility is forbidden by the existing edit model.
    ///   - allowedMentions: Optional explicit parsing override; nil derives a safe typed-ID policy for declared text/components.
    ///   - content: Synchronous finite declaration. Empty Text writes an empty string, empty Components clears components,
    ///     and undeclared fields remain absent. Use the existing raw initializer for explicit nulls or other edit fields.
    /// - Throws: Safe authoring/text/JSON errors and existing partial-edit/state-transition validation errors.
    ///   V2 migration requires explicit clearing of old incompatible fields through the existing model initializer.
    ///   Construction takes no response authority, starts no tasks and performs no requests.
    public init(previousFlags: UInt64? = nil, allowedMentions: MessageAllowedMentions? = nil,
                @MessageBuilder _ content: () -> MessageBody) throws {
        let fields = try content().lower(override: allowedMentions, existingComponentsV2: (previousFlags ?? 0) & (1 << 15) != 0)
        let flags: Field<MessageEditFlags> = fields.componentsV2
            ? .value(MessageEditFlags(rawValue: (previousFlags ?? 0) | (1 << 15))) : .absent
        let edit = try InteractionMessageEdit(content: fields.content, embeds: fields.embeds,
            allowedMentions: fields.allowedMentions, components: fields.components, flags: flags,
            deferredResponse: true, previousFlags: previousFlags)
        _ = try edit.jsonValue().serialized(limits: componentJSONLimits)
        try self.init(edit)
    }
}
