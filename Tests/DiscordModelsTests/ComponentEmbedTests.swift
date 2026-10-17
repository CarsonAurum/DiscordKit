import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Verifies display-only component embeds, publishing limits and safe server-rendered metadata.
@Suite struct ComponentEmbedTests {
    /// Builders produce one Container with a link-only row and media; round trips retain exact wire fields.
    /// - Throws: Unexpected construction/validation errors fail the test.
    @Test func validDisplayBuilders() throws {
        let text = try ComponentEmbed.text("# Patch notes")
        let link = try ComponentEmbed.linkButton(label: "Read", url: "https://example.com/article")
        let row = try MessageComponent(jsonValue: .object(["type": .number(try JSONNumber(rawValue: "1")),
            "components": .array([try link.jsonValue()])]))
        let gallery = try ComponentEmbed.gallery(urls: ["https://example.com/1.avif", "http://example.com/2.mov"])
        let embed = try ComponentEmbed(components: [text, row, gallery], accentColor: 0x5865F2, spoiler: true)
        let data = try embed.validatedData()
        let reparsed = try ComponentEmbed(data: data)
        #expect(reparsed == embed && reparsed.jsonValue() == embed.jsonValue())
        #expect(embed.component.type.knownValue == .container && embed.component.accentColor == .value(0x5865F2))
        #expect(embed.component.spoiler == .value(true))
        #expect(link.style == .value(5) && link.customID == .absent && link.url == .value("https://example.com/article"))
        #expect(data.count < 3_000)
        let markup = try embed.inlineScript()
        #expect(markup.hasPrefix("<script id=\"discord:component-embed\" type=\"application/json\">"))
        #expect(markup.hasSuffix("</script>"))
        #expect(!String(reflecting: embed).contains("Patch notes"))
        #expect(embed.customMirror.children.count == 1)
    }

