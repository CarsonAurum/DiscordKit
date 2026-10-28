// File: Sources/DiscordModels/Component.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// A typed string-select, radio-group, or checkbox-group option, preserving unknown fields.
public struct ComponentOption: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Required display label.
    public let label: String
    /// Required opaque option value.
    public let value: String
    /// Optional display description; null is forbidden.
    public let optionDescription: Field<String>
    /// Optional emoji, currently writable only on string-select options.
    public let emoji: Field<PartialEmoji>
    /// Optional default-selection state.
    public let isDefault: Field<Bool>
    /// Complete original object with unknown fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Projects a bounded API v10 object without I/O, suspension, or payload diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; malformed modeled fields fail safely.
    ///   - limits: Shared parser and nested projection bounds, defaulting to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON bounds/syntax errors or sanitized invalid-response errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one exact subtree already bounded by its containing document.
    /// - Parameters:
    ///   - value: Original object subtree; unknown keys are retained.
    ///   - limits: Bounds used by the containing model.
    /// - Throws: Safe malformed-field, type, missing-key, or JSON-bound errors.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        label = try object.required("label", String.self)
        self.value = try object.required("value", String.self)
        optionDescription = try object.field("description", String.self)
        emoji = try object.nested("emoji") { try PartialEmoji(value: $0, limits: limits) }
        isDefault = try object.field("default", Bool.self)
        rawFields = object.resource.fields
    }

    /// Redacts all payload content in ordinary diagnostics.
    public var description: String { "ComponentOption(redacted)" }
    /// Redacts debug output, including future raw fields.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing sensitive payload values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// An auto-populated select default; future default type strings remain available without inventing support.
public struct ComponentDefaultValue: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Exact unsigned 64-bit snowflake string.
    public let id: String
    /// User, role, channel, or a future type discriminator.
    public let type: String
    /// Complete original object with unknown fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Projects a bounded API v10 object without I/O, suspension, or payload diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; malformed modeled fields fail safely.
    ///   - limits: Shared parser and nested projection bounds, defaulting to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON bounds/syntax errors or sanitized invalid-response errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one exact subtree already bounded by its containing document.
    /// - Parameters:
    ///   - value: Original object subtree; unknown keys are retained.
    ///   - limits: Bounds used by the containing model.
    /// - Throws: Safe malformed-field, type, missing-key, or JSON-bound errors.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", String.self)
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }), UInt64(id) != nil
        else { throw DiscordError.transport(.invalidResponse) }
        type = try object.required("type", String.self)
        rawFields = object.resource.fields
    }

    /// Redacts all payload content in ordinary diagnostics.
    public var description: String { "ComponentDefaultValue(redacted)" }
    /// Redacts debug output, including future raw fields.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing sensitive payload values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Complete documented component media projection. Only url is developer-settable; all other fields are response metadata.
public struct UnfurledMediaItem: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Arbitrary media URL or attachment reference; parsing performs no fetch.
    public let url: String
    /// Optional Discord proxy URL.
    public let proxyURL: Field<String>
    /// Optional nullable image/video height in pixels.
    public let height: Field<UInt64>
    /// Optional nullable image/video width in pixels.
    public let width: Field<UInt64>
    /// Optional thumbhash placeholder.
    public let placeholder: Field<String>
    /// Optional integral placeholder version, retaining future values.
    public let placeholderVersion: Field<Int>
    /// Optional media type string.
    public let contentType: Field<String>
    /// Optional flags retaining unknown bits.
    public let flags: Field<UInt64>
    /// Optional exact attachment snowflake string.
    public let attachmentID: Field<String>
    /// Complete original object with unknown fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Projects a bounded API v10 object without I/O, suspension, or payload diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; malformed modeled fields fail safely.
    ///   - limits: Shared parser and nested projection bounds, defaulting to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON bounds/syntax errors or sanitized invalid-response errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one exact subtree already bounded by its containing document.
    /// - Parameters:
    ///   - value: Original object subtree; unknown keys are retained.
    ///   - limits: Bounds used by the containing model.
    /// - Throws: Safe malformed-field, type, missing-key, or JSON-bound errors.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        url = try object.required("url", String.self)
        proxyURL = try object.field("proxy_url", String.self)
        height = try object.field("height", UInt64.self, nullable: true)
        width = try object.field("width", UInt64.self, nullable: true)
        placeholder = try object.field("placeholder", String.self)
        placeholderVersion = try object.field("placeholder_version", Int.self)
        contentType = try object.field("content_type", String.self)
        flags = try object.field("flags", UInt64.self)
        attachmentID = try object.field("attachment_id", String.self)
        if case .value(let id) = attachmentID {
            guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }), UInt64(id) != nil
            else { throw DiscordError.transport(.invalidResponse) }
        }
        rawFields = object.resource.fields
    }

    /// Redacts all payload content in ordinary diagnostics.
    public var description: String { "UnfurledMediaItem(redacted)" }
    /// Redacts debug output, including future raw fields.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing sensitive payload values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// One gallery media item with nullable alternate text and optional spoiler state.
