import DiscordCore
import Foundation

/// Flags accepted when creating callback/follow-up messages; raw unsupported bits are rejected.
public struct InteractionMessageFlags: OptionSet, Sendable, Hashable {
    public let rawValue: UInt64
    public static let suppressEmbeds = Self(rawValue: 1 << 2)
    public static let ephemeral = Self(rawValue: 1 << 6)
    public static let suppressNotifications = Self(rawValue: 1 << 12)
    public static let isVoiceMessage = Self(rawValue: 1 << 13)
    public static let isComponentsV2 = Self(rawValue: 1 << 15)

    /// Stores outgoing bits; the complete request checks the operation-specific legal mask.
    /// - Parameter rawValue: Complete unsigned flags, including zero to explicitly clear optional flags.
    public init(rawValue: UInt64) { self.rawValue = rawValue }
}

/// Callback/follow-up message body. It shares ordinary message validation and bounded upload associations
/// while deliberately exposing only the documented interaction fields, including EPHEMERAL.
public struct InteractionMessageCreate: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let message: MessageCreate
    public let flags: Field<InteractionMessageFlags>

    /// Validates an interaction message without opening files, reserving rate admission or contacting Discord.
    /// - Parameters:
    ///   - content: Omitted or nonnull content of at most 2,000 Unicode scalars.
    ///   - tts: Optional nonnull TTS state; actual permission and ephemeral compatibility are server checked.
    ///   - embeds: Omitted or up to ten validated embeds with at most 6,000 combined text scalars.
    ///   - allowedMentions: Omitted for Discord defaults, or an explicit notification parsing policy.
    ///   - components: Omitted or validated legacy/V2 message components; modal-only components are rejected.
    ///   - attachments: Omitted or new-upload metadata; actual IDs are checked when constructing the endpoint.
    ///   - flags: Omitted or the documented callback/follow-up flags; EPHEMERAL limits visibility to the invoker.
    ///   - poll: Omitted or validated poll creation; deferred-original edits use InteractionMessageEdit instead.
    /// - Throws: Safe field/flag/null/combination errors. A file-only body is accepted until upload association checks.
    public init(content: Field<String> = .absent, tts: Field<Bool> = .absent,
                embeds: Field<[MessageEmbed]> = .absent, allowedMentions: Field<MessageAllowedMentions> = .absent,
                components: Field<[MessageComponent]> = .absent, attachments: Field<[MessageAttachmentRequest]> = .absent,
                flags: Field<InteractionMessageFlags> = .absent, poll: Field<PollCreate> = .absent) throws {
        let ordinary: Field<MessageCreateFlags>
        switch flags {
        case .absent: ordinary = .absent
        case .null: throw DiscordError.validation(.invalidValue)
        case .value(let flags):
            guard flags.rawValue & ~UInt64((1 << 2) | (1 << 6) | (1 << 12) | (1 << 13) | (1 << 15)) == 0
            else { throw DiscordError.validation(.invalidValue) }
            ordinary = .value(MessageCreateFlags(rawValue: flags.rawValue & ~UInt64(1 << 6)))
        }
        self.flags = flags
        message = try MessageCreate(content: content, tts: tts, embeds: embeds, allowedMentions: allowedMentions,
            components: components, attachments: attachments, flags: ordinary, poll: poll)
    }

    /// Validates the complete JSON/file associations and restores the interaction-specific visibility flag.
    /// - Parameters:
    ///   - uploadIDs: Actual distinct nonnegative files[n] IDs, default empty for JSON-only messages.
    ///   - uploadContentTypes: Actual media types, required for voice-message audio validation.
    /// - Returns: Complete validated object suitable for JSON or multipart payload_json.
    /// - Throws: Safe empty-message, attachment, voice, flags or message-field validation errors.
    public func jsonValue(uploadIDs: [Int] = [], uploadContentTypes: [Int: String] = [:]) throws -> JSONValue {
        guard case .object(var fields) = try message.jsonValue(uploadIDs: uploadIDs, uploadContentTypes: uploadContentTypes)
        else { throw DiscordError.validation(.invalidValue) }
        if case .value(let flags) = flags { fields["flags"] = try guildRequestNumber(flags.rawValue) }
        return .object(fields)
    }

    /// Conceals message content and nested user-supplied payloads from ordinary formatting.
    public var description: String { "InteractionMessageCreate(redacted)" }
    /// Uses the same safe marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflective traversal from exposing retained message fields.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Presence-aware original/follow-up edits with explicit support for creating a poll after a deferred response.
