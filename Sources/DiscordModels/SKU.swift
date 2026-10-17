import DiscordCore
import Foundation

/// Complete written API v10 SKU offering snapshot, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/sku. Example-only and future fields remain in `rawFields`.
/// This immutable value describes an offering; availability, flags and type do not establish premium access.
public struct SKU: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Exact offering identifier.
    public let id: SKUID
    /// Offering kind, retaining unrecognized integral wire values.
    public let type: RawValue<SKUType>
    /// Parent application identifier.
    public let applicationID: ApplicationID
    /// Customer-facing offering name, without outgoing mutation validation or normalization.
    public let name: String
    /// System-generated offering URL slug.
    public let slug: String
    /// Exact unsigned bitfield; wrap with `SKUFlags` for named membership checks.
    public let flags: UInt64
    /// Complete exact object, including unknown fields and numeric lexemes; ordinary diagnostics redact it.
    public let rawFields: [String: JSONValue]

    /// Parses one complete offering object synchronously without fetching prices, access or related resources.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON object; duplicate keys and trailing documents are rejected.
    ///   - limits: Whole-document byte/depth/node bounds including unknown subtrees; default is 1 MiB/64/100,000.
    /// - Throws: `JSONValueError` for syntax, duplicate keys, invalid limits or exceeded bounds; sanitized
    ///   `DiscordError.transport(.invalidResponse)` for missing, null, mistyped or out-of-range known fields,
    ///   invalid decimal snowflakes or nonintegral numeric discriminators/flags. Correct the response before retrying.
    /// Parsing owns no external resources, performs no I/O or suspension, and does not check task cancellation.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable offering subtree after the complete containing document passed parser bounds.
    /// - Parameters:
    ///   - value: Original nonnull object subtree; unknown fields remain shared and unchanged.
    ///   - limits: Root-document limits reused for scalar projection and exact integer validation.
    /// - Throws: Sanitized invalid-response errors for nonobjects or incompatible/missing known fields;
    ///   scalar serialization can report supplied limit errors. Future kinds and flag bits remain valid responses.
    /// Construction is synchronous, has no suspension or ownership changes, and grants no access or permissions.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", SKUID.self)
        type = try object.required("type", RawValue<SKUType>.self)
        applicationID = try object.required("application_id", ApplicationID.self)
        name = try object.required("name", String.self)
        slug = try object.required("slug", String.self)
        flags = try object.required("flags", UInt64.self)
        rawFields = object.resource.fields
    }
}