public struct MediaGalleryItem: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Required typed unfurled media.
    public let media: UnfurledMediaItem
    /// Optional nullable alternate text.
    public let itemDescription: Field<String>
    /// Optional spoiler state; absence uses the server default.
    public let spoiler: Field<Bool>
    /// Complete original object with unknown fields and exact numeric spellings.
    public let rawFields: [String: JSONValue]

    /// Projects a bounded API v10 object without I/O, suspension, or payload diagnostics.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; malformed modeled fields fail safely.
    ///   - limits: Shared parser and nested projection bounds, defaulting to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON bounds/syntax errors or sanitized invalid-response errors.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects one exact subtree already bounded by its containing document.
    /// - Parameters:
    ///   - value: Original object subtree; unknown keys are retained.
    ///   - limits: Bounds used by the containing model.
    /// - Throws: Safe malformed-field, type, missing-key, or JSON-bound errors.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guard let value = object.resource.fields["media"] else { throw DiscordError.transport(.invalidResponse) }
        media = try UnfurledMediaItem(value: value, limits: limits)
        itemDescription = try object.field("description", String.self, nullable: true)
        spoiler = try object.field("spoiler", Bool.self)
        rawFields = object.resource.fields
    }

    /// Redacts all payload content in ordinary diagnostics.
    public var description: String { "MediaGalleryItem(redacted)" }
    /// Redacts debug output, including future raw fields.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing sensitive payload values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Current component discriminators, verified against Discord's reference on 2026-10-16.
/// Unknown integral types survive through RawValue and their complete raw object.
public enum ComponentType: Int, Sendable {
    /// The documented actionRow component (wire type 1).
    case actionRow = 1
    /// The documented button component (wire type 2).
    case button = 2
    /// The documented stringSelect component (wire type 3).
    case stringSelect = 3
    /// The documented textInput component (wire type 4).
    case textInput = 4
    /// The documented userSelect component (wire type 5).
    case userSelect = 5
    /// The documented roleSelect component (wire type 6).
    case roleSelect = 6
    /// The documented mentionableSelect component (wire type 7).
    case mentionableSelect = 7
    /// The documented channelSelect component (wire type 8).
    case channelSelect = 8
    /// The documented section component (wire type 9).
    case section = 9
    /// The documented textDisplay component (wire type 10).
    case textDisplay = 10
    /// The documented thumbnail component (wire type 11).
    case thumbnail = 11
    /// The documented mediaGallery component (wire type 12).
    case mediaGallery = 12
    /// The documented file component (wire type 13).
    case file = 13
    /// The documented separator component (wire type 14).
    case separator = 14
    /// The documented container component (wire type 17).
    case container = 17
    /// The documented label component (wire type 18).
    case label = 18
    /// The documented fileUpload component (wire type 19).
    case fileUpload = 19
    /// The documented radioGroup component (wire type 21).
    case radioGroup = 21
    /// The documented checkboxGroup component (wire type 22).
    case checkboxGroup = 22
    /// The documented checkbox component (wire type 23).
    case checkbox = 23
}

/// A typed interaction value; radio groups may additionally supply an explicit null field.
public enum ComponentInputValue: Sendable, Equatable {
    /// Text input or radio selection string, preserved without normalization.
    case text(String)
    /// Checkbox state.
    case checked(Bool)
}

