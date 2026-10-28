// File: Sources/DiscordCommandDSL/AutocompleteCommands.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCommands
import DiscordCore
import DiscordDSL
import DiscordInteractions
import DiscordModels

/// A nonoptional string/integer/number codec usable for focused autocomplete values and choices.
/// Custom conformances must preserve their declared scalar kind and avoid I/O or side effects.
/// Construction rejects optional, structural, reference and enumerated-choice codecs.
public protocol AutocompleteValue: ArgumentValue {}
extension String: AutocompleteValue {}
extension Int: AutocompleteValue {}
extension Int64: AutocompleteValue {}
extension Double: AutocompleteValue {}

/// One typed suggestion. Its existing-model value is validated against the associated option kind.
public struct AutocompleteChoice<Value: AutocompleteValue>: Sendable {
    public let choice: ApplicationCommandChoiceCreate

    /// Validates display metadata and an exact scalar suggestion without invoking handlers.
    /// - Parameters:
    ///   - name: Display label, 1...100 Unicode scalars.
    ///   - value: Typed nonoptional string/integer/number suggestion; strings are at most 100 scalars.
    ///   - nameLocalizations: Omitted, cleared or complete translated display labels.
    /// - Throws: Existing model/codec errors for incompatible, nonfinite, out-of-range or oversized values.
    public init(name: String, value: Value, nameLocalizations: Field<[String: String]> = .absent) throws {
        let scalar: ApplicationCommandChoiceValue
        switch try value.argumentValue {
        case .value(.string(let value)) where Value.optionType == .string: scalar = .string(value)
        case .value(.number(let value)) where Value.optionType == .integer || Value.optionType == .number:
            scalar = .number(value)
        default: throw DiscordError.validation(.invalidValue)
        }
        choice = try ApplicationCommandChoiceCreate(name: name, value: scalar, nameLocalizations: nameLocalizations)
        _ = try ApplicationCommandOptionCreate(type: Value.optionType, name: "choice", description: "Choice", choices: [choice])
    }
}

/// An immediate autocomplete-only response. No defer, message, modal or follow-up operation is exposed.
public struct AutocompleteResponse<Value: AutocompleteValue>: Sendable {
    public let choices: [AutocompleteChoice<Value>]

    /// Captures zero through 25 validated, correctly typed choices in display order.
    /// - Parameter choices: Finite suggestions, default empty; empty suppresses all suggestions.
    /// - Throws: Existing invalid-value error for more than 25 suggestions.
    public init(_ choices: [AutocompleteChoice<Value>] = []) throws {
        guard choices.count <= 25 else { throw DiscordError.validation(.invalidValue) }
        self.choices = choices
    }
}

