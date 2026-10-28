// File: Sources/DiscordModels/ComponentEmbed.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation

/// Display-only website component embed, independent of messages, interaction routing and callbacks.
/// Response parsing preserves unknown fields; validatedData and inlineScript apply the current outgoing
/// contract. Discord must fetch server-rendered markup and assets within ten seconds; no helper here
/// fetches URLs or establishes that an embed will render. Verified 2026-10-17 against
/// https://docs.discord.com/developers/link-previews/component-embeds.
public struct ComponentEmbed: MessageResponseValue, MessageTreeProjectable, Equatable {
    public let component: MessageComponent
    public let rawFields: [String: JSONValue]

    /// Projects a bounded display document while retaining unknown keys and future component variants.
    /// - Parameters:
    ///   - data: Complete UTF-8 JSON document with a component object.
    ///   - limits: Whole-document parser bounds; defaults to library bounds, not outgoing embed limits.
    /// - Throws: JSON syntax/bounds or sanitized invalid-response errors for malformed modeled values.
    /// Parsing does not validate this document for publishing or perform network I/O.
    public init(data: Data, limits: JSONLimits = .default) throws {
        try self.init(value: JSONValue.parse(data, limits: limits), limits: limits)
    }

    /// Projects an immutable subtree already bounded at its containing document root.
    /// - Parameters:
    ///   - value: Original nonnull object retaining future keys.
    ///   - limits: Bounds established at the complete document root.
    /// - Throws: Sanitized invalid-response errors for missing or malformed component objects.
    init(value: JSONValue, limits: JSONLimits) throws {
        let object = try PayloadObject(value, limits: limits)
        guard let subtree = object.resource.fields["component"] else { throw DiscordError.transport(.invalidResponse) }
        component = try MessageComponent(verifiedValue: subtree, limits: limits)
        rawFields = object.resource.fields
    }

    /// Builds a single parent Container and validates a display-only component tree before publication.
    /// - Parameters:
    ///   - components: Ordered children; permitted display types total at most forty including the parent.
    ///   - accentColor: Optional RGB value in 0...0xFFFFFF; omitted by default.
    ///   - spoiler: Whether the parent is initially obscured; default false.
    /// - Throws: Sanitized invalid-value errors for unsupported/interactive components, invalid media/URLs,
    ///   nesting/count/schema violations or a serialized payload over 3,000 UTF-8 bytes; projection may
    ///   also throw safe JSON/schema errors. No handlers, listeners or network resources are created.
    public init(components: [MessageComponent], accentColor: UInt32? = nil, spoiler: Bool = false) throws {
        var fields: [String: JSONValue] = ["type": .number(try JSONNumber(rawValue: "17")),
            "components": .array(try components.map { try $0.jsonValue() }), "spoiler": .bool(spoiler)]
        if let accentColor { fields["accent_color"] = .number(try JSONNumber(rawValue: String(accentColor))) }
        try self.init(value: .object(["component": .object(fields)]), limits: .default)
        _ = try validatedData()
    }

    /// Validates the current display contract and returns deterministic JSON for an external JSON document.
    /// - Returns: A complete payload of at most 3,000 UTF-8 bytes; unknown retained keys are rejected for publishing.
    /// - Throws: Sanitized invalid-value errors for forbidden types/fields, non-link buttons, nested containers,
    ///   invalid HTTP(S) media, more than ten gallery items globally, more than forty components or excess bytes.
    /// This synchronous offline operation neither registers interaction handlers nor fetches assets.
    public func validatedData() throws -> Data {
        guard Set(rawFields.keys) == ["component"], component.type.knownValue == .container
        else { throw DiscordError.validation(.invalidValue) }
        try MessageComponent.validateMessage([component], componentsV2: true)
        var pending = [component]
        var galleryCount = 0
        while let node = pending.popLast() {
            guard let kind = node.type.knownValue,
                  [.container, .actionRow, .button, .section, .textDisplay, .thumbnail, .mediaGallery, .separator].contains(kind)
            else { throw DiscordError.validation(.invalidValue) }
            if kind == .button {
                let labelPresent: Bool
                let emojiPresent: Bool
                if case .value(let label) = node.label { labelPresent = !label.isEmpty } else { labelPresent = false }
                if case .value = node.emoji { emojiPresent = true } else { emojiPresent = false }
                guard node.style == .value(5), labelPresent || emojiPresent,
                      Set(node.rawFields.keys).isSubset(of: ["id", "type", "url", "style", "label", "emoji", "disabled"])
                else { throw DiscordError.validation(.invalidValue) }
                if case .value(let url) = node.url { try validatePreviewURL(url) }
            }
            if case .value(let media) = node.media { try validatePreviewURL(media.url) }
            if case .value(let items) = node.items {
                galleryCount += items.count
                guard galleryCount <= 10 else { throw DiscordError.validation(.invalidValue) }
                for item in items { try validatePreviewURL(item.media.url) }
            }
            if case .value(let children) = node.components { pending.append(contentsOf: children) }
            if case .value(let accessory) = node.accessory { pending.append(accessory) }
        }
        let data = try jsonValue().serialized()
        guard data.count <= 3_000 else { throw DiscordError.validation(.invalidValue) }
        return data
    }