/// Immutable exact projection of all current message/modal component fields. Only the
/// discriminator is required so partial interaction projections remain representable.
/// Incoming payloads are wire-typed; validateMessage applies stricter creation rules.
/// This final, immutable class permits recursive single accessories/label children;
/// equality compares complete exact raw objects rather than reference identity.
public final class MessageComponent: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Required known or future integral discriminator.
    public let type: RawValue<ComponentType>
    /// Optional unsigned 32-bit component ID; zero asks Discord to generate one.
    public let id: Field<UInt32>
    /// Optional developer-defined interaction identifier.
    public let customID: Field<String>
    /// Optional ordered row/section/container child components.
    public let components: Field<[MessageComponent]>
    /// Optional section accessory, preserving omission.
    public let accessory: Field<MessageComponent>
    /// Optional label child; modal interactions can return this partial projection.
    public let component: Field<MessageComponent>
    /// Optional button/text-input style, retaining future integers.
    public let style: Field<Int>
    /// Optional button or modal label text.
    public let label: Field<String>
    /// Optional typed button emoji.
    public let emoji: Field<PartialEmoji>
    /// Optional premium-button SKU snowflake string.
    public let skuID: Field<String>
    /// Optional link-button URL; projection performs no navigation.
    public let url: Field<String>
    /// Optional message component disabled state.
    public let disabled: Field<Bool>
    /// Optional string-select/radio/checkbox options in server order.
    public let options: Field<[ComponentOption]>
    /// Optional select/text-input placeholder.
    public let placeholder: Field<String>
    /// Optional minimum selected/uploaded item count.
    public let minValues: Field<Int>
    /// Optional maximum selected/uploaded item count.
    public let maxValues: Field<Int>
    /// Optional modal required state; ignored for message selects.
    public let required: Field<Bool>
    /// Optional user/role/channel select defaults.
    public let defaultValues: Field<[ComponentDefaultValue]>
    /// Optional channel-type filters; integer lexemes are validated exactly.
    public let channelTypes: Field<[Int]>
    /// Optional text-input minimum length.
    public let minLength: Field<Int>
    /// Optional text-input maximum length.
    public let maxLength: Field<Int>
    /// Optional text/radio/checkbox interaction or text-input preset value; null is retained.
    public let value: Field<ComponentInputValue>
    /// Optional selected/uploaded values; snowflake IDs remain decimal strings.
    public let values: Field<[String]>
    /// Optional exact resolved-data object; entity schemas remain separate projections.
    public let resolved: Field<JSONValue>
    /// Optional Markdown text-display content; mention policy belongs to the message.
    public let content: Field<String>
    /// Optional thumbnail media.
    public let media: Field<UnfurledMediaItem>
    /// Optional description; thumbnail alternate text permits null.
    public let componentDescription: Field<String>
    /// Optional thumbnail/file/container spoiler state.
    public let spoiler: Field<Bool>
    /// Optional media gallery items.
    public let items: Field<[MediaGalleryItem]>
    /// Optional attached-file media.
    public let file: Field<UnfurledMediaItem>
    /// Optional response-only file name.
    public let name: Field<String>
    /// Optional response-only file size in bytes.
    public let size: Field<UInt64>
    /// Optional separator divider state.
    public let divider: Field<Bool>
    /// Optional separator spacing discriminator.
    public let spacing: Field<Int>
    /// Optional nullable RGB container accent.
    public let accentColor: Field<Int>
    /// Optional file-upload filters.
    public let fileTypes: Field<[String]>
    /// Optional checkbox default state.
    public let isDefault: Field<Bool>
    /// Complete exact original object, including unmodeled future variants and fields.
    public let rawFields: [String: JSONValue]

    /// Parses one bounded component definition or partial interaction component.
    /// - Parameters:
    ///   - data: Complete untrusted UTF-8 JSON object with an integral type discriminator.
    ///   - limits: Byte/depth/node bounds, shared by nested projections; defaults to the library policy.
    /// - Throws: Safe JSON errors or invalid-response errors for malformed modeled fields.
    /// Unknown discriminators retain the object without applying today's unrelated field schemas.
    public convenience init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(verifiedValue: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an exact JSON object under explicit bounds; convenient for offline request composition.
    /// - Parameters:
    ///   - jsonValue: Complete JSON component object, including unknown fields to retain.
    ///   - limits: Bounds enforced before traversal; defaults to 1 MiB, depth 64, and 100,000 nodes.
    /// - Throws: Safe JSON bounds errors or malformed-field errors; no I/O or mutation occurs.
    public convenience init(jsonValue: JSONValue, limits: JSONLimits = .default) throws {
        _ = try jsonValue.serialized(limits: limits)
        try self.init(verifiedValue: jsonValue, limits: limits)
    }

    /// Projects an already bounded subtree without serializing each recursive child again.
    /// - Parameters:
    ///   - verifiedValue: Object from a complete tree that passed the caller's JSON bounds.
    ///   - limits: Bounds enforced at the tree's public entry point.
    /// - Throws: Safe invalid-response errors for missing or malformed modeled fields.
    /// Immutable raw dictionaries share tree storage; no I/O or state mutation occurs.
    init(verifiedValue: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(verifiedValue, limits: limits)
        let wireType = try object.required("type", RawValue<ComponentType>.self)
        type = wireType
        let knownType = wireType.knownValue
        rawFields = object.resource.fields
        let known = knownType != nil
        let projected = try PayloadObject(known ? verifiedValue : .object([:]), limits: limits)
        id = try projected.field("id", UInt32.self)
        customID = try projected.field("custom_id", String.self)
        components = try projected.array("components") { try MessageComponent(verifiedValue: $0, limits: limits) }
        accessory = try projected.nested("accessory") { try MessageComponent(verifiedValue: $0, limits: limits) }
        component = try projected.nested("component") { try MessageComponent(verifiedValue: $0, limits: limits) }
        style = try projected.field("style", Int.self)
        label = try projected.field("label", String.self)
        emoji = try projected.nested("emoji") { try PartialEmoji(value: $0, limits: limits) }
        skuID = try projected.field("sku_id", String.self)
        url = try projected.field("url", String.self)
        disabled = try projected.field("disabled", Bool.self)
        options = try projected.array("options") { try ComponentOption(value: $0, limits: limits) }
        placeholder = try projected.field("placeholder", String.self)
        minValues = try projected.field("min_values", Int.self)
        maxValues = try projected.field("max_values", Int.self)
        required = try projected.field("required", Bool.self)
        defaultValues = try projected.array("default_values") { try ComponentDefaultValue(value: $0, limits: limits) }
        channelTypes = try projected.array("channel_types") { value in
            let element = try PayloadObject(.object(["value": value]), limits: limits)
            return try element.required("value", Int.self)
        }
        minLength = try projected.field("min_length", Int.self)
        maxLength = try projected.field("max_length", Int.self)
        value = try projected.nested("value", nullable: knownType == .radioGroup) { value in
            if knownType == .checkbox {
                guard case .bool(let checked) = value else { throw DiscordError.transport(.invalidResponse) }
                return ComponentInputValue.checked(checked)
            }
            if knownType == .textInput || knownType == .radioGroup {
                guard case .string(let text) = value else { throw DiscordError.transport(.invalidResponse) }
                return ComponentInputValue.text(text)
            }
            switch value {
            case .string(let text): return ComponentInputValue.text(text)
            case .bool(let checked): return ComponentInputValue.checked(checked)
            default: throw DiscordError.transport(.invalidResponse)
            }
        }
        values = try projected.field("values", [String].self)
        resolved = try projected.nested("resolved") { value in
            guard case .object = value else { throw DiscordError.transport(.invalidResponse) }
            return value
        }
        content = try projected.field("content", String.self)
        media = try projected.nested("media") { try UnfurledMediaItem(value: $0, limits: limits) }
        componentDescription = try projected.field("description", String.self, nullable: knownType == .thumbnail)
        spoiler = try projected.field("spoiler", Bool.self)
        items = try projected.array("items") { try MediaGalleryItem(value: $0, limits: limits) }
        file = try projected.nested("file") { try UnfurledMediaItem(value: $0, limits: limits) }
        name = try projected.field("name", String.self)
        size = try projected.field("size", UInt64.self)
        divider = try projected.field("divider", Bool.self)
        spacing = try projected.field("spacing", Int.self)
        accentColor = try projected.field("accent_color", Int.self, nullable: true)
        fileTypes = try projected.field("file_types", [String].self)
        isDefault = try projected.field("default", Bool.self)
        for field in [skuID] {
            if case .value(let id) = field {
                guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }), UInt64(id) != nil
                else { throw DiscordError.transport(.invalidResponse) }
            }
        }
    }

    /// Compares complete wire objects, including unknown keys and numeric lexemes.
    /// - Parameters:
    ///   - lhs: First immutable component projection.
    ///   - rhs: Second immutable component projection.
    /// - Returns: True for equal payloads regardless of object identity.
    public static func == (lhs: MessageComponent, rhs: MessageComponent) -> Bool { lhs.rawFields == rhs.rawFields }

    /// Exposes the exact immutable tree for explicitly validated request composition.
    /// - Returns: The complete original component object; callers must validate message context before sending.
    public func jsonValue() throws -> JSONValue { .object(rawFields) }

    /// Redacts all payload content in ordinary diagnostics.
    public var description: String { "MessageComponent(redacted)" }
    /// Redacts debug output, including future raw fields.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing sensitive payload values.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

