// File: Sources/DiscordCommandDSL/ComponentBuilder.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordDSL
import DiscordModels

/// Explicit message component grammar. Automatic mode selects V2 for non-row top-level nodes or observed existing V2 state.
/// Explicit legacy mode rejects an already-V2 deferred message because the flag cannot be removed.
/// The existing Models validator remains authoritative for placement, identities and flag compatibility.
public enum MessageComponentMode: Sendable, Equatable {
    case automatic
    case legacy
    case v2
}

/// Typed interactive button styles; URL and premium buttons use their dedicated factories.
public enum ComponentButtonStyle: Int, Sendable { case primary = 1, secondary, success, danger }

/// Auto-populated select families supported in message action rows.
public enum ComponentSelectKind: Int, Sendable { case user = 5, role, mentionable, channel }

/// A bounded, inert component declaration, lowered through the existing `MessageComponent` projection.
/// Factories allocate no tasks or I/O. They deliberately postpone contextual validation until response construction.
/// Raw model adoption covers supported layouts without introducing a parallel outgoing wire contract.
public struct Component: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let declaration: ComponentDeclaration
    let count: Int
    let depth: Int
    let invalid: Bool

    /// Adopts an exact existing component without changing any omitted, null or unknown field.
    /// - Parameter component: Immutable existing model; unsupported outgoing fields still fail final validation.
    public init(_ component: MessageComponent) {
        declaration = .raw(component); count = 1; depth = 1; invalid = false
    }

    /// Retains one finite declaration; children and accessories contribute to sticky count/depth admission.
    /// - Parameters:
    ///   - fields: Existing component-schema fields, including the integral discriminator.
    ///   - children: Optional ordered nested declarations; omission differs from an explicit empty list.
    ///   - accessory: Optional section accessory, retained without executing work.
    ///   - text: Safe interpolated text, rendered only during response validation.
    private init(fields: [String: JSONValue], children: ComponentList? = nil,
                 accessory: Component? = nil, text: MessageContent? = nil) {
        let nestedCount = (children?.count ?? 0) + (accessory?.count ?? 0)
        let nestedDepth = max(children?.depth ?? 0, accessory?.depth ?? 0)
        count = min(41, 1 + nestedCount); depth = min(9, 1 + nestedDepth)
        invalid = children?.invalid == true || accessory?.invalid == true || count > 40 || depth > 8
        declaration = .definition(fields, children, accessory, text)
    }

    /// Declares an action row containing one select or one through five buttons; Models checks that grammar.
    /// - Parameter content: Synchronous ordered builder supporting branches, arrays and finite loops.
    /// - Returns: An inert row. Invalid/overflowed children remain rejected rather than silently truncated.
    public static func actionRow(@ComponentBuilder _ content: () -> ComponentList) -> Component {
        Component(fields: ["type": componentNumber(1)], children: content())
    }

    /// Declares a standard interaction button without registering a component handler.
    /// - Parameters:
    ///   - label: Visible label; Models enforces its 80-scalar maximum.
    ///   - customID: Explicit returned interaction identity, validated as 1...100 scalars and globally unique.
    ///   - style: Standard button style; defaults to primary.
    ///   - disabled: Explicit enabled state; defaults to false.
    /// - Returns: An inert button requiring a valid row or section parent.
    public static func button(_ label: String, customID: String,
                              style: ComponentButtonStyle = .primary, disabled: Bool = false) -> Component {
        Component(fields: ["type": componentNumber(2), "style": componentNumber(style.rawValue),
            "label": .string(label), "custom_id": .string(customID), "disabled": .bool(disabled)])
    }

    /// Declares a URL button without fetching or navigating to the URL.
    /// - Parameters:
    ///   - label: Visible label, limited by Models to 80 scalars.
    ///   - url: Explicit nonempty URL text, limited by Models to 512 scalars; no network request occurs.
    ///   - disabled: Explicit disabled state; defaults to false.
    /// - Returns: An inert link-style button with no custom interaction identity.
    public static func linkButton(_ label: String, url: String, disabled: Bool = false) -> Component {
        Component(fields: ["type": componentNumber(2), "style": componentNumber(5), "label": .string(label),
            "url": .string(url), "disabled": .bool(disabled)])
    }

    /// Declares a premium SKU button without performing purchase or entitlement work.
    /// - Parameters:
    ///   - skuID: Exact SKU snowflake, serialized without numeric rounding.
    ///   - disabled: Explicit disabled state; defaults to false.
    /// - Returns: An inert premium button with no forbidden label, URL or custom ID.
    public static func premiumButton(skuID: SKUID, disabled: Bool = false) -> Component {
        Component(fields: ["type": componentNumber(2), "style": componentNumber(6), "sku_id": .string(skuID.description),
            "disabled": .bool(disabled)])
    }

    /// Declares a string select using exact existing option values; option count/defaults remain model validated.
    /// - Parameters:
    ///   - customID: Explicit interaction identity, 1...100 scalars and globally unique.
    ///   - options: Existing typed options; Models checks 1...25 entries, labels, values and uniqueness.
    ///   - placeholder: Optional visible placeholder; nil omits it.
    ///   - minimum: Minimum selected entries, default one; Models checks 0...25 and ordering.
    ///   - maximum: Maximum selected entries, default one; Models checks available options and 1...25.
    ///   - disabled: Explicit disabled state, default false.
    /// - Returns: An inert menu requiring its own action row.
    public static func stringSelect(customID: String, options: [ComponentOption], placeholder: String? = nil,
                                    minimum: Int = 1, maximum: Int = 1, disabled: Bool = false) -> Component {
        var fields: [String: JSONValue] = ["type": componentNumber(3), "custom_id": .string(customID),
            "options": .array(options.prefix(26).map { .object($0.rawFields) }),
            "min_values": componentNumber(minimum),
            "max_values": componentNumber(maximum), "disabled": .bool(disabled)]
        if let placeholder { fields["placeholder"] = .string(placeholder) }
        return Component(fields: fields)
    }

    /// Declares one of Discord's auto-populated select menus without loading any entities.
    /// - Parameters:
    ///   - kind: Explicit user, role, mentionable or channel family.
    ///   - customID: Globally unique developer identity of 1...100 scalars.
    ///   - placeholder: Optional visible placeholder; nil omits it.
    ///   - minimum: Minimum selected entries, default one, validated as 0...25.
    ///   - maximum: Maximum selected entries, default one, validated as 1...25 and at least minimum.
    ///   - disabled: Explicit disabled state, default false.
    /// - Returns: An inert select; richer defaults/channel filters remain available through raw model adoption.
    public static func select(_ kind: ComponentSelectKind, customID: String, placeholder: String? = nil,
                              minimum: Int = 1, maximum: Int = 1, disabled: Bool = false) -> Component {
        var fields: [String: JSONValue] = ["type": componentNumber(kind.rawValue),
            "custom_id": .string(customID), "min_values": componentNumber(minimum),
            "max_values": componentNumber(maximum), "disabled": .bool(disabled)]
        if let placeholder { fields["placeholder"] = .string(placeholder) }
        return Component(fields: fields)
    }

    /// Declares V2 display text with safe interpolation and aggregate message mention ownership.
    /// - Parameter content: Safe text; typed user/role interpolations contribute to the message allowlist.
    /// - Returns: An inert text display. Response construction validates V2 field conflicts and finite JSON resources.
    public static func textDisplay(_ content: MessageContent) -> Component {
        Component(fields: ["type": componentNumber(10)], text: content)
    }

    /// Declares a V2 section without allowing accessory fields to escape complete model validation.
    /// - Parameters:
    ///   - accessory: Button or raw thumbnail declaration; Models rejects every other accessory kind.
    ///   - content: Ordered builder; Models requires one through three text displays.
    /// - Returns: An inert section whose children, accessory and IDs share global message limits.
    public static func section(accessory: Component, @ComponentBuilder _ content: () -> ComponentList) -> Component {
        Component(fields: ["type": componentNumber(9)], children: content(), accessory: accessory)
    }

    /// Declares a V2 container; nested containers and unsupported children are rejected by Models.
    /// - Parameters:
    ///   - accentColor: Optional RGB integer in 0...0xFFFFFF; nil omits the color.
    ///   - spoiler: Explicit spoiler state, default false.
    ///   - content: Ordered child builder supporting branches and finite loops.
    /// - Returns: An inert layout container, sharing the message's forty-node admission limit.
    public static func container(accentColor: Int? = nil, spoiler: Bool = false,
                                 @ComponentBuilder _ content: () -> ComponentList) -> Component {
        var fields: [String: JSONValue] = ["type": componentNumber(17), "spoiler": .bool(spoiler)]
        if let accentColor { fields["accent_color"] = componentNumber(accentColor) }
        return Component(fields: fields, children: content())
    }

    /// Declares a V2 visual separator with finite documented spacing values checked during lowering.
    /// - Parameters:
    ///   - divider: Whether a divider line is visible; defaults to true.
    ///   - spacing: Documented small (1) or large (2) spacing; defaults to one.
    /// - Returns: An inert separator, valid at top level or in a V2 container.
    public static func separator(divider: Bool = true, spacing: Int = 1) -> Component {
        Component(fields: ["type": componentNumber(14), "divider": .bool(divider),
            "spacing": componentNumber(spacing)])
    }

    /// Lowers a bounded declaration into an existing model while collecting safe text mention policies.
    /// - Parameter mentions: Inout explicit policies from text displays, in deterministic traversal order.
    /// - Returns: An exact existing component projection; containing-message validation still owns placement.
    /// - Throws: Sanitized validation, safe-content, JSON byte/depth/node or projection errors; no I/O occurs.
    func lower(mentions: inout [MessageAllowedMentions]) throws -> MessageComponent {
        guard !invalid else { throw DiscordError.validation(.invalidValue) }
        let value: JSONValue
        switch declaration {
        case .raw(let component): value = try component.jsonValue()
        case .definition(var fields, let children, let accessory, let text):
            if let children {
                guard !children.invalid else { throw DiscordError.validation(.invalidValue) }
                fields["components"] = .array(try children.values.map { try $0.lower(mentions: &mentions).jsonValue() })
            }
            if let accessory { fields["accessory"] = try accessory.lower(mentions: &mentions).jsonValue() }
            if let text {
                let rendered = try text.render(); fields["content"] = .string(rendered.content)
                mentions.append(rendered.allowedMentions)
            }
            value = .object(fields)
        }
        return try MessageComponent(jsonValue: value, limits: componentJSONLimits)
    }

    /// Conceals all content and interaction identities during ordinary diagnostics.
    public var description: String { "Component(redacted)" }
    /// Uses the same redacted debugger representation.
    public var debugDescription: String { description }
    /// Prevents reflective traversal into nested authoring data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Internal recursive storage; public declarations remain immutable, bounded values.
