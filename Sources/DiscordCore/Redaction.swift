import Foundation

/// A deterministic, immutable filter for diagnostic strings and structured fields.
///
/// Register exact secrets before producing diagnostics. Text redaction covers raw
/// strings, JSON's common escapes, and percent-encoded forms (including nested
/// encoding). It intentionally canonicalizes percent escapes in diagnostic text.
/// This is a best-effort filter, not a guarantee against every possible encoding,
/// partial secret, unregistered token, base64 payload or malicious transformation.
/// Prefer structured errors and suppressed bodies over free-form diagnostics.
public struct DiagnosticRedactor: Sendable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    private let patterns: [String]

    /// Registers secrets without retaining empty matching patterns.
    /// Longer overlapping secrets are matched first. The redactor has value
    /// semantics and no global registry; create a new instance when secrets change.
    /// - Parameter secrets: Exact secrets to conceal; empty entries are ignored.
    public init(secrets: [String] = []) {
        var variants = Set<String>()
        for secret in secrets where !secret.isEmpty {
            variants.insert(secret)
            variants.insert(Self.decodePercentEscapes(secret))
            let escaped = secret
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            variants.insert(escaped)
            variants.insert(escaped.replacingOccurrences(of: "/", with: "\\/"))
            variants.insert(secret.replacingOccurrences(of: " ", with: "+"))
        }
        patterns = variants.filter { !$0.isEmpty }.sorted {
            $0.utf8.count == $1.utf8.count ? $0 < $1 : $0.utf8.count > $1.utf8.count
        }
    }

    /// Conceals registered patterns after decoding valid percent escapes.
    /// Malformed percent text is preserved; valid escapes alongside it are still
    /// decoded. Each pass strictly consumes escapes; nested forms terminate.
    /// Runtime scales with input length, nesting depth and registered pattern count.
    /// - Parameter text: Diagnostic text, never a wire payload to send onward.
    /// - Returns: Canonicalized diagnostic text with recognized secrets replaced.
    public func redact(_ text: String) -> String {
        replaceRegisteredPatterns(in: Self.decodePercentEscapes(text))
    }

    /// Conceals sensitive header values and registered secrets in all other fields.
    /// Header matching is case-insensitive and conservatively treats names
    /// containing `token`, `secret` or `api-key` as sensitive as well.
    /// - Parameter headers: Header names and values; duplicate fields must already
    ///   have been represented by the caller's dictionary policy.
    /// - Returns: Diagnostic-only headers, with collisions after key redaction
    ///   resolved by replacing the colliding value with a redaction marker.
    public func headers(_ headers: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (name, value) in headers {
            let lower = name.lowercased().replacingOccurrences(of: "_", with: "-")
            let sensitive = ["authorization", "proxy-authorization", "cookie", "set-cookie"]
                .contains(lower) || lower.contains("token") || lower.contains("secret")
                || lower.contains("api-key")
            let safeName = redact(name)
            let safeValue = sensitive ? "[REDACTED]" : redact(value)
            result[safeName] = result[safeName] == nil ? safeValue : "[REDACTED]"
        }
        return result
    }

    /// Conceals webhook/interaction path tokens plus every query and fragment.
    /// This recognizes `/webhooks/{id}/{token}` and `/interactions/{id}/{token}`
    /// independently of registered secrets. Other path content uses the registered
    /// filter; arbitrary URL credentials or unknown token layouts are not inferred.
    /// - Parameter path: An endpoint path or URL for diagnostics only.
    /// Percent escapes are decoded after route-token removal, so an encoded slash
    /// inside a token cannot accidentally split it into diagnostic path segments.
    /// - Returns: A canonicalized string with recognized path credentials removed.
    public func path(_ path: String) -> String {
        let filtered = replaceRegisteredPatterns(in: path)
        let boundary = filtered.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? filtered.endIndex
        var components = filtered[..<boundary].split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for index in components.indices {
            let component = Self.decodePercentEscapes(components[index])
            if component == "webhooks" || component == "interactions", index + 2 < components.count {
                components[index + 2] = "[REDACTED]"
            }
        }
        return redact(components.joined(separator: "/")) + (boundary == filtered.endIndex ? "" : "?[REDACTED]")
    }

    /// Suppresses an entire body rather than attempting to infer all secret fields.
    /// - Parameter body: Text body for diagnostic reporting; it is never parsed.
    /// - Returns: Empty for an empty body, otherwise a fixed redaction marker.
    public func body(_ body: String) -> String {
        body.isEmpty ? "" : "[REDACTED BODY]"
    }

    /// A fixed description concealing the registered strings and their count.
    public var description: String { "DiagnosticRedactor([REDACTED])" }

    /// A fixed debug description concealing the registered strings.
    public var debugDescription: String { description }

    /// A mirror exposing no registered strings or derived matching patterns.
    public var customMirror: Mirror {
        Mirror(self, children: ["patterns": "[REDACTED]"])
    }

    /// Replaces registered forms without interpreting route delimiters or escapes.
    /// Keeping this step separate allows paths to remove whole encoded tokens
    /// before canonicalization can introduce additional slash characters.
    /// - Parameter text: A diagnostic string whose current spelling is preserved.
    /// - Returns: Text with exact registered patterns replaced longest-first.
    private func replaceRegisteredPatterns(in text: String) -> String {
        var result = text
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "[REDACTED]")
        }
        return result
    }

    /// Decodes valid UTF-8 percent triplets, including nested encodings.
    /// Invalid UTF-8 is replaced for diagnostics; malformed triplets remain literal.
    /// Each successful pass reduces encoded bytes, bounding the number of passes
    /// by the original byte count. It does not interpret form `+` as whitespace.
    /// - Parameter text: Arbitrary diagnostic text.
    /// - Returns: Percent-decoded text suitable only for diagnostic filtering.
    private static func decodePercentEscapes(_ text: String) -> String {
        var bytes = Array(text.utf8)
        while true {
            var decoded: [UInt8] = []
            decoded.reserveCapacity(bytes.count)
            var index = 0
            var changed = false
            while index < bytes.count {
                if bytes[index] == 37, index + 2 < bytes.count,
                    let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2])
                {
                    decoded.append(high * 16 + low)
                    index += 3
                    changed = true
                } else {
                    decoded.append(bytes[index])
                    index += 1
                }
            }
            if !changed { return String(decoding: bytes, as: UTF8.self) }
            bytes = decoded
        }
    }

    /// Converts one ASCII hexadecimal character without locale-sensitive parsing.
    /// - Parameter byte: A byte potentially containing `0...9`, `A...F` or `a...f`.
    /// - Returns: A nibble in `0...15`, or nil for any other byte.
    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 48...57: byte - 48
        case 65...70: byte - 55
        case 97...102: byte - 87
        default: nil
        }
    }
}