extension MessageComponent {
    /// Validates current message-only component placement and bounded request constraints.
    /// - Parameters:
    ///   - components: Ordered top-level components; an empty array intentionally clears components on edit.
    ///   - componentsV2: Whether the containing message sets IS_COMPONENTS_V2. Legacy messages
    ///     allow five action rows; V2 allows forty total components including nested accessories.
    /// - Throws: `DiscordError.validation(.invalidValue)` for modal/unknown types, invalid nesting,
    ///   duplicate nonzero IDs/custom IDs, response-only fields, incompatible button fields,
    ///   or documented count/string/range violations. Content/embed/poll/sticker conflicts belong
    ///   to the containing request validator. No payload content appears in errors.
    public static func validateMessage(_ components: [MessageComponent], componentsV2: Bool) throws {
        guard componentsV2 || components.count <= 5 else { throw DiscordError.validation(.invalidValue) }
        var pending = components.map { ($0, Optional<ComponentType>.none) }
        var count = 0
        var ids = Set<UInt32>()
        var customIDs = Set<String>()
        while let (component, parent) = pending.popLast() {
            count += 1
            guard !componentsV2 || count <= 40 else { throw DiscordError.validation(.invalidValue) }
            try component.validateDefinition(parent: parent, componentsV2: componentsV2)
            if case .value(let id) = component.id, id != 0 {
                guard ids.insert(id).inserted else { throw DiscordError.validation(.invalidValue) }
            }
            if case .value(let customID) = component.customID {
                guard (1...100).contains(customID.unicodeScalars.count), customIDs.insert(customID).inserted
                else { throw DiscordError.validation(.invalidValue) }
            }
            if case .value(let children) = component.components {
                pending.append(contentsOf: children.map { ($0, component.type.knownValue) })
            }
            if case .value(let accessory) = component.accessory { pending.append((accessory, .section)) }
        }
    }