private indirect enum ComponentDeclaration: Sendable {
    case raw(MessageComponent)
    case definition([String: JSONValue], ComponentList?, Component?, MessageContent?)
}

/// Shared component serialization budget: 64 KiB, 24 JSON containers and 4,096 JSON values.
let componentJSONLimits = JSONLimits(maximumBytes: 65_536, maximumDepth: 24, maximumNodes: 4_096)

/// Finite ordered result-builder storage. Overflow is sticky, so dropping excess retained nodes never admits a partial tree.
/// At most forty declarations are retained per fragment; typed descendants contribute to count/depth at construction.
public struct ComponentList: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var values: [Component] = []
    var count = 0
    var depth = 0
    var invalid = false

    /// Creates an empty structural fragment without starting work or allocating unbounded storage.
    init() {}

    /// Appends finite declarations with saturating admission state; overflow can never recover in later branches.
    /// - Parameter other: Ordered fragment; at most forty stored declarations survive, solely for finite diagnostics.
    mutating func append(_ other: ComponentList) {
        count = min(41, count + other.count); depth = max(depth, other.depth)
        invalid = invalid || other.invalid || count > 40 || depth > 8
        values.append(contentsOf: other.values.prefix(max(0, 40 - values.count)))
    }

    /// Conceals retained component content during formatting.
    public var description: String { "ComponentList(redacted)" }
    /// Uses the redacted marker during debugger formatting.
    public var debugDescription: String { description }
    /// Prevents reflective traversal into structural payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Ordered component authoring supporting conditionals, arrays and finite loops without transport ownership.