    /// Projection retains future fields/types but publication rejects them, preserving compatibility without inventing support.
    /// - Throws: Unexpected fixture/projection errors fail the test.
    @Test func projectionAndUnknowns() throws {
        let input = Data(#"{"component":{"type":99,"future":{"x":1.2300}},"extra":true}"#.utf8)
        let value = try ComponentEmbed(data: input)
        #expect(value.component.type.rawValue == 99)
        #expect(try value.jsonValue() == JSONValue.parse(input))
        #expect(throws: DiscordError.validation(.invalidValue)) { try value.validatedData() }
        for input in [#"{}"#, #"{"component":null}"#, #"{"component":{"type":"17"}}"#] {
            #expect(throws: DiscordError.transport(.invalidResponse)) { try ComponentEmbed(data: Data(input.utf8)) }
        }
        #expect(throws: JSONValueError.maximumBytesExceeded) { try ComponentEmbed(data: Data("{}".utf8), limits: .init(maximumBytes: 1)) }
    }

    /// Sections, thumbnail accessories, separators and emoji-only links remain display-only; interactive rows fail.
    /// - Throws: Unexpected fixture or valid-display validation errors fail the test.
    @Test func sectionMediaAndButtonVariants() throws {
        let section = try MessageComponent(data: Data(#"{"type":9,"components":[{"type":10,"content":"Details"}],"accessory":{"type":11,"media":{"url":"https://example.com/image.webp"},"description":"Alt","spoiler":true}}"#.utf8))
        let row = try MessageComponent(data: Data(#"{"type":1,"components":[{"type":2,"style":5,"url":"https://example.com","emoji":{"name":"🔗"},"disabled":false}]}"#.utf8))
        let separator = try MessageComponent(data: Data(#"{"type":14,"spacing":2,"divider":true}"#.utf8))
        let value = try ComponentEmbed(components: [section, separator, row])
        #expect(try value.validatedData().count < 3_000)
        for child in [#"{"type":1,"components":[{"type":2,"style":1,"label":"Run","custom_id":"run"}]}"#,
                      #"{"type":1,"components":[{"type":2,"style":5,"url":"https://example.com"}]}"#,
                      #"{"type":1,"components":[{"type":2,"style":5,"url":"javascript:run()","label":"Open"}]}"#,
                      #"{"type":9,"components":[{"type":10,"content":"x"}],"accessory":{"type":11,"media":{"url":"attachment://x.png"}}}"#,
                      #"{"type":12,"items":[{"media":{"url":"file:///private/image.png"}}]}"#] {
            let parsed = try MessageComponent(data: Data(child.utf8))
            #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed(components: [parsed]) }
        }
    }

    /// Outgoing display validation rejects interactive controls, unknown keys and nested Containers.
    /// - Parameter child: Independently authored invalid child JSON.
    /// - Throws: Unexpected fixture/projection errors fail the test.
    @Test(arguments: [#"{"type":2,"style":1,"custom_id":"run","label":"Run"}"#,
        #"{"type":2,"style":5,"url":"https://example.com","label":"Open","custom_id":"bad"}"#,
        #"{"type":2,"style":5,"url":"https://example.com"}"#,
        #"{"type":17,"components":[]}"#, #"{"type":13,"file":{"url":"attachment://a.txt"}}"#,
        #"{"type":99}"#, #"{"type":10,"content":"x","future":true}"#,
        #"{"type":11,"media":{"url":"https://example.com/a.png","width":1}}"#,
        #"{"type":11,"media":{"url":"attachment://a.png"}}"#])
    func invalidDisplayChildren(_ child: String) throws {
        let component = try MessageComponent(data: Data(child.utf8))
        #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed(components: [component]) }
    }

    /// The global component/gallery counts, RGB range and exact serialized/escaped byte budgets are enforced.
    /// - Throws: Unexpected fixture/construction errors fail the test.
    @Test func countsAndBytes() throws {
        let text = try ComponentEmbed.text("x")
        _ = try ComponentEmbed(components: Array(repeating: text, count: 39))
        #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed(components: Array(repeating: text, count: 40)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed(components: [text], accentColor: 0x1000000) }
        let five = try ComponentEmbed.gallery(urls: Array(repeating: "https://example.com/a.png", count: 5))
        _ = try ComponentEmbed(components: [five, five])
        #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed(components: [five, five, five]) }
        let minimal = try ComponentEmbed(components: [ComponentEmbed.text("")])
        let overhead = try minimal.validatedData().count
        let exact = try ComponentEmbed(components: [ComponentEmbed.text(String(repeating: "a", count: 3_000 - overhead))])
        #expect(try exact.validatedData().count == 3_000)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try ComponentEmbed(components: [ComponentEmbed.text(String(repeating: "a", count: 3_001 - overhead))])
        }
        let expanded = try ComponentEmbed(components: [ComponentEmbed.text(String(repeating: "<", count: 1_000))])
        #expect(try expanded.validatedData().count < 3_000)
        #expect(throws: DiscordError.validation(.invalidValue)) { try expanded.inlineScript() }
        let original = try ComponentEmbed(components: [ComponentEmbed.text("</script><img src=x>&")])
        let escaped = try original.inlineScript()
        #expect(!escaped.contains("</script><img"))
        #expect(escaped.contains("\\u003c") && escaped.contains("\\u003e") && escaped.contains("\\u0026"))
        let prefix = "<script id=\"discord:component-embed\" type=\"application/json\">"
        let embeddedJSON = escaped.dropFirst(prefix.count).dropLast("</script>".count)
        #expect(try ComponentEmbed(data: Data(embeddedJSON.utf8)) == original)
    }

    /// Invalid public URLs/counts/labels fail before markup or component publication, including malicious domain suffixes.
    /// - Parameter url: An invalid URL or one unsupported by the display contract.
    @Test(arguments: ["/relative", "attachment://image.png", "javascript:alert(1)", "https://user:password@example.com",
        "https://example.com/has space", "https://", "https://example.com/" + String(repeating: "x", count: 2_049)])
    func invalidURLs(_ url: String) {
        #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed.gallery(urls: [url]) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed.linkButton(label: "Open", url: url) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try LinkPreviewMetadata(title: "t", description: "d", pageURL: url) }
    }

    /// Gallery count/label/button limits and host relationship checks are independent of network state.
    /// - Throws: Unexpected valid-fixture failures fail the test.
    @Test func builderBoundariesAndLinkedJSON() throws {
        #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed.gallery(urls: []) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed.gallery(urls: Array(repeating: "https://example.com/x", count: 11)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed.linkButton(label: "", url: "https://example.com") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed.linkButton(label: String(repeating: "a", count: 81), url: "https://example.com") }
        _ = try ComponentEmbed.linkButton(label: String(repeating: "a", count: 80), url: "https://example.com")
        _ = try ComponentEmbed.gallery(urls: Array(repeating: "https://example.com", count: 10))
        for (json, page) in [("https://cdn.example.com/a?x=1&y=2", "https://example.com/page"),
                            ("https://example.com/a", "https://cdn.example.com/page"),
                            ("https://EXAMPLE.com/a", "https://example.com/page")] {
            let tag = try ComponentEmbed.linkedJSONTag(jsonURL: json, pageURL: page)
            #expect(tag.contains("rel=\"discord:component-embed\""))
            #expect(!tag.contains("x=1&y=2"))
        }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed.linkedJSONTag(jsonURL: "https://evil-example.com/a", pageURL: "https://example.com") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed.linkedJSONTag(jsonURL: "https://example.com.evil/a", pageURL: "https://example.com") }
        #expect(throws: DiscordError.validation(.invalidValue)) { try ComponentEmbed.linkedJSONTag(jsonURL: "https://example.com/a", pageURL: "/relative") }
    }

    /// Open Graph helpers escape all attribute delimiters, preserve long text for Discord trimming and omit absent fields.
    /// - Throws: Unexpected metadata-construction errors fail the test.
    @Test func metadataFallbackAndEscaping() throws {
        let value = try LinkPreviewMetadata(title: "\"<&>'", description: String(repeating: "d", count: 400),
            pageURL: "https://example.com/?x=1&y=2", imageURL: "https://example.com/image.avif",
            siteName: "Example", accentColor: 0x0055FF)
        let html = value.html()
        #expect(html.contains("&quot;&lt;&amp;&gt;&#39;"))
        #expect(html.contains("#0055FF") && html.contains("summary_large_image") && html.contains("og:site_name"))
        #expect(html.contains(String(repeating: "d", count: 400)))
        #expect(value.title == "\"<&>'" && value.previewDescription.count == 400)
        let minimal = try LinkPreviewMetadata(title: "t", description: "d", pageURL: "http://example.com")
        #expect(!minimal.html().contains("twitter:card") && !minimal.html().contains("theme-color") && !minimal.html().contains("og:site_name"))
        #expect(minimal.imageURL == nil && minimal.siteName == nil && minimal.accentColor == nil)
        #expect(throws: DiscordError.validation(.invalidValue)) { try LinkPreviewMetadata(title: "t", description: "d", pageURL: "https://example.com", siteName: String(repeating: "s", count: 257)) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try LinkPreviewMetadata(title: "t", description: "d", pageURL: "https://example.com", accentColor: 0x1000000) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try LinkPreviewMetadata(title: "t", description: "d", pageURL: "https://example.com", imageURL: "file:///tmp/image.png") }
    }
}