    /// Requires a present field while keeping response omission separate from request validity.
    /// - Parameter field: Optional projection that must contain a nonnull request value.
    /// - Returns: The unwrapped value without copying referenced component objects.
    /// - Throws: Safe invalid-value errors for absent/null fields.
    private func require<T>(_ field: Field<T>) throws -> T {
        guard case .value(let value) = field else { throw DiscordError.validation(.invalidValue) }
        return value
    }

    /// Applies one optional string length bound without changing omitted/null values.
    /// - Parameters:
    ///   - field: Optional string; null is accepted only when its response projector permits it.
    ///   - maximum: Inclusive maximum number of Unicode scalars, never encoded UTF-8 bytes.
    /// - Throws: Safe invalid-value errors when the string exceeds the current wire limit.
    private func length(_ field: Field<String>, maximum: Int) throws {
        if case .value(let value) = field, value.unicodeScalars.count > maximum {
            throw DiscordError.validation(.invalidValue)
        }
    }

    /// Validates a button/select emoji's documented writable keys and nonempty identity.
    /// - Parameter emoji: Typed partial emoji; ID range/type was checked during projection.
    /// - Throws: Invalid-value errors for missing identity or undocumented request keys.
    private func validateEmoji(_ emoji: PartialEmoji) throws {
        let fields = emoji.rawFields
        let hasID: Bool
        let hasName: Bool
        if case .value(let id) = emoji.id { hasID = !id.isEmpty } else { hasID = false }
        if case .value(let name) = emoji.name { hasName = !name.isEmpty } else { hasName = false }
        guard hasID || hasName, Set(fields.keys).isSubset(of: ["id", "name", "animated"])
        else { throw DiscordError.validation(.invalidValue) }
    }