/// User-provided builder closures run synchronously; declaration bounds cannot terminate an infinite user loop.
@resultBuilder public enum ComponentBuilder {
    /// Adopts one typed declaration, including sticky descendant admission failures.
    /// - Parameter expression: Inert declaration.
    /// - Returns: One finite ordered fragment.
    public static func buildExpression(_ expression: Component) -> ComponentList {
        var result = ComponentList(); result.values = [expression]; result.count = expression.count
        result.depth = expression.depth; result.invalid = expression.invalid; return result
    }

    /// Adopts an exact existing model without changing its nullable fields.
    /// - Parameter expression: Existing model, contextually validated with the complete resulting message.
    /// - Returns: One raw declaration fragment.
    public static func buildExpression(_ expression: MessageComponent) -> ComponentList {
        buildExpression(Component(expression))
    }

    /// Adopts an ordered array using finite, sticky admission rather than retaining an unbounded copy.
    /// - Parameter expression: Typed declarations; excess count marks the entire result invalid.
    /// - Returns: Saturating fragment preserving source order.
    public static func buildExpression(_ expression: [Component]) -> ComponentList {
        var result = ComponentList()
        for component in expression { result.append(buildExpression(component)) }
        return result
    }

    /// Adopts an ordered existing-model array while retaining bounded storage and exact nullable field values.
    /// - Parameter expression: Existing components; more than forty entries marks the complete fragment invalid.
    /// - Returns: Finite raw declaration fragment, contextually validated with the whole message.
    public static func buildExpression(_ expression: [MessageComponent]) -> ComponentList {
        var result = ComponentList()
        for component in expression { result.append(buildExpression(component)) }
        return result
    }