/// Existing EPHEMERAL state is immutable; carry observed previousFlags when retaining noneditable flag bits.
public struct InteractionMessageEdit: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let message: MessageEdit
    public let poll: Field<PollCreate>
    public let deferredResponse: Bool

    /// Validates a partial interaction-message update without fetching prior state or opening files.
    /// - Parameters:
    ///   - content: Absent preserves content; null clears; values are at most 2,000 Unicode scalars.
    ///   - embeds: Absent preserves; null/empty clears; nonempty values obey ten/6,000-scalar limits.
    ///   - allowedMentions: Optional parsing policy, including explicit null according to webhook edit semantics.
    ///   - components: Optional nullable component replacement validated for the resulting message flags.
    ///   - attachments: Optional nullable complete retained/new set; uploads require explicit metadata.
    ///   - flags: Optional nullable outgoing flags; only SUPPRESS_EMBEDS and setting IS_COMPONENTS_V2 may change.
    ///   - poll: Omitted normally, null clears for V2 migration, or a new poll only with deferredResponse=true.
    ///   - deferredResponse: Caller evidence that this edits the original deferred-channel response; default false.
    ///   - previousFlags: Optional observed complete flags, including immutable EPHEMERAL; no hidden fetch occurs.
    /// - Throws: Safe message-edit/state-transition errors; poll creation without explicit deferred evidence fails.
    public init(content: Field<String> = .absent, embeds: Field<[MessageEmbed]> = .absent,
                allowedMentions: Field<MessageAllowedMentions> = .absent, components: Field<[MessageComponent]> = .absent,
                attachments: Field<[MessageAttachmentRequest]> = .absent, flags: Field<MessageEditFlags> = .absent,
                poll: Field<PollCreate> = .absent, deferredResponse: Bool = false, previousFlags: UInt64? = nil) throws {
        if case .value = poll, !deferredResponse { throw DiscordError.validation(.invalidValue) }
        self.poll = poll; self.deferredResponse = deferredResponse
        let reset: Field<PollCreate> = if case .null = poll { .null } else { .absent }
        let stickerReset: Field<[StickerID]> = if case .null = poll { .value([]) } else { .absent }
        message = try MessageEdit(content: content, embeds: embeds, flags: flags, allowedMentions: allowedMentions,
            components: components, attachments: attachments, stickerIDs: stickerReset, poll: reset, previousFlags: previousFlags)
        if case .value(let poll) = poll { _ = try poll.jsonValue() }
        let resultingFlags = if case .value(let flags) = flags { flags.rawValue } else { previousFlags ?? 0 }
        if resultingFlags & (1 << 15) != 0, case .value = poll { throw DiscordError.validation(.invalidValue) }
    }

    /// Produces a validated nullable webhook edit body with complete file retention metadata.
    /// - Parameters:
    ///   - uploadIDs: Actual distinct files[n] placeholders, default empty.
    ///   - uploadContentTypes: Reserved symmetric upload context; voice messages cannot be edited.
    /// - Returns: Exact partial-update object, preserving absent/null/empty values and omitting channel-only stickers.
    /// - Throws: Safe attachment-retention, bounds or nested poll validation errors.
    public func jsonValue(uploadIDs: [Int] = [], uploadContentTypes: [Int: String] = [:]) throws -> JSONValue {
        guard case .object(var fields) = try message.jsonValue(uploadIDs: uploadIDs, uploadContentTypes: uploadContentTypes)
        else { throw DiscordError.validation(.invalidValue) }
        fields.removeValue(forKey: "sticker_ids")
        if case .value(let poll) = poll { fields["poll"] = try poll.jsonValue() }
        return .object(fields)
    }

    /// Conceals edited content, poll text and attachment metadata from ordinary formatting.
    public var description: String { "InteractionMessageEdit(redacted)" }
    /// Uses the same safe marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflective traversal from exposing nullable edits or retained payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Validated modal definition covering legacy text-input rows and all current label child types.