    /// Rejects response metadata from developer-set media objects and checks attachment-only files.
    /// - Parameters:
    ///   - media: Exact typed unfurled media object.
    ///   - attachmentOnly: Whether the file component requires an attachment reference.
    /// - Throws: Invalid-value errors for missing URLs, response-only keys, or nonattachment file URLs.
    private func validateMedia(_ media: UnfurledMediaItem, attachmentOnly: Bool = false) throws {
        guard !media.url.isEmpty, Set(media.rawFields.keys) == ["url"],
              !attachmentOnly || (media.url.hasPrefix("attachment://") && media.url.count > "attachment://".count)
        else { throw DiscordError.validation(.invalidValue) }
    }

    /// Validates one node's current message schema and permitted parent relationship.
    /// - Parameters:
    ///   - parent: Parent type, or nil for a top-level component. Section accessories share the section parent.
    ///   - componentsV2: Whether V2 content/layout component types are enabled by the containing message.
    /// - Throws: Sanitized invalid-value errors for all incompatible shapes. Recursion is handled
    ///   iteratively by validateMessage, keeping total-node and uniqueness accounting global.
    private func validateDefinition(parent: ComponentType?, componentsV2: Bool) throws {
        guard let type = type.knownValue else { throw DiscordError.validation(.invalidValue) }
        let allowedTop: Set<ComponentType> = componentsV2
            ? [.actionRow, .section, .textDisplay, .mediaGallery, .file, .separator, .container] : [.actionRow]
        if let parent {
            let allowed: Set<ComponentType>
            switch parent {
            case .actionRow: allowed = [.button, .stringSelect, .userSelect, .roleSelect, .mentionableSelect, .channelSelect]
            case .section: allowed = [.textDisplay, .button, .thumbnail]
            case .container: allowed = [.actionRow, .textDisplay, .section, .mediaGallery, .separator, .file]
            default: allowed = []
            }
            guard allowed.contains(type) else { throw DiscordError.validation(.invalidValue) }
        } else {
            guard allowedTop.contains(type) else { throw DiscordError.validation(.invalidValue) }
        }
        let keys: Set<String>
        switch type {
        case .actionRow: keys = ["components"]
        case .button: keys = ["style", "label", "emoji", "custom_id", "sku_id", "url", "disabled"]
        case .stringSelect: keys = ["custom_id", "options", "placeholder", "min_values", "max_values", "required", "disabled"]
        case .userSelect, .roleSelect, .mentionableSelect: keys = ["custom_id", "placeholder", "default_values", "min_values", "max_values", "required", "disabled"]
        case .channelSelect: keys = ["custom_id", "placeholder", "default_values", "min_values", "max_values", "required", "disabled", "channel_types"]
        case .section: keys = ["components", "accessory"]
        case .textDisplay: keys = ["content"]
        case .thumbnail: keys = ["media", "description", "spoiler"]
        case .mediaGallery: keys = ["items"]
        case .file: keys = ["file", "spoiler"]
        case .separator: keys = ["divider", "spacing"]
        case .container: keys = ["components", "accent_color", "spoiler"]
        default: throw DiscordError.validation(.invalidValue)
        }
        guard Set(rawFields.keys).isSubset(of: keys.union(["type", "id"]))
        else { throw DiscordError.validation(.invalidValue) }
        switch type {
        case .actionRow:
            let children = try require(components)
            guard (1...5).contains(children.count),
                  children.allSatisfy({ $0.type.knownValue == .button })
                    || (children.count == 1 && [3, 5, 6, 7, 8].contains(children[0].type.rawValue))
            else { throw DiscordError.validation(.invalidValue) }
        case .button:
            let style = try require(style)
            guard (1...6).contains(style) else { throw DiscordError.validation(.invalidValue) }
            try length(label, maximum: 80)
            try length(url, maximum: 512)
            if case .value(let emoji) = emoji { try validateEmoji(emoji) }
            switch style {
            case 5:
                guard !(try require(url)).isEmpty, customID == .absent, skuID == .absent
                else { throw DiscordError.validation(.invalidValue) }
            case 6:
                _ = try require(skuID)
                guard customID == .absent, label == .absent, url == .absent, emoji == .absent
                else { throw DiscordError.validation(.invalidValue) }
            default:
                _ = try require(customID)
                guard url == .absent, skuID == .absent else { throw DiscordError.validation(.invalidValue) }
            }
        case .stringSelect, .userSelect, .roleSelect, .mentionableSelect, .channelSelect:
            try validateSelect(type)
        case .section:
            let children = try require(components)
            let accessory = try require(accessory)
            guard (1...3).contains(children.count), children.allSatisfy({ $0.type.knownValue == .textDisplay }),
                  accessory.type.knownValue == .button || accessory.type.knownValue == .thumbnail
            else { throw DiscordError.validation(.invalidValue) }
        case .textDisplay:
            _ = try require(content)
        case .thumbnail:
            try validateMedia(require(media))
            try length(componentDescription, maximum: 1024)
        case .mediaGallery:
            let items = try require(items)
            guard (1...10).contains(items.count) else { throw DiscordError.validation(.invalidValue) }
            for item in items {
                guard Set(item.rawFields.keys).isSubset(of: ["media", "description", "spoiler"])
                else { throw DiscordError.validation(.invalidValue) }
                try validateMedia(item.media)
                try length(item.itemDescription, maximum: 1024)
            }
        case .file:
            try validateMedia(require(file), attachmentOnly: true)
        case .separator:
            if case .value(let spacing) = spacing, ![1, 2].contains(spacing) {
                throw DiscordError.validation(.invalidValue)
            }
        case .container:
            _ = try require(components)
            if case .value(let color) = accentColor, !(0...0xFFFFFF).contains(color) {
                throw DiscordError.validation(.invalidValue)
            }
        default: throw DiscordError.validation(.invalidValue)
        }
    }