    /// Starts an incremental result-builder block.
    /// - Parameter first: First finite fragment.
    /// - Returns: The unchanged fragment; no lowering or validation work executes.
    public static func buildPartialBlock(first: ComponentList) -> ComponentList { first }

    /// Combines adjacent expressions in source order with sticky count/depth admission.
    /// - Parameters:
    ///   - accumulated: Prior fragment.
    ///   - next: Next fragment, appended without executing any handler.
    /// - Returns: Finite combined fragment.
    public static func buildPartialBlock(accumulated: ComponentList, next: ComponentList) -> ComponentList {
        var result = accumulated; result.append(next); return result
    }

    /// Supplies an explicitly empty block, allowing Models to decide context-specific validity.
    /// - Returns: Empty fragment, useful for component clearing on deferred edits.
    public static func buildBlock() -> ComponentList { ComponentList() }

    /// Includes an optional conditional branch.
    /// - Parameter component: Present branch or nil when omitted.
    /// - Returns: The branch or an empty fragment without evaluating another branch.
    public static func buildOptional(_ component: ComponentList?) -> ComponentList { component ?? ComponentList() }

    /// Includes the selected first conditional branch.
    /// - Parameter component: Already evaluated first branch.
    /// - Returns: Unchanged finite branch.
    public static func buildEither(first component: ComponentList) -> ComponentList { component }

    /// Includes the selected second conditional branch.
    /// - Parameter component: Already evaluated second branch.
    /// - Returns: Unchanged finite branch.
    public static func buildEither(second component: ComponentList) -> ComponentList { component }

    /// Flattens finite loop iterations in their source order, preserving any earlier overflow failure.
    /// - Parameter components: Iteration fragments created synchronously by Swift's result-builder lowering.
    /// - Returns: A fragment retaining no more than forty declarations.
    public static func buildArray(_ components: [ComponentList]) -> ComponentList {
        var result = ComponentList()
        for component in components { result.append(component) }
        return result
    }

    /// Preserves an availability-checked branch without introducing runtime work.
    /// - Parameter component: Available branch's finite declaration fragment.
    /// - Returns: Unchanged fragment.
    public static func buildLimitedAvailability(_ component: ComponentList) -> ComponentList { component }
}

/// Converts a finite Swift integer into an exact JSON numeric lexeme without rounding.
/// - Parameter value: Complete signed integer, including boundary values; decimal conversion is always valid JSON.
/// - Returns: Exact JSON number; a defensive null fallback makes an unexpected formatting change fail Models validation.
private func componentNumber(_ value: Int) -> JSONValue {
    guard let number = try? JSONNumber(rawValue: String(value)) else { return .null }
    return .number(number)
}
