import DiscordCore
import Foundation

/// Validated stereo pan, retaining exact wire numbers rather than normalizing fractional spellings.
public struct RPCPan: RPCPayload {
    public let left: JSONNumber
    public let right: JSONNumber
    public let rawFields: [String: JSONValue]

    /// Creates finite stereo levels without opening an audio device.
    /// - Parameters:
    ///   - left: Left output level in inclusive 0...1.
    ///   - right: Right output level in inclusive 0...1.
    /// - Throws: Sanitized invalid-argument errors for nonfinite or out-of-range levels.
    public init(left: Double, right: Double) throws {
        try self.init(value: .object(["left": rpcFiniteNumber(left), "right": rpcFiniteNumber(right)]))
    }

    /// Projects and validates an exact bounded pan object.
    /// - Parameter value: Object with required numeric left/right fields; unknown members survive.
    /// - Throws: Sanitized invalid-payload or invalid-argument errors for missing/wrong/out-of-range fields.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        left = try RPCObject.number(object.required("left"))
        right = try RPCObject.number(object.required("right"))
        try rpcCheckRange(left, minimum: 0, maximum: 1)
        try rpcCheckRange(right, minimum: 0, maximum: 1)
        rawFields = object.fields
    }
}

/// Explicit writable voice-settings patch. Missing fields retain desktop state; null is not a documented update.
/// All fields are optional and unknown keys are retained for compatibility, without implying server support.
public struct RPCVoiceSettingsUpdate: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let rawFields: [String: JSONValue]

    /// Validates a bounded writable patch including nested input/output/mode settings.
    /// - Parameters:
    ///   - fields: Optional input/output volume/device IDs, mode and booleans. Read-only available_devices is rejected.
    ///     Input volume is 0...100; output volume 0...200; mode threshold -100...0 dB and delay 0...2000 ms.
    ///   - limits: Whole-document bounds, default 1 MiB/depth 64/100,000 nodes.
    /// - Throws: Sanitized invalid-argument errors or JSON bounds errors; parsing performs no I/O or suspension.
    /// Mode types must be PUSH_TO_TALK or VOICE_ACTIVITY when sent; received future types remain preserved separately.
    public init(fields: [String: JSONValue] = [:], limits: JSONLimits = .default) throws {
        _ = try JSONValue.object(fields).serialized(limits: limits)
        do {
            _ = try RPCVoiceSettings(value: .object(fields))
            for (key, maximum) in [("input", 100), ("output", 200)] {
                if let value = fields[key] {
                    let io = try RPCObject(value)
                    guard io.fields["available_devices"] == nil else { throw RPCCatalogError.invalidArguments }
                    if let volume = io.fields["volume"] { try rpcCheckRange(RPCObject.number(volume), minimum: 0, maximum: maximum) }
                }
            }
            if let value = fields["mode"] {
                let mode = try RPCObject(value)
                if let type = mode.fields["type"], !["PUSH_TO_TALK", "VOICE_ACTIVITY"].contains(try RPCObject.string(type)) {
                    throw RPCCatalogError.invalidArguments
                }
                if let threshold = mode.fields["threshold"] { try rpcCheckRange(RPCObject.number(threshold), minimum: -100, maximum: 0) }
                if let delay = mode.fields["delay"] { try rpcCheckRange(RPCObject.number(delay), minimum: 0, maximum: 2_000) }
                if let shortcuts = mode.fields["shortcut"] {
                    guard case .array(let values) = shortcuts else { throw RPCCatalogError.invalidArguments }
                    for shortcut in values {
                        let parsed = try RPCShortcut(value: shortcut)
                        guard (0...3).contains(parsed.type), parsed.code >= 0 else { throw RPCCatalogError.invalidArguments }
                    }
                }
            }
        } catch { throw RPCCatalogError.invalidArguments }
        rawFields = fields
    }

    /// Conceals device identifiers and user settings in diagnostics.
    public var description: String { "RPCVoiceSettingsUpdate(redacted)" }
    /// Uses the same redaction for debugger output.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing device identifiers and future setting fields.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Validated RPC Rich Presence object. Unknown fields are retained but do not claim future server support.