/// Partial invocation view, distinct from complete `CommandArguments`. Omitted required options remain
/// omitted; explicit defaults and aggregate constructors are never evaluated during autocomplete.
public struct AutocompleteInput: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let focusedOption: String
    private let descriptors: [String: AnyArgumentOption]
    private let submitted: [String: InteractionCommandOption]
    private let resolved: Field<InteractionResolvedData>
    private let commandName: String
    private let source: DefinitionSourceLocation

    /// Admits every supplied envelope before exposing the partial view to user work.
    /// - Parameters:
    ///   - options: At most 25 submitted unique leaves; missing declared leaves are intentionally legal.
    ///   - descriptors: Captured complete registration descriptors, without running default codecs.
    ///   - focusedOption: Exact declared enabled autocomplete name; exactly one supplied leaf must focus it.
    ///   - resolved: Same-interaction partial resolution data; no hydration occurs.
    ///   - commandName: Declared root diagnostic label.
    ///   - source: Author coordinate for sanitized invocation diagnostics.
    /// - Throws: `ArgumentDiagnostic` for malformed, undeclared, duplicate, nested, null, mistyped or invalid focus input.
    internal init(options: [InteractionCommandOption], descriptors: [AnyArgumentOption], focusedOption: String,
        resolved: Field<InteractionResolvedData>, commandName: String, source: DefinitionSourceLocation) throws {
        guard options.count <= 25 else {
            throw ArgumentDiagnostic(code: .optionLimit, commandName: commandName, source: source)
        }
        let byName = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.name, $0) })
        var submitted: [String: InteractionCommandOption] = [:]
        var focused = 0
        for option in options {
            guard let descriptor = byName[option.name] else {
                throw ArgumentDiagnostic(code: .unknownOption, commandName: commandName, source: source)
            }
            guard submitted.updateValue(option, forKey: option.name) == nil else {
                throw ArgumentDiagnostic(code: .duplicateOption, commandName: commandName, optionName: descriptor.name, source: source)
            }
            guard option.options == .absent else {
                throw ArgumentDiagnostic(code: .nestedOption, commandName: commandName, optionName: descriptor.name, source: source)
            }
            guard option.type.knownValue == descriptor.registration.type,
                  case .value(let scalar) = option.value,
                  argumentWireShape(scalar, type: descriptor.registration.type) else {
                throw ArgumentDiagnostic(code: .wrongType, commandName: commandName, optionName: descriptor.name, source: source)
            }
            if option.focused == .value(true) {
                focused += 1
                guard option.name == focusedOption else {
                    throw ArgumentDiagnostic(code: .focusedOption, commandName: commandName, source: source)
                }
            } else if option.focused != .absent && option.focused != .value(false) {
                throw ArgumentDiagnostic(code: .focusedOption, commandName: commandName, source: source)
            }
        }
        guard focused == 1 else {
            throw ArgumentDiagnostic(code: .focusedOption, commandName: commandName, source: source)
        }
        self.focusedOption = focusedOption
        self.descriptors = byName
        self.submitted = submitted
        self.resolved = resolved
        self.commandName = commandName
        self.source = source
    }

    /// Decodes one present partial leaf while retaining omission separately from the codec's own optional value.
    /// - Parameter option: Descriptor with the exact same registration as the captured partial schema.
    /// - Returns: Nil for an omitted leaf, otherwise its typed present value. Defaults never substitute for omission.
    /// - Throws: Sanitized descriptor-mismatch or invalid-value diagnostics. Codecs may impose extra local rules;
    ///   partial strings deliberately bypass registration minimum lengths and complete-invocation constraints.
    public func value<Value: ArgumentValue>(for option: ArgumentOption<Value>) throws -> Value? {
        guard let descriptor = descriptors[option.name], descriptor.valueType == ObjectIdentifier(Value.self),
              descriptor.registration.jsonValue() == option.registration.jsonValue() else {
            throw ArgumentDiagnostic(code: .descriptorMismatch, commandName: commandName, source: source)
        }
        guard let submitted = submitted[option.name] else { return nil }
        do { return try Value.decodeArgument(submitted.value, resolved: resolved) }
        catch { throw ArgumentDiagnostic(code: .invalidValue, commandName: commandName, optionName: descriptor.name, source: source) }
    }

    /// Conceals partial user values from ordinary formatting.
    public var description: String { "AutocompleteInput(redacted)" }
    /// Uses the same safe marker for debugger formatting.
    public var debugDescription: String { description }
    /// Prevents reflection from traversing partial input or resolved resources.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Typed autocomplete behavior with one immediate suggestions-only response. Execute in the caller's
/// task, honor cancellation and the initial acknowledgement deadline; defer is unavailable for this family.
public protocol AutocompleteCommandHandler: Sendable {
    associatedtype Value: AutocompleteValue

    /// Produces correctly typed suggestions from one focused value and optional partial siblings.
    /// - Parameters:
    ///   - context: Immutable normalized interaction without low-level response authority.
    ///   - input: Admitted partial leaves, retaining absent required/defaulted values as absence.
    ///   - value: Typed focused string/integer/number; partial strings may violate complete minimum lengths.
    /// - Returns: Zero through 25 typed suggestions in display order.
    /// - Throws: Application errors or cancellation; no defer, fallback or retry occurs.
    func execute(_ context: CommandContext, input: AutocompleteInput, value: Value) async throws -> AutocompleteResponse<Value>
}

