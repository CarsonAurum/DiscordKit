import DiscordCore
import Foundation

/// Marker distinguishing standard sticker-pack snowflakes from sticker and SKU identifiers.
public enum StickerPackTag: Sendable {}
/// Exact unsigned identifier of a standard sticker pack.
public typealias StickerPackID = Snowflake<StickerPackTag>
/// Marker distinguishing sticker-pack banner assets from other CDN resources.
public enum StickerPackBannerAssetTag: Sendable {}
/// Exact unsigned identifier of a sticker-pack banner image; parsing never fetches it.
public typealias StickerPackBannerAssetID = Snowflake<StickerPackBannerAssetTag>
/// Shared API v10 sticker-format discriminator already used by message sticker items.
public typealias StickerFormatType = MessageStickerFormatType

/// Known API v10 sticker origins; `RawValue` retains future integer origins without claiming support.
public enum StickerType: Int, Sendable, CaseIterable {
    /// Official sticker distributed in a standard pack, potentially subject to Nitro eligibility.
    case standard = 1
    /// Sticker uploaded by a guild member and subject to current guild availability.
    case guild = 2
}

/// Complete written API v10 sticker projection, verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/sticker. Boost availability and use eligibility are
/// snapshots, not authorization. Unknown formats and fields remain readable; creation limits are not
/// retroactively imposed on server snapshots. Sticker items in messages use `MessageStickerItem`.
public struct Sticker: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required sticker snowflake, preserving all unsigned bits.
    public let id: StickerID
    /// Optional pack ID for standard stickers.
    public let packID: Field<StickerPackID>
    /// Required server-provided name, retained without normalization.
    public let name: String
    /// Required nullable description; null remains distinct from an empty string.
    public let stickerDescription: Nullable<String>
    /// Required autocomplete tags; server responses can exceed current creation limits.
    public let tags: String
    /// Required origin, including unknown future integer values.
    public let type: RawValue<StickerType>
    /// Required nonnull format according to the written reference, including future integers.
    public let formatType: RawValue<StickerFormatType>
    /// Optional current usability; false can reflect lost Server Boosts.
    public let available: Field<Bool>
    /// Optional owning guild, ordinarily present for guild stickers.
    public let guildID: Field<GuildID>
    /// Optional uploader using the existing partial user projection and retaining unknown user fields.
    public let user: Field<MessageAuthor>
    /// Optional signed ordering value within a standard pack.
    public let sortValue: Field<Int>
    /// Original complete object and unknown subtrees, concealed by ordinary diagnostics.
    public let rawFields: [String: JSONValue]

    /// Parses one bounded immutable sticker without media fetching or server-state lookups.
    /// - Parameters:
    ///   - data: Complete UTF-8 object; required fields follow the written Sticker Structure.
    ///   - limits: Bounds for the whole tree, including unknown values; defaults to 1 MiB/64 depth/100,000 nodes.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for malformed fields,
    ///   missing required data, forbidden nulls, invalid snowflakes or nonintegral discriminators.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an already bounded subtree, retaining exact presence without revalidating upload rules.
    /// - Parameters:
    ///   - value: Original nonnull object from a fully bounded root.
    ///   - limits: Bounds established by the containing parse and reused for scalar decoding.
    /// - Throws: Sanitized invalid-response errors for incompatible required/optional fields or nested users.
    ///   Work is synchronous and has no I/O, cancellation suspension, mutation or resource ownership.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", StickerID.self)
        packID = try object.field("pack_id", StickerPackID.self)
        name = try object.required("name", String.self)
        stickerDescription = try object.required("description", Nullable<String>.self)
        tags = try object.required("tags", String.self)
        type = try object.required("type", RawValue<StickerType>.self)
        formatType = try object.required("format_type", RawValue<StickerFormatType>.self)
        available = try object.field("available", Bool.self)
        guildID = try object.field("guild_id", GuildID.self)
        user = try object.messageField("user", MessageAuthor.self)
        sortValue = try object.field("sort_value", Int.self)
        rawFields = object.resource.fields
    }
}

/// An official API v10 sticker pack, including all written fields and its ordered full sticker objects.
/// SKU presence does not establish purchase rights, Nitro status or current sticker eligibility.
public struct StickerPack: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Required pack snowflake.
    public let id: StickerPackID
    /// Required complete ordered sticker list; an empty pack remains valid.
    public let stickers: [Sticker]
    /// Required pack name.
    public let name: String
    /// Required pack SKU identifier without depending on a monetization runtime.
    public let skuID: SKUID
    /// Optional sticker chosen as the pack icon; membership is not inferred from a snapshot.
    public let coverStickerID: Field<StickerID>
    /// Required nonnull pack description according to the written reference.
    public let packDescription: String
    /// Optional CDN banner asset identifier; this value performs no fetching.
    public let bannerAssetID: Field<StickerPackBannerAssetID>
    /// Complete original pack and future fields with exact numeric lexemes.
    public let rawFields: [String: JSONValue]

    /// Parses a bounded pack, including every nested sticker, without media or purchase requests.
    /// - Parameters:
    ///   - data: Complete UTF-8 pack object; unknown fields are preserved.
    ///   - limits: Whole-document bounds shared by all nested stickers and unknown fields.
    /// - Throws: Parser/bounds errors or sanitized invalid-response errors for missing/mistyped
    ///   fields, forbidden nulls, invalid IDs or malformed sticker elements; no partial pack escapes.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a pack subtree after its entire containing document passed parser limits.
    /// - Parameters:
    ///   - value: Original pack object sharing immutable JSON subtree storage.
    ///   - limits: Containing parse bounds, reused for exact scalar projection.
    /// - Throws: Sanitized invalid-response errors for incompatible pack/sticker fields.
    ///   Construction is synchronous, side-effect free, nonblocking and independent of task cancellation.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        id = try object.required("id", StickerPackID.self)
        stickers = try object.messageModels("stickers", Sticker.self)
        name = try object.required("name", String.self)
        skuID = try object.required("sku_id", SKUID.self)
        coverStickerID = try object.field("cover_sticker_id", StickerID.self)
        packDescription = try object.required("description", String.self)
        bannerAssetID = try object.field("banner_asset_id", StickerPackBannerAssetID.self)
        rawFields = object.resource.fields
    }
}

/// API v10 standard-pack collection under the documented `sticker_packs` envelope.
public struct StickerPackList: MessageResponseValue, MessageTreeProjectable, Equatable {
    /// Complete ordered pack list, including a permitted empty collection.
    public let stickerPacks: [StickerPack]
    /// Original envelope and future fields; default diagnostics conceal all payload content.
    public let rawFields: [String: JSONValue]

    /// Parses a bounded pack collection without pagination, I/O or background work.
    /// - Parameters:
    ///   - data: Complete UTF-8 object with a required nonnull `sticker_packs` array.
    ///   - limits: Shared bounds for the envelope, packs, stickers and unknown nested fields.
    /// - Throws: JSON syntax/bounds errors or sanitized invalid-response errors for malformed
    ///   roots, absent/mistyped arrays or invalid nested objects; callers must correct invalid input.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects a collection subtree once its containing root has passed parser limits.
    /// - Parameters:
    ///   - value: Original envelope object from the bounded root.
    ///   - limits: Bounds established by that parse; reused rather than reset for nested objects.
    /// - Throws: Sanitized invalid-response errors for incompatible envelope or pack fields.
    ///   Work is synchronous, side-effect free and has no suspension or external resource ownership.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        stickerPacks = try object.messageModels("sticker_packs", StickerPack.self)
        rawFields = object.resource.fields
    }
}