/// This is an outgoing definition; submitted partial component values use InteractionModalData.
public struct InteractionModal: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates a modal's finite component tree without executing handlers or allocating any I/O resources.
    /// - Parameters:
    ///   - customID: Developer identifier of 1...100 Unicode scalars, returned on submission.
    ///   - title: Visible title of 1...45 Unicode scalars.
    ///   - components: One through five label/text-display components or deprecated single-text-input action rows.
    ///     Label children support text inputs, all selects, file uploads, radio groups, checkbox groups and checkboxes.
    /// - Throws: Safe invalid-value errors for unsupported fields/types, invalid limits/nesting, duplicate nonzero IDs
    ///   or custom IDs, invalid defaults or incompatible selection/required constraints. Unknown outgoing fields fail.
    public init(customID: String, title: String, components: [MessageComponent]) throws {
        guard (1...5).contains(components.count) else { throw DiscordError.validation(.invalidValue) }
        var customIDs = Set<String>(), ids = Set<UInt32>()
        for component in components { try interactionModalComponent(component, parent: nil, customIDs: &customIDs, ids: &ids) }
        fields = ["custom_id": try guildRequestText(customID, length: 1...100),
                  "title": try guildRequestText(title, length: 1...45),
                  "components": .array(try components.map { try $0.jsonValue() })]
    }

    /// Returns the already validated exact modal definition with no I/O, state mutation or signature processing.
    /// - Returns: Required custom_id/title/components object suitable for a type-9 callback's data.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Outgoing interaction callback variants. Callers own the three-second acknowledgement deadline,
/// token lifetime, activity/monetization eligibility and single-acknowledgement state machine.
public enum InteractionResponse: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    case pong
    case message(InteractionMessageCreate)
    case deferredMessage(ephemeral: Bool = false)
    case deferredUpdate
    case update(InteractionMessageEdit)
    case autocomplete([ApplicationCommandChoiceCreate])
    case modal(InteractionModal)
    /// Deprecated upstream; premium-style buttons are the recommended replacement.
    @available(*, deprecated, message: "Use premium-style message buttons instead of the premium-required callback.")
    case premiumRequired
    case launchActivity

    /// Returns the documented callback discriminator without serializing the payload.
    public var type: InteractionCallbackType {
        switch self {
        case .pong: .pong
        case .message: .channelMessageWithSource
        case .deferredMessage: .deferredChannelMessageWithSource
        case .deferredUpdate: .deferredUpdateMessage
        case .update: .updateMessage
        case .autocomplete: .applicationCommandAutocompleteResult
        case .modal: .modal
        case .premiumRequired: .premiumRequired
        case .launchActivity: .launchActivity
        }
    }

    /// Validates callback compatibility and constructs its exact JSON envelope.
    /// - Parameters:
    ///   - interactionType: Optional known triggering kind; supply it to reject impossible callback combinations.
    ///     Nil retains explicit descriptor-only composition without claiming state-machine validation.
    ///   - uploadIDs: Actual distinct multipart file IDs, default empty; only message/update callbacks permit files.
    ///   - uploadContentTypes: Actual upload media types for voice-message validation.
    /// - Returns: Exact type/data object; data is absent for callbacks without a documented body.
    /// - Throws: Safe errors for incompatible trigger/callback types, excessive choices, illegal uploads or invalid messages.
    public func jsonValue(interactionType: InteractionType? = nil, uploadIDs: [Int] = [],
                          uploadContentTypes: [Int: String] = [:]) throws -> JSONValue {
        if let interactionType {
            switch (interactionType, type) {
            case (.ping, .pong), (.applicationCommandAutocomplete, .applicationCommandAutocompleteResult): break
            case (.ping, _), (_, .pong), (.applicationCommandAutocomplete, _), (_, .applicationCommandAutocompleteResult):
                throw DiscordError.validation(.invalidValue)
            case (.modalSubmit, .modal): throw DiscordError.validation(.invalidValue)
            case (_, .deferredUpdateMessage), (_, .updateMessage):
                guard interactionType == .messageComponent || interactionType == .modalSubmit else { throw DiscordError.validation(.invalidValue) }
            default: break
            }
        }
        var fields = ["type": try guildRequestNumber(type.rawValue)]
        switch self {
        case .message(let message): fields["data"] = try message.jsonValue(uploadIDs: uploadIDs, uploadContentTypes: uploadContentTypes)
        case .update(let message):
            guard !message.deferredResponse else { throw DiscordError.validation(.invalidValue) }
            fields["data"] = try message.jsonValue(uploadIDs: uploadIDs, uploadContentTypes: uploadContentTypes)
        default:
            guard uploadIDs.isEmpty else { throw DiscordError.validation(.invalidValue) }
            switch self {
            case .deferredMessage(let ephemeral):
                if ephemeral { fields["data"] = .object(["flags": try guildRequestNumber(64)]) }
            case .autocomplete(let choices):
                guard choices.count <= 25 else { throw DiscordError.validation(.invalidValue) }
                fields["data"] = .object(["choices": .array(choices.map { $0.jsonValue() })])
            case .modal(let modal): fields["data"] = modal.jsonValue()
            default: break
            }
        }
        return .object(fields)
    }

    /// Conceals all callback content and autocomplete choices from ordinary formatting.
    public var description: String { "InteractionResponse(redacted)" }
    /// Uses the same safe marker for debug formatting.
    public var debugDescription: String { description }
    /// Prevents reflective traversal from exposing retained callback payloads.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Validates one finite outgoing modal component using the current component-reference field matrix.
