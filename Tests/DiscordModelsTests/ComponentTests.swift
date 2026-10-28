// File: Tests/DiscordModelsTests/ComponentTests.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import Foundation
import Testing
@testable import DiscordModels

/// Validates component wire projections and current message request rules without live Discord activity.
@Suite struct ComponentTests {
    /// Recognizes every published discriminator including the newest modal component kinds.
    /// - Parameter type: One current component discriminator; partial responses require only this key.
    @Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 17, 18, 19, 21, 22, 23])
    func currentKinds(type: Int) throws {
        let component = try parse("{\"type\":\(type)}")
        #expect(component.type.rawValue == type)
        #expect(component.type.knownValue != nil)
        #expect(component.id == .absent)
        #expect(component.components == .absent)
        #expect(component.accessory == .absent)
        #expect(component.component == .absent)
        #expect(component.value == .absent)
        #expect(component.channelTypes == .absent)
    }

    /// Projects all common and nested fields, preserving exact future metadata and reflection redaction.
    @Test func completeTypedFieldsAndNestedDiagnostics() throws {
        let component = try parse("""
        {"type":11,"id":4294967295,"custom_id":"secret","components":[{"type":10,"content":"child"}],
         "accessory":{"type":2,"style":1},"component":{"type":4,"value":"preset"},"style":99,"label":"label",
         "emoji":{"id":null,"name":"😀","animated":false},"sku_id":"18446744073709551615","url":"https://example.test",
         "disabled":true,"options":[{"label":"One","value":"one","description":"option","emoji":{"name":"😀"},"default":true}],
         "placeholder":"choose","min_values":0,"max_values":25,"required":false,
         "default_values":[{"id":"18446744073709551615","type":"future"}],"channel_types":[0,999],
         "min_length":0,"max_length":4000,"value":"text","values":["1"],"resolved":{"users":{},"future":1.2300},
         "content":"content","media":{"url":"attachment://image.png","proxy_url":"https://proxy.test","height":null,"width":42,
         "placeholder":"hash","placeholder_version":99,"content_type":"image/png","flags":18446744073709551615,"attachment_id":"18446744073709551615"},
         "description":null,"spoiler":true,"items":[{"media":{"url":"https://example.test/image"},"description":null,"spoiler":false}],
         "file":{"url":"attachment://file.txt"},"name":"file.txt","size":18446744073709551615,"divider":false,"spacing":2,
         "accent_color":null,"file_types":["image",".pdf"],"default":true,"future":1e1000}
        """)
        #expect(component.id == .value(UInt32.max))
        #expect(component.customID == .value("secret"))
        #expect(component.style == .value(99))
        #expect(component.label == .value("label"))
        #expect(component.skuID == .value("18446744073709551615"))
        #expect(component.url == .value("https://example.test"))
        #expect(component.disabled == .value(true))
        #expect(component.placeholder == .value("choose"))
        #expect(component.minValues == .value(0))
        #expect(component.maxValues == .value(25))
        #expect(component.required == .value(false))
        #expect(component.channelTypes == .value([0, 999]))
        #expect(component.minLength == .value(0))
        #expect(component.maxLength == .value(4000))
        #expect(component.value == .value(.text("text")))
        #expect(component.values == .value(["1"]))
        #expect(component.content == .value("content"))
        #expect(component.componentDescription == .null)
        #expect(component.spoiler == .value(true))
        #expect(component.name == .value("file.txt"))
        #expect(component.size == .value(UInt64.max))
        #expect(component.divider == .value(false))
        #expect(component.spacing == .value(2))
        #expect(component.accentColor == .null)
        #expect(component.fileTypes == .value(["image", ".pdf"]))
        #expect(component.isDefault == .value(true))
        guard case .value(let children) = component.components, case .value(let accessory) = component.accessory,
              case .value(let child) = component.component, case .value(let options) = component.options,
              case .value(let defaults) = component.defaultValues, case .value(let media) = component.media,
              case .value(let items) = component.items, case .value(let file) = component.file,
              case .value(let emoji) = component.emoji
        else { Issue.record("Missing projected fields"); return }
        #expect(children.count == 1)
        #expect(accessory.style == .value(1))
        #expect(child.value == .value(.text("preset")))
        #expect(options[0].label == "One")
        #expect(options[0].value == "one")
        #expect(options[0].optionDescription == .value("option"))
        #expect(options[0].isDefault == .value(true))
        #expect(options[0].emoji != .absent)
        #expect(defaults[0].id == "18446744073709551615")
        #expect(defaults[0].type == "future")
        #expect(media.url == "attachment://image.png")
        #expect(media.proxyURL == .value("https://proxy.test"))
        #expect(media.height == .null)
        #expect(media.width == .value(42))
        #expect(media.placeholder == .value("hash"))
        #expect(media.placeholderVersion == .value(99))
        #expect(media.contentType == .value("image/png"))
        #expect(media.flags == .value(UInt64.max))
        #expect(media.attachmentID == .value("18446744073709551615"))
        #expect(items[0].itemDescription == .null)
        #expect(items[0].spoiler == .value(false))
        #expect(file.url == "attachment://file.txt")
        #expect(component.rawFields["future"] == .number(try JSONNumber(rawValue: "1e1000")))
        #expect(try component.jsonValue() == JSONValue.parse(JSONValue.object(component.rawFields).serialized()))
        #expect(component == (try MessageComponent(jsonValue: component.jsonValue())))
        let objects: [any CustomStringConvertible & CustomDebugStringConvertible & CustomReflectable] = [
            component, children[0], accessory, child, options[0], defaults[0], media, items[0], file, emoji
        ]
        for object in objects {
            #expect(object.description.hasSuffix("(redacted)"))
            #expect(object.debugDescription == object.description)
            #expect(!object.description.contains("secret"))
            #expect(object.customMirror.children.count == 1)
        }
    }

    /// Future component types preserve arbitrary current-looking fields without imposing today's schema.
    @Test func unknownVariantsAndInputValues() throws {
        let future = try parse("{\"type\":999,\"components\":null,\"id\":\"future\",\"value\":1.2300}")
        #expect(future.type.knownValue == nil)
        #expect(future.id == .absent)
        #expect(future.rawFields["components"] == .null)
        #expect(future.rawFields["value"] == .number(try JSONNumber(rawValue: "1.2300")))
        #expect(future != (try parse("{\"type\":998}")))
        #expect(try parse("{\"type\":21,\"value\":null}").value == .null)
        #expect(try parse("{\"type\":23,\"value\":true}").value == .value(.checked(true)))
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage([future], componentsV2: true) }
    }

    /// All public nested parsers retain absent defaults, nullable dimensions, and partial emoji details.
    @Test func standaloneNestedParsers() throws {
        let option = try ComponentOption(data: Data("{\"label\":\"L\",\"value\":\"V\"}".utf8))
        #expect(option.optionDescription == .absent)
        #expect(option.emoji == .absent)
        #expect(option.isDefault == .absent)
        #expect(try ComponentDefaultValue(data: Data("{\"id\":\"0\",\"type\":\"user\"}".utf8)).id == "0")
        let media = try UnfurledMediaItem(data: Data("{\"url\":\"url\",\"height\":0,\"width\":null}".utf8))
        #expect(media.height == .value(0))
        #expect(media.width == .null)
        #expect(media.proxyURL == .absent)
        #expect(media.flags == .absent)
        let item = try MediaGalleryItem(data: Data("{\"media\":{\"url\":\"url\"},\"description\":\"alt\"}".utf8))
        #expect(item.itemDescription == .value("alt"))
        #expect(item.spoiler == .absent)
        #expect(item == (try MediaGalleryItem(data: JSONValue.object(item.rawFields).serialized())))
    }

    /// Rejects wrong wire types, optional nulls, missing nested requirements, and imprecise integers.
    /// - Parameter json: Complete malformed component object.
    @Test(arguments: ["{}", "[]", "{\"type\":null}", "{\"type\":\"1\"}", "{\"type\":1e0}", "{\"type\":1.00000000000000001}",
                      "{\"type\":1,\"id\":-1}", "{\"type\":1,\"id\":4294967296}", "{\"type\":1,\"custom_id\":null}",
                      "{\"type\":1,\"components\":null}", "{\"type\":1,\"components\":[1]}", "{\"type\":9,\"accessory\":[]}",
                      "{\"type\":18,\"component\":{}}", "{\"type\":2,\"style\":1.5}", "{\"type\":2,\"sku_id\":\"abc\"}",
                      "{\"type\":3,\"options\":[{}]}", "{\"type\":8,\"channel_types\":[1e0]}", "{\"type\":4,\"value\":42}", "{\"type\":4,\"value\":false}", "{\"type\":21,\"value\":true}", "{\"type\":23,\"value\":\"yes\"}",
                      "{\"type\":4,\"value\":null}", "{\"type\":5,\"resolved\":[]}", "{\"type\":11,\"media\":{}}",
                      "{\"type\":18,\"description\":null}", "{\"type\":12,\"items\":[{}]}", "{\"type\":13,\"size\":-1}",
                      "{\"type\":5,\"default_values\":[{\"id\":\"18446744073709551616\",\"type\":\"user\"}]}" ])
    func malformedFields(json: String) throws {
        #expect(throws: DiscordError.transport(.invalidResponse)) { try parse(json) }
    }

    /// Parser limits precede typed traversal and syntax errors never expose payload content.
    @Test func boundsAndSafeErrors() throws {
        let data = Data("{\"type\":10,\"content\":\"sensitive\",\"future\":{}}".utf8)
        #expect(throws: JSONValueError.maximumBytesExceeded) { try MessageComponent(data: data, limits: JSONLimits(maximumBytes: 1)) }
        #expect(throws: JSONValueError.maximumDepthExceeded) { try MessageComponent(data: data, limits: JSONLimits(maximumDepth: 1)) }
        let tree = try JSONValue.parse(data)
        #expect(throws: JSONValueError.maximumBytesExceeded) { try MessageComponent(jsonValue: tree, limits: JSONLimits(maximumBytes: 1)) }
        #expect(throws: JSONValueError.maximumDepthExceeded) { try MessageComponent(jsonValue: tree, limits: JSONLimits(maximumDepth: 1)) }
        #expect(throws: JSONValueError.maximumNodesExceeded) { try MessageComponent(jsonValue: tree, limits: JSONLimits(maximumNodes: 1)) }
        #expect(throws: JSONValueError.maximumNodesExceeded) { try MessageComponent(data: data, limits: JSONLimits(maximumNodes: 1)) }
        #expect(throws: JSONValueError.self) { try parse("{sensitive") }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try UnfurledMediaItem(data: Data("{\"url\":\"x\",\"attachment_id\":\"invalid\"}".utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try ComponentOption(data: Data("{}".utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try ComponentDefaultValue(data: Data("{}".utf8)) }
        #expect(throws: DiscordError.transport(.invalidResponse)) { try MediaGalleryItem(data: Data("{}".utf8)) }
    }

    /// Every message button style and auto-populated select kind can be placed inside a valid legacy row.
    @Test func legacyButtonsAndSelectKinds() throws {
        for json in ["{\"type\":2,\"style\":1,\"custom_id\":\"a\",\"label\":\"Go\",\"emoji\":{\"name\":\"😀\"}}",
                     "{\"type\":2,\"style\":2,\"custom_id\":\"a\"}", "{\"type\":2,\"style\":3,\"custom_id\":\"a\"}",
                     "{\"type\":2,\"style\":4,\"custom_id\":\"a\"}", "{\"type\":2,\"style\":5,\"url\":\"https://example.test\"}",
                     "{\"type\":2,\"style\":6,\"sku_id\":\"18446744073709551615\"}",
                     "{\"type\":3,\"custom_id\":\"a\",\"min_values\":0,\"options\":[{\"label\":\"L\",\"value\":\"V\",\"description\":\"D\",\"default\":true,\"emoji\":{\"id\":\"1\"}}]}"] {
            try MessageComponent.validateMessage([row(json)], componentsV2: false)
        }
        for (type, defaultType) in [(5, "user"), (6, "role"), (7, "role"), (8, "channel")] {
            let json = "{\"type\":\(type),\"custom_id\":\"a\",\"default_values\":[{\"id\":\"1\",\"type\":\"\(defaultType)\"}]}"
            try MessageComponent.validateMessage([row(json)], componentsV2: false)
        }
        try MessageComponent.validateMessage([], componentsV2: false)
        try MessageComponent.validateMessage([row("{\"type\":2,\"style\":1,\"custom_id\":\"\(String(repeating: "😀", count: 100))\",\"id\":0}")], componentsV2: false)
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage(Array(repeating: row("{\"type\":2,\"style\":5,\"url\":\"url\"}"), count: 6), componentsV2: false) }
    }

    /// V2 content/layout trees accept all current message component kinds and count every nested node.
    @Test func validV2AndGlobalBounds() throws {
        let tree = try parse("""
        {"type":17,"accent_color":16777215,"components":[
          {"type":9,"components":[{"type":10,"content":"A"}],"accessory":{"type":11,"media":{"url":"https://example.test/image"},"description":null}},
          {"type":9,"components":[{"type":10,"content":"B"}],"accessory":{"type":2,"style":1,"custom_id":"go"}},
          {"type":12,"items":[{"media":{"url":"attachment://image.png"},"description":"alt","spoiler":true}]},
          {"type":13,"file":{"url":"attachment://file.txt"},"spoiler":true},
          {"type":14,"divider":true,"spacing":2},
          {"type":1,"components":[{"type":2,"style":5,"url":"https://example.test"}]}]}
        """)
        try MessageComponent.validateMessage([tree], componentsV2: true)
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage([tree], componentsV2: false) }
        let text = try parse("{\"type\":10,\"content\":\"A\"}")
        try MessageComponent.validateMessage(Array(repeating: text, count: 40), componentsV2: true)
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage(Array(repeating: text, count: 41), componentsV2: true) }
        let nested = try MessageComponent(jsonValue: .object(["type": .number(JSONNumber(rawValue: "17")), "components": .array(Array(repeating: text.jsonValue(), count: 40))]))
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage([nested], componentsV2: true) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage([parse("{\"type\":10,\"id\":1,\"content\":\"a\"}"), parse("{\"type\":10,\"id\":1,\"content\":\"b\"}")], componentsV2: true) }
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage([row("{\"type\":2,\"style\":1,\"custom_id\":\"same\"},{\"type\":2,\"style\":1,\"custom_id\":\"same\"}")], componentsV2: true) }
    }

    /// Incompatible style fields, string bounds, nesting, response metadata, and absent required keys fail locally.
    /// - Parameter json: Invalid message component; top-level arrays are validated separately.
    @Test(arguments: ["{\"type\":2,\"style\":1,\"custom_id\":\"a\"}", "{\"type\":1,\"components\":[]}",
                      "{\"type\":1,\"components\":[{\"type\":10,\"content\":\"x\"}]}",
                      "{\"type\":1,\"components\":[{\"type\":2,\"style\":0,\"custom_id\":\"a\"}]}",
                      "{\"type\":1,\"components\":[{\"type\":2,\"style\":1}]}",
                      "{\"type\":1,\"components\":[{\"type\":2,\"style\":1,\"custom_id\":\"\"}]}",
                      "{\"type\":1,\"components\":[{\"type\":2,\"style\":1,\"custom_id\":\"a\",\"url\":\"url\"}]}",
                      "{\"type\":1,\"components\":[{\"type\":2,\"style\":5,\"url\":\"url\",\"custom_id\":\"a\"}]}",
                      "{\"type\":1,\"components\":[{\"type\":2,\"style\":6,\"sku_id\":\"1\",\"label\":\"Buy\"}]}",
                      "{\"type\":1,\"components\":[{\"type\":2,\"style\":6}]}",
                      "{\"type\":1,\"components\":[{\"type\":2,\"style\":1,\"custom_id\":\"a\",\"emoji\":{}}]}",
                      "{\"type\":9,\"components\":[{\"type\":10,\"content\":\"a\"}],\"accessory\":{\"type\":10,\"content\":\"b\"}}",
                      "{\"type\":9,\"components\":[],\"accessory\":{\"type\":2,\"style\":1,\"custom_id\":\"a\"}}",
                      "{\"type\":10}", "{\"type\":10,\"content\":\"a\",\"future\":true}",
                      "{\"type\":12,\"items\":[]}", "{\"type\":12,\"items\":[{\"media\":{\"url\":\"u\",\"width\":1}}]}",
                      "{\"type\":13,\"file\":{\"url\":\"https://example.test/file\"}}", "{\"type\":13,\"file\":{\"url\":\"attachment://\"}}",
                      "{\"type\":13,\"file\":{\"url\":\"attachment://f\"},\"name\":\"f\"}", "{\"type\":14,\"spacing\":3}",
                      "{\"type\":17,\"components\":[],\"accent_color\":16777216}",
                      "{\"type\":17,\"components\":[{\"type\":17,\"components\":[]}]}",
                      "{\"type\":18,\"label\":\"Modal\",\"component\":{\"type\":23,\"custom_id\":\"x\"}}" ])
    func invalidMessageDefinitions(json: String) throws {
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage([parse(json)], componentsV2: true) }
    }

    /// Select-specific count, default type, option uniqueness, and text boundaries are enforced.
    @Test func invalidSelectsAndLengths() throws {
        for json in ["{\"type\":3,\"custom_id\":\"a\"}", "{\"type\":3,\"custom_id\":\"a\",\"options\":[]}",
                     "{\"type\":3,\"custom_id\":\"a\",\"options\":[{\"label\":\"L\",\"value\":\"V\"},{\"label\":\"M\",\"value\":\"V\"}]}",
                     "{\"type\":5,\"custom_id\":\"a\",\"min_values\":2,\"max_values\":1}",
                     "{\"type\":5,\"custom_id\":\"a\",\"max_values\":26}",
                     "{\"type\":5,\"custom_id\":\"a\",\"default_values\":[{\"id\":\"1\",\"type\":\"role\"}]}",
                     "{\"type\":5,\"custom_id\":\"a\",\"default_values\":[]}",
                     "{\"type\":3,\"custom_id\":\"a\",\"options\":[{\"label\":\"\",\"value\":\"V\"}]}"] {
            #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage([row(json)], componentsV2: false) }
        }
        for (key, value) in [("label", String(repeating: "x", count: 81)), ("custom_id", String(repeating: "x", count: 101))] {
            var fields: [String: JSONValue] = ["type": .number(try JSONNumber(rawValue: "2")), "style": .number(try JSONNumber(rawValue: "1")), "custom_id": .string("a")]
            fields[key] = .string(value)
            let json = String(decoding: try JSONValue.object(fields).serialized(), as: UTF8.self)
            #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage([row(json)], componentsV2: false) }
        }
        let longURL = String(repeating: "x", count: 513)
        #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage([row("{\"type\":2,\"style\":5,\"url\":\"\(longURL)\"}")], componentsV2: false) }
        let longAlt = String(repeating: "x", count: 1025)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try MessageComponent.validateMessage([parse("{\"type\":12,\"items\":[{\"media\":{\"url\":\"u\"},\"description\":\"\(longAlt)\"}]}")], componentsV2: true)
        }
    }

    /// Inclusive maxima pass while one-over counts fail for rows, sections, galleries, and select options.
    @Test func inclusiveRequestBoundaries() throws {
        let buttons = (0..<5).map { "{\"type\":2,\"style\":1,\"custom_id\":\"b\($0)\",\"id\":0}" }
        try MessageComponent.validateMessage([row(buttons.joined(separator: ","))], componentsV2: false)
        #expect(throws: DiscordError.validation(.invalidValue)) {
            try MessageComponent.validateMessage([row((buttons + ["{\"type\":2,\"style\":5,\"url\":\"u\"}"]).joined(separator: ","))], componentsV2: false)
        }
        let text = try parse("{\"type\":10,\"content\":\"A\"}").jsonValue()
        let accessory = try parse("{\"type\":11,\"media\":{\"url\":\"url\"},\"description\":\"\(String(repeating: "a", count: 1024))\"}").jsonValue()
        for count in [3, 4] {
            let section = try MessageComponent(jsonValue: .object(["type": .number(JSONNumber(rawValue: "9")),
                "components": .array(Array(repeating: text, count: count)), "accessory": accessory]))
            if count == 3 { try MessageComponent.validateMessage([section], componentsV2: true) }
            else { #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage([section], componentsV2: true) } }
        }
        let galleryItem: JSONValue = .object(["media": .object(["url": .string("url")])])
        for count in [10, 11] {
            let gallery = try MessageComponent(jsonValue: .object(["type": .number(JSONNumber(rawValue: "12")),
                "items": .array(Array(repeating: galleryItem, count: count))]))
            if count == 10 { try MessageComponent.validateMessage([gallery], componentsV2: true) }
            else { #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage([gallery], componentsV2: true) } }
        }
        for count in [25, 26] {
            let options: [JSONValue] = (0..<count).map { .object(["label": .string("Option"), "value": .string(String($0))]) }
            let select = try MessageComponent(jsonValue: .object(["type": .number(JSONNumber(rawValue: "3")), "custom_id": .string("select"),
                "min_values": .number(JSONNumber(rawValue: "0")), "max_values": .number(JSONNumber(rawValue: "25")), "options": .array(options)]))
            let row = try MessageComponent(jsonValue: .object(["type": .number(JSONNumber(rawValue: "1")), "components": .array([select.jsonValue()])]))
            if count == 25 { try MessageComponent.validateMessage([row], componentsV2: false) }
            else { #expect(throws: DiscordError.validation(.invalidValue)) { try MessageComponent.validateMessage([row], componentsV2: false) } }
        }
        let label = String(repeating: "a", count: 80)
        let url = String(repeating: "u", count: 512)
        try MessageComponent.validateMessage([row("{\"type\":2,\"style\":5,\"label\":\"\(label)\",\"url\":\"\(url)\"}")], componentsV2: false)
        let zeroIDText = try parse("{\"type\":10,\"id\":0,\"content\":\"A\"}")
        try MessageComponent.validateMessage([zeroIDText, zeroIDText], componentsV2: true)
    }

    /// Parses one local fixture through the public bounded component entry point.
    /// - Parameter json: Complete deterministic component JSON text.
    /// - Returns: Typed immutable component preserving complete raw fields.
    /// - Throws: Parser or projection errors, indicating fixture invalidity where success is expected.
    private func parse(_ json: String) throws -> MessageComponent { try MessageComponent(data: Data(json.utf8)) }

    /// Places one or more supplied child definitions inside an action row.
    /// - Parameter children: Comma-separated component objects; no network input is interpolated.
    /// - Returns: Typed row for legacy/V2 request validation.
    /// - Throws: Fixture syntax or projection errors.
    private func row(_ children: String) throws -> MessageComponent { try parse("{\"type\":1,\"components\":[\(children)]}") }
}