    /// Applies message select constraints, retaining API defaults when fields are omitted.
    /// - Parameter type: Known string/user/role/mentionable/channel select type.
    /// - Throws: Invalid-value errors for missing IDs, invalid counts, duplicate option values,
    ///   malformed options/defaults, or default IDs whose types do not match the selected menu.
    private func validateSelect(_ type: ComponentType) throws {
        _ = try require(customID)
        try length(placeholder, maximum: 150)
        let minimum: Int
        let maximum: Int
        if case .value(let value) = minValues { minimum = value } else { minimum = 1 }
        if case .value(let value) = maxValues { maximum = value } else { maximum = 1 }
        guard (0...25).contains(minimum), (1...25).contains(maximum), minimum <= maximum
        else { throw DiscordError.validation(.invalidValue) }
        if type == .stringSelect {
            let options = try require(options)
            guard (1...25).contains(options.count), maximum <= options.count,
                  Set(options.map(\.value)).count == options.count
            else { throw DiscordError.validation(.invalidValue) }
            var defaultCount = 0
            for option in options {
                guard Set(option.rawFields.keys).isSubset(of: ["label", "value", "description", "emoji", "default"]),
                      (1...100).contains(option.label.unicodeScalars.count),
                      (1...100).contains(option.value.unicodeScalars.count)
                else { throw DiscordError.validation(.invalidValue) }
                try length(option.optionDescription, maximum: 100)
                if case .value(let emoji) = option.emoji { try validateEmoji(emoji) }
                if option.isDefault == .value(true) { defaultCount += 1 }
            }
            guard defaultCount <= maximum else { throw DiscordError.validation(.invalidValue) }
        } else if case .value(let defaults) = defaultValues {
            let allowed: Set<String>
            switch type {
            case .userSelect: allowed = ["user"]
            case .roleSelect: allowed = ["role"]
            case .mentionableSelect: allowed = ["user", "role"]
            default: allowed = ["channel"]
            }
            guard (minimum...maximum).contains(defaults.count),
                  Set(defaults.map { $0.type + ":" + $0.id }).count == defaults.count,
                  defaults.allSatisfy({ allowed.contains($0.type) && Set($0.rawFields.keys) == ["id", "type"] })
            else { throw DiscordError.validation(.invalidValue) }
        }
    }
}