/// One captured complete registration reference, checked globally after all contributions are lowered.
internal struct AutocompleteRegistrationReference: Sendable {
    let key: CommandRouteKey
    let options: [ApplicationCommandOptionCreate]
    let source: DefinitionSourceLocation
}

/// Route-only focused autocomplete contribution. Its complete leaf registration snapshot must match
/// the slash root/tree in the same compiled catalog; it never adds a separate registration.
public struct AutocompleteCommand<Handler: AutocompleteCommandHandler>: CommandFamilyContribution {
    public let declaration: RawDefinitionContribution
    public let family: CommandFamily

    /// Captures typed partial behavior and an exact focus route without invoking codecs or handlers.
    /// - Parameters:
    ///   - id: Explicit stable declaration identity, validated by compilation.
    ///   - name: Exact root slash name already contributed elsewhere in the catalog.
    ///   - path: Empty root, one subcommand or group/subcommand path, default empty.
    ///   - option: Exact nonoptional string/integer/number descriptor with autocomplete explicitly enabled.
    ///   - options: Complete leaf schema descriptors in registration order; nil means this option alone.
    ///     Defaults are ignored during partial invocation; compile verifies exact registration equality.
    ///   - handler: Inert suggestions-only behavior retained until explicit router invocation.
    ///   - source: Explicit author coordinate, or nil for compiler defaults.
    ///   - fileID: Caller identifier when source is nil; no file is read.
    ///   - line: Caller line when source is nil; zero means unknown.
    ///   - column: Caller column when source is nil; zero means unknown.
    /// - Throws: Existing key/schema validation or sanitized invalid-command diagnostics for incompatible
    ///   focus codecs, missing/duplicate descriptors or a descriptor without enabled autocomplete.
    ///   At invocation, complete supplied-envelope and focused-value decoding occurs synchronously before
    ///   execution wrappers. Invalid partial input neither executes policy work nor sends a callback.
    public init(id: String, name: String, path: [String] = [], option: ArgumentOption<Handler.Value>,
        options: [AnyArgumentOption]? = nil, handler: Handler, source: DefinitionSourceLocation? = nil,
        fileID: String = #fileID, line: UInt = #line, column: UInt = #column) throws {
        let source = source ?? .init(fileID: fileID, line: line, column: column)
        let options = options ?? [option.erased]
        guard [.string, .integer, .number].contains(Handler.Value.optionType), !Handler.Value.isOptional,
              case .object(let fields) = option.registration.jsonValue(), fields["autocomplete"] == .bool(true),
              options.count <= 25, Set(options.map(\.name)).count == options.count,
              options.contains(where: { $0.registration.jsonValue() == option.registration.jsonValue() }) else {
            throw CommandCompilationDiagnostic(code: .invalidCommand, commandName: name, source: source)
        }
        _ = try ApplicationCommandCreate(name: name, description: "Autocomplete", options: options.map(\.registration))
        let key = try CommandRouteKey.autocomplete(name: name, path: path, focusedOption: option.name)
        let route = CommandRoute(key: key, prepare: { context in
            try Task.checkCancellation()
            let leaves = try commandLeafInput(context, name: name, path: path, autocomplete: true, source: source)
            let input = try AutocompleteInput(options: leaves.options, descriptors: options,
                focusedOption: option.name, resolved: leaves.resolved, commandName: name, source: source)
            guard let value = try input.value(for: option) else {
                throw ArgumentDiagnostic(code: .missingValue, commandName: name, source: source)
            }
            try Task.checkCancellation()
            return {
                let response = try await handler.execute(CommandContext(context), input: input, value: value)
                try Task.checkCancellation()
                try await context.responder.respond(.autocomplete(response.choices.map(\.choice)))
            }
        })
        family = CommandFamily(routes: [route],
            autocompleteReferences: [.init(key: key, options: options.map(\.registration), source: source)])
        declaration = family.declaration(id: id, source: source)
    }
}