/// This is separate from Gateway bot presence and from the native Social SDK.
public struct RPCActivity: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public let rawFields: [String: JSONValue]

    /// Validates the documented RPC activity types and typed partial object shape.
    /// - Parameters:
    ///   - fields: Rich Presence object. Type may be omitted; a supplied type must be 0, 2, 3 or 5.
    ///     Nested timestamps/assets/party/secrets must be objects. Presence strings/secrets are retained verbatim.
    ///   - limits: Whole-object JSON bounds, default 1 MiB/depth 64/100,000 nodes.
    /// - Throws: Sanitized invalid-argument errors for incompatible fields or unsupported outgoing type,
    ///   or JSON bounds errors. No image/URL fetching, authentication or background work occurs.
    /// The official RPC reference does not publish a complete field-specific limit matrix; the desktop client
    /// remains authoritative for remaining validation and compatibility.
    public init(fields: [String: JSONValue], limits: JSONLimits = .default) throws {
        _ = try JSONValue.object(fields).serialized(limits: limits)
        do {
            let activity = try RPCActivityProjection(value: .object(fields))
            if case .value(let type) = activity.type, ![0, 2, 3, 5].contains(type) { throw RPCCatalogError.invalidArguments }
        } catch { throw RPCCatalogError.invalidArguments }
        rawFields = fields
    }

    /// Conceals invite secrets and profile details in ordinary output.
    public var description: String { "RPCActivity(redacted)" }
    /// Uses the same redaction in nested debugger-oriented output.
    public var debugDescription: String { description }
    /// Prevents reflective diagnostics from traversing activity secrets and nested profile data.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Manufacturer-certified local device descriptor. It describes state; it never probes or opens hardware.
/// Native identity formats: https://docs.discord.com/developers/topics/certified-devices#getting-device-uuid.
public struct RPCCertifiedDevice: RPCPayload {
    public let type: String
    public let id: String
    public let vendor: RPCHardwareIdentity
    public let model: RPCHardwareIdentity
    public let related: [String]
    public let echoCancellation: Field<Bool>
    public let noiseSuppression: Field<Bool>
    public let automaticGainControl: Field<Bool>
    public let hardwareMute: Field<Bool>
    public let rawFields: [String: JSONValue]

    /// Projects a certified device and validates input-only hardware controls.
    /// - Parameter value: Bounded object with audioinput/audiooutput/videoinput type, native id, vendor,
    ///   model and related native ID strings. Windows IDs may include endpoint prefixes and braces;
    ///   macOS IDs are device names. IDs must be nonempty, at most 16 KiB and contain no control scalars.
    ///   Four optional hardware booleans are audioinput-only.
    /// - Throws: Sanitized invalid-payload or invalid-argument errors for wrong fields, unknown outgoing
    ///   type, invalid native identifiers or hardware controls on an incompatible device type.
    /// Unknown object members survive; certification and manufacturer ownership remain server decisions.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        type = try object.string("type")
        id = try object.string("id")
        vendor = try RPCHardwareIdentity(value: object.required("vendor"))
        model = try RPCHardwareIdentity(value: object.required("model"))
        related = try object.array("related").map(RPCObject.string)
        echoCancellation = try object.field("echo_cancellation", RPCObject.bool)
        noiseSuppression = try object.field("noise_suppression", RPCObject.bool)
        automaticGainControl = try object.field("automatic_gain_control", RPCObject.bool)
        hardwareMute = try object.field("hardware_mute", RPCObject.bool)
        guard ["audioinput", "audiooutput", "videoinput"].contains(type), rpcValidNativeDeviceID(id),
              related.allSatisfy(rpcValidNativeDeviceID),
              type == "audioinput" || ["echo_cancellation", "noise_suppression", "automatic_gain_control", "hardware_mute"]
                .allSatisfy({ object.fields[$0] == nil }) else { throw RPCCatalogError.invalidArguments }
        rawFields = object.fields
    }
}

/// Enforces local native-device identifier text bounds without assuming one platform's UUID grammar.
/// - Parameter value: Windows native endpoint identity or macOS device name, retained verbatim.
/// - Returns: True for nonempty strings of at most 16 KiB without Unicode control scalars;
///   spaces, braces, endpoint prefixes and non-ASCII device names are allowed.
private func rpcValidNativeDeviceID(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 16_384 && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
}