    /// Renders safe server-side head markup with the required script ID and application/json type.
    /// - Returns: A complete script element whose escaped JSON payload remains at most 3,000 UTF-8 bytes.
    /// - Throws: Publishing validation errors, including payloads that exceed the byte limit after escaping.
    /// Less-than, greater-than and ampersand characters are JSON Unicode escapes, preventing script-tag
    /// termination by display content. Markup must be placed in the server-rendered head; no script executes.
    public func inlineScript() throws -> String {
        let data = try validatedData()
        let escaped = String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
        guard escaped.utf8.count <= 3_000 else { throw DiscordError.validation(.invalidValue) }
        return "<script id=\"discord:component-embed\" type=\"application/json\">\(escaped)</script>"
    }

    /// Renders a linked JSON declaration after checking Discord's page-host relationship requirement.
    /// - Parameters:
    ///   - jsonURL: Absolute HTTP(S) URL hosting validatedData; at most 2,048 Unicode scalars.
    ///   - pageURL: Absolute HTTP(S) page URL. JSON host must equal, contain or be a parent of this host.
    /// - Returns: An HTML-escaped link element for server-rendered head markup; performs no URL fetch.
    /// - Throws: Sanitized invalid-value errors for invalid schemes, credentials, hosts or unrelated domains.
    public static func linkedJSONTag(jsonURL: String, pageURL: String) throws -> String {
        let jsonHost = try validatePreviewURL(jsonURL)
        let pageHost = try validatePreviewURL(pageURL)
        guard jsonHost == pageHost || jsonHost.hasSuffix("." + pageHost) || pageHost.hasSuffix("." + jsonHost)
        else { throw DiscordError.validation(.invalidValue) }
        return "<link rel=\"discord:component-embed\" type=\"application/json\" href=\"\(previewHTMLEscape(jsonURL))\">"
    }

    /// Builds a text-display child for subsequent validated ComponentEmbed composition.
    /// - Parameter content: Discord markdown, including empty text; the final embed applies whole-payload bounds.
    /// - Returns: A display component with no interactive identity or handler.
    /// - Throws: Safe JSON bounds/schema errors if content exceeds the component parser's limits.
    public static func text(_ content: String) throws -> MessageComponent {
        try MessageComponent(jsonValue: .object(["type": .number(try JSONNumber(rawValue: "10")), "content": .string(content)]))
    }

    /// Builds a link button for a Section accessory or Action Row; it cannot emit an interaction.
    /// - Parameters:
    ///   - label: Nonempty label of at most eighty Unicode scalars.
    ///   - url: Absolute HTTP(S) target of at most 512 Unicode scalars, matching current button constraints.
    /// - Returns: A link-style button; callers place it in a valid display parent.
    /// - Throws: Sanitized invalid-value errors for invalid labels/URLs, or safe JSON/schema errors.
    public static func linkButton(label: String, url: String) throws -> MessageComponent {
        guard (1...80).contains(label.unicodeScalars.count), url.unicodeScalars.count <= 512
        else { throw DiscordError.validation(.invalidValue) }
        try validatePreviewURL(url)
        return try MessageComponent(jsonValue: .object(["type": .number(try JSONNumber(rawValue: "2")),
            "style": .number(try JSONNumber(rawValue: "5")), "label": .string(label), "url": .string(url)]))
    }