/// - Parameters:
///   - component: Already parser-bounded immutable component definition.
///   - parent: Nil at the root, 1 for a legacy row, or 18 for a label.
///   - customIDs: Global developer-identifier set, updated synchronously on successful traversal.
///   - ids: Global nonzero numeric-ID set; zero remains Discord's generate-ID sentinel.
/// - Throws: Invalid-value for unknown fields/types, wrong placement, invalid limits/defaults or duplicates.
private func interactionModalComponent(_ component: MessageComponent, parent: Int?,
                                       customIDs: inout Set<String>, ids: inout Set<UInt32>) throws {
    let kind = component.type.rawValue
    var allowed: Set<String> = ["type", "id"]
    if case .value(let id) = component.id, id != 0, !ids.insert(id).inserted { throw DiscordError.validation(.invalidValue) }
    if parent == nil {
        switch kind {
        case 1:
            allowed.insert("components")
            guard case .value(let children) = component.components, children.count == 1, children[0].type.rawValue == 4
            else { throw DiscordError.validation(.invalidValue) }
            try interactionModalComponent(children[0], parent: 1, customIDs: &customIDs, ids: &ids)
        case 10:
            allowed.insert("content")
            guard case .value(let text) = component.content, (1...4_000).contains(text.unicodeScalars.count)
            else { throw DiscordError.validation(.invalidValue) }
        case 18:
            allowed.formUnion(["label", "description", "component"])
            guard case .value(let text) = component.label, (1...45).contains(text.unicodeScalars.count),
                  case .value(let child) = component.component else { throw DiscordError.validation(.invalidValue) }
            try interactionModalOptionalText(component.componentDescription, maximum: 100)
            try interactionModalComponent(child, parent: 18, customIDs: &customIDs, ids: &ids)
        default: throw DiscordError.validation(.invalidValue)
        }
    } else {
        guard parent == 18 || (parent == 1 && kind == 4),
              [3, 4, 5, 6, 7, 8, 19, 21, 22, 23].contains(kind),
              case .value(let customID) = component.customID, (1...100).contains(customID.unicodeScalars.count),
              customIDs.insert(customID).inserted else { throw DiscordError.validation(.invalidValue) }
        allowed.insert("custom_id")
        if kind != 23 { allowed.insert("required") }
        if kind == 4 {
            allowed.formUnion(["style", "min_length", "max_length", "value", "placeholder"])
            if parent == 1 { allowed.insert("label"); try interactionModalOptionalText(component.label, maximum: 45) }
            guard case .value(let style) = component.style, style == 1 || style == 2 else { throw DiscordError.validation(.invalidValue) }
            let minimum = try interactionModalInteger(component.minLength, range: 0...4_000, fallback: 0)
            let maximum = try interactionModalInteger(component.maxLength, range: 1...4_000, fallback: 4_000)
            guard minimum <= maximum else { throw DiscordError.validation(.invalidValue) }
            try interactionModalOptionalText(component.placeholder, maximum: 100)
            if case .value(let preset) = component.value {
                guard case .text(let text) = preset, text.unicodeScalars.count <= 4_000 else { throw DiscordError.validation(.invalidValue) }
            }
        } else if kind == 23 {
            allowed.insert("default")
        } else {
            let limit = [19, 21, 22].contains(kind) ? 10 : 25
            if kind != 21 { allowed.formUnion(["min_values", "max_values"]) }
            if [3, 5, 6, 7, 8].contains(kind) { allowed.insert("placeholder"); try interactionModalOptionalText(component.placeholder, maximum: 150) }
            if [3, 21, 22].contains(kind) {
                allowed.insert("options")
                guard case .value(let options) = component.options, ((kind == 21 ? 2 : 1)...limit).contains(options.count),
                      Set(options.map(\.value)).count == options.count else { throw DiscordError.validation(.invalidValue) }
                var defaults = 0
                for option in options {
                    var keys: Set<String> = ["label", "value", "description", "default"]
                    if kind == 3 { keys.insert("emoji") }
                    guard Set(option.rawFields.keys).isSubset(of: keys), (1...100).contains(option.label.unicodeScalars.count),
                          (1...100).contains(option.value.unicodeScalars.count) else { throw DiscordError.validation(.invalidValue) }
                    try interactionModalOptionalText(option.optionDescription, maximum: 100)
                    if case .value(true) = option.isDefault { defaults += 1 }
                }
                if kind == 21, defaults > 1 { throw DiscordError.validation(.invalidValue) }
            }
            if kind != 21 {
                let optionValues: [ComponentOption]? = if case .value(let options) = component.options { options } else { nil }
                let fallback = kind == 22 ? (optionValues?.count ?? 1) : 1
                let minimum = try interactionModalInteger(component.minValues, range: 0...limit, fallback: 1)
                let maximum = try interactionModalInteger(component.maxValues, range: 1...limit, fallback: fallback)
                guard minimum <= maximum, minimum > 0 || component.required == .value(false),
                      optionValues.map({ maximum <= $0.count }) ?? true else { throw DiscordError.validation(.invalidValue) }
                if let options = optionValues {
                    guard options.filter({ $0.isDefault == .value(true) }).count <= maximum else { throw DiscordError.validation(.invalidValue) }
                }
                if [5, 6, 7, 8].contains(kind) {
                    allowed.insert("default_values")
                    if case .value(let defaults) = component.defaultValues {
                        let types: Set<String> = kind == 5 ? ["user"] : kind == 6 ? ["role"] : kind == 8 ? ["channel"] : ["user", "role"]
                        guard defaults.count <= maximum, defaults.isEmpty || defaults.count >= minimum,
                              Set(defaults.map { $0.type + ":" + $0.id }).count == defaults.count,
                              defaults.allSatisfy({ types.contains($0.type) && Set($0.rawFields.keys).isSubset(of: ["id", "type"]) })
                        else { throw DiscordError.validation(.invalidValue) }
                    }
                }
            }
            if kind == 8 {
                allowed.insert("channel_types")
                if case .value(let types) = component.channelTypes {
                    guard Set(types).count == types.count, types.allSatisfy({ ChannelType(rawValue: $0) != nil })
                    else { throw DiscordError.validation(.invalidValue) }
                }
            }
            if kind == 19 {
                allowed.insert("file_types")
                if case .value(let filters) = component.fileTypes {
                    guard filters.count <= 10, Set(filters.map { $0.lowercased() }).count == filters.count,
                          filters.allSatisfy({ value in
                              (1...16).contains(value.unicodeScalars.count) &&
                              (["image", "video", "audio"].contains(value) || (value.hasPrefix(".") && value.count > 1 &&
                               !value.contains("/") && !value.contains("\\") && !value.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.properties.generalCategory == .control })))
                          }) else { throw DiscordError.validation(.invalidValue) }
                }
            }
        }
    }
    guard Set(component.rawFields.keys).isSubset(of: allowed) else { throw DiscordError.validation(.invalidValue) }
}