/// Manufacturer or product identity from a certified-device descriptor; URLs are informational only.
public struct RPCHardwareIdentity: RPCPayload {
    public let name: String
    public let url: String
    public let rawFields: [String: JSONValue]

    /// Projects name and URL without making a network request or asserting certification.
    /// - Parameter value: Bounded object containing nonempty name/url strings; unknown fields survive.
    /// - Throws: Sanitized invalid-payload or invalid-argument errors for missing/wrong/empty fields.
    public init(value: JSONValue) throws {
        let object = try RPCObject(value)
        name = try object.string("name")
        url = try object.string("url")
        guard !name.isEmpty, !url.isEmpty else { throw RPCCatalogError.invalidArguments }
        rawFields = object.fields
    }
}

/// Converts finite caller-supplied binary floating point to a JSON number for outgoing convenience APIs.
/// - Parameter value: Finite native number; endpoint-specific range validation follows separately.
/// - Returns: JSON lexeme for the native input value; received wire numbers never use this conversion.
/// - Throws: Sanitized invalid-argument error for NaN/infinity, or JSON number grammar errors.
private func rpcFiniteNumber(_ value: Double) throws -> JSONValue {
    guard value.isFinite else { throw RPCCatalogError.invalidArguments }
    return .number(try JSONNumber(rawValue: String(value)))
}

/// Checks an exact decimal lexeme against small integral documented limits without rounding to Double.
/// - Parameters:
///   - number: Complete grammar-validated JSON number, including arbitrary exponent spellings.
///   - minimum: Inclusive integral lower bound; current RPC callers use -100...0.
///   - maximum: Inclusive nonnegative integral upper bound; current callers use 0...2000.
/// - Throws: Sanitized invalid-argument error if the exact decimal value lies outside the interval.
func rpcCheckRange(_ number: JSONNumber, minimum: Int, maximum: Int) throws {
    let raw = number.rawValue
    let negative = raw.first == "-"
    let magnitude = negative ? String(raw.dropFirst()) : raw
    if negative {
        guard minimum <= 0, rpcCompareMagnitude(magnitude, to: -minimum) <= 0 else { throw RPCCatalogError.invalidArguments }
        if maximum < 0 { throw RPCCatalogError.invalidArguments }
    } else {
        guard maximum >= 0, rpcCompareMagnitude(magnitude, to: maximum) <= 0,
              minimum <= 0 || rpcCompareMagnitude(magnitude, to: minimum) >= 0 else { throw RPCCatalogError.invalidArguments }
    }
}

/// Compares a nonnegative exact JSON decimal magnitude to a nonnegative small native integer.
/// - Parameters:
///   - raw: Valid positive-magnitude JSON spelling; no leading minus.
///   - bound: Nonnegative integral boundary from the documented RPC range table.
/// - Returns: -1, 0 or 1 for less, equal or greater, with exponent magnitudes clamped only after
///   exceeding any possible bounded input coefficient length. No expanded exponent allocation occurs.
private func rpcCompareMagnitude(_ raw: String, to bound: Int) -> Int {
    let parts = raw.lowercased().split(separator: "e", omittingEmptySubsequences: false)
    let coefficient = String(parts[0])
    let exponentText = parts.count > 1 ? String(parts[1]) : "0"
    let exponent = Int(exponentText) ?? (exponentText.first == "-" ? -Int.max / 4 : Int.max / 4)
    let boundedExponent = min(max(exponent, -Int.max / 4), Int.max / 4)
    let fractionalCount = coefficient.firstIndex(of: ".").map { coefficient.distance(from: coefficient.index(after: $0), to: coefficient.endIndex) } ?? 0
    let digits = Array(coefficient.filter { $0 != "." }.drop(while: { $0 == "0" }))
    guard !digits.isEmpty else { return bound == 0 ? 0 : -1 }
    guard bound != 0 else { return 1 }
    let integerDigits = digits.count + boundedExponent - fractionalCount
    let boundary = Array(String(bound))
    if integerDigits != boundary.count { return integerDigits < boundary.count ? -1 : 1 }
    for index in boundary.indices {
        let digit = index < digits.count ? digits[index] : "0"
        if digit != boundary[index] { return digit < boundary[index] ? -1 : 1 }
    }
    return digits.dropFirst(boundary.count).contains(where: { $0 != "0" }) ? 1 : 0
}