    /// Builds a bounded gallery of public HTTP(S) media URLs without fetching or classifying files.
    /// - Parameter urls: One through ten absolute media URLs; the complete embed shares one ten-item limit.
    /// - Returns: An ordered display gallery whose media contains only developer-writable URLs.
    /// - Throws: Sanitized invalid-value errors for count/URL violations, or safe JSON/schema errors.
    public static func gallery(urls: [String]) throws -> MessageComponent {
        guard (1...10).contains(urls.count) else { throw DiscordError.validation(.invalidValue) }
        for url in urls { try validatePreviewURL(url) }
        return try MessageComponent(jsonValue: .object(["type": .number(try JSONNumber(rawValue: "12")),
            "items": .array(urls.map { .object(["media": .object(["url": .string($0)])]) })]))
    }
}

/// Open Graph fallback metadata for website display; it never represents an interaction or authorization.
/// Discord may trim titles/descriptions and can decline to render a preview; these helpers provide markup only.
public struct LinkPreviewMetadata: Sendable, Equatable {
    public let title: String
    public let previewDescription: String
    public let pageURL: String
    public let imageURL: String?
    public let siteName: String?
    public let accentColor: UInt32?

    /// Validates immutable fallback values without fetching URLs or truncating human-authored text.
    /// - Parameters:
    ///   - title: Display title; Discord trims after seventy bytes or three lines.
    ///   - description: Display description; Discord trims after 350 bytes or twenty lines.
    ///   - pageURL: Absolute HTTP(S) canonical page URL, at most 2,048 Unicode scalars.
    ///   - imageURL: Optional absolute HTTP(S) image URL, with the same bound; nil omits image tags.
    ///   - siteName: Optional provider text of at most 256 Unicode scalars; nil omits the provider tag.
    ///   - accentColor: Optional RGB integer in 0...0xFFFFFF; nil omits the theme-color tag.
    /// - Throws: Sanitized invalid-value errors for invalid URLs, provider length or RGB range.
    public init(title: String, description: String, pageURL: String, imageURL: String? = nil,
                siteName: String? = nil, accentColor: UInt32? = nil) throws {
        try validatePreviewURL(pageURL)
        if let imageURL { try validatePreviewURL(imageURL) }
        guard siteName.map({ $0.unicodeScalars.count <= 256 }) ?? true,
              accentColor.map({ $0 <= 0xFFFFFF }) ?? true else { throw DiscordError.validation(.invalidValue) }
        self.title = title
        previewDescription = description
        self.pageURL = pageURL
        self.imageURL = imageURL
        self.siteName = siteName
        self.accentColor = accentColor
    }

    /// Renders deterministic escaped metadata suitable for the page's server-rendered head.
    /// - Returns: Open Graph title/description/url/type plus optional provider/image/color and a large-image
    ///   Twitter fallback when an image exists. Escaping preserves quotes, ampersands and markup as data.
    /// No JavaScript, network request, token access or interaction registration occurs.
    public func html() -> String {
        var fields = [("og:title", title), ("og:description", previewDescription), ("og:url", pageURL), ("og:type", "article")]
        if let siteName { fields.append(("og:site_name", siteName)) }
        if let imageURL { fields.append(("og:image", imageURL)) }
        var tags = fields.map { "<meta property=\"\($0.0)\" content=\"\(previewHTMLEscape($0.1))\">" }
        if let accentColor { tags.append("<meta name=\"theme-color\" content=\"\(String(format: "#%06X", accentColor))\">") }
        if imageURL != nil { tags.append("<meta name=\"twitter:card\" content=\"summary_large_image\">") }
        return tags.joined(separator: "\n")
    }
}

/// Validates a public display URL without resolving a host or fetching content.
/// - Parameter value: An absolute HTTP(S) URL of at most 2,048 Unicode scalars, without embedded credentials.
/// - Returns: Lowercased host for exact domain-label relationship checks.
/// - Throws: Sanitized invalid-value errors for malformed, relative, oversized or non-HTTP(S) URLs.
@discardableResult private func validatePreviewURL(_ value: String) throws -> String {
    guard value.unicodeScalars.count <= 2_048,
          !value.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.value < 32 || $0.value == 127 }),
          let url = URLComponents(string: value), let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty,
          url.user == nil, url.password == nil else { throw DiscordError.validation(.invalidValue) }
    return host.lowercased()
}

/// Escapes text for a double-quoted HTML attribute without interpreting any markup or entities.
/// - Parameter value: Arbitrary display text or a previously validated URL.
/// - Returns: Text with ampersand, angle brackets and both quote forms safely escaped, in that order.
private func previewHTMLEscape(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}