/// Checks one optional modal display string without conflating an absent field with an invalid null.
/// - Parameters:
///   - field: Omitted or a nonnull string already typed by the component projection.
///   - maximum: Inclusive Unicode scalar count limit; empty optional strings remain representable.
/// - Throws: Invalid-value for explicit null or an overlong string.
private func interactionModalOptionalText(_ field: Field<String>, maximum: Int) throws {
    switch field {
    case .absent: break
    case .null: throw DiscordError.validation(.invalidValue)
    case .value(let text): guard text.unicodeScalars.count <= maximum else { throw DiscordError.validation(.invalidValue) }
    }
}

/// Checks one optional modal integer, supplying the documented upstream default solely for validation.
/// - Parameters:
///   - field: Omitted or a nonnull integral component field.
///   - range: Inclusive legal interval.
///   - fallback: Documented omitted-field default, not synthesized into outgoing JSON.
/// - Returns: Present validated integer or the selected default.
/// - Throws: Invalid-value for explicit null or a value outside the inclusive interval.
private func interactionModalInteger(_ field: Field<Int>, range: ClosedRange<Int>, fallback: Int) throws -> Int {
    switch field {
    case .absent: return fallback
    case .null: throw DiscordError.validation(.invalidValue)
    case .value(let value): guard range.contains(value) else { throw DiscordError.validation(.invalidValue) }; return value
    }
}
