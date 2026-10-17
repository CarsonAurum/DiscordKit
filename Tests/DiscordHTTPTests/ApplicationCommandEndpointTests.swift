import DiscordCore
import DiscordModels
import DiscordTransport
import Foundation
import Testing
@testable import DiscordHTTP

/// Exact wire contracts for all 15 currently available global/guild command and permission operations.
@Suite struct ApplicationCommandEndpointTests {
    /// Every descriptor retains exact explicit version, scope, success, auth, body, cache and replay policy.
    /// - Throws: Unexpected valid catalog/descriptor/fixture failures fail this test.
    @Test func completeCatalog() throws {
        let catalog = try Self.catalog()
        #expect(catalog.count == 15)
        let expectedMethods = ["GET", "POST", "GET", "PATCH", "DELETE", "PUT", "GET", "POST", "GET", "PATCH", "DELETE", "PUT", "GET", "GET", "PUT"]
        for (index, item) in catalog.enumerated() {
            let (endpoint, bytes) = item
            #expect(endpoint.method == expectedMethods[index])
            #expect(endpoint.majorParameter == (index >= 6 ? "3" : nil))
            #expect(endpoint.authentication == (index == 14 ? .bearer : .botOrBearer))
            #expect(endpoint.retrySafety == (endpoint.method == "GET" ? .safe : .unsafe))
            #expect((endpoint.readPolicy != nil) == (endpoint.method == "GET"))
            #expect(endpoint.invalidates.isEmpty == (endpoint.method == "GET"))
            #expect(endpoint.auditReason == nil && endpoint.usesGlobalLimit)
            #expect(try endpoint.decode(bytes) == bytes)
            let request = try endpoint.makeRequest(credential: .bearer(try BearerToken("synthetic")), userAgent: "test")
            #expect(request.url.absoluteString.hasPrefix("https://discord.com/api/v10/applications/18446744073709551615/"))
            #expect(request.url.path == "/api/v10/" + endpoint.path.joined(separator: "/"))
            #expect(request.headers.contains { $0.name == "Authorization" && $0.value == "Bearer synthetic" })
            #expect(throws: DiscordError.validation(.missingValue)) { try endpoint.makeRequest(credential: .none, userAgent: "test") }
            if endpoint.method == "DELETE" {
                #expect(endpoint.successStatuses == [204])
                #expect(throws: DiscordError.transport(.invalidResponse)) { try endpoint.decode(Data("{}".utf8)) }
            } else if endpoint.method == "POST" { #expect(endpoint.successStatuses == [200, 201]) }
            else { #expect(endpoint.successStatuses == [200]) }
            if index == 5 || index == 11 {
                #expect(endpoint.bulk?.maximumItems == (index == 5 ? 131 : 130))
                #expect(endpoint.bulk?.preservesOrder == false && endpoint.bulk?.permitsPartialResults == false)
            } else { #expect(endpoint.bulk == nil) }
            #expect(endpoint.query == ((index == 0 || index == 6) ? [.init(name: "with_localizations", value: "true")] : []))
        }
        #expect(catalog[12].0.path.suffix(2) == ["commands", "permissions"])
        #expect(catalog[13].0.path.suffix(3) == ["commands", "1", "permissions"])
        #expect(catalog[14].0.path.suffix(3) == ["commands", "1", "permissions"])
        #expect(catalog.filter { $0.0.path.suffix(2) == ["commands", "permissions"] && $0.0.method == "PUT" }.isEmpty)
        #expect(throws: DiscordError.validation(.missingValue)) { try catalog[14].0.makeRequest(credential: .bot(BotToken("synthetic")), userAgent: "test") }
        for index in 0..<14 {
            #expect(try catalog[index].0.makeRequest(credential: .bot(BotToken("synthetic")), userAgent: "test").headers.contains { $0.value == "Bot synthetic" })
        }
        #expect(try ApplicationCommandEndpoints.list(applicationID: .init(rawValue: 2)).decode(Data("[]".utf8)).isEmpty)
        #expect(try ApplicationCommandEndpoints.listPermissions(applicationID: .init(rawValue: 2), guildID: .init(rawValue: 3)).decode(Data("[]".utf8)).isEmpty)
    }

    /// Scope-specific settings, strict nullable fields and invalid TTLs fail before I/O, while explicit bulk fields remain available.
    /// - Throws: Unexpected valid descriptor construction failures fail this test.
    @Test func scopePoliciesAndReadChoices() throws {
        let app = ApplicationID(rawValue: 2), guild = GuildID(rawValue: 3), command = ApplicationCommandID(rawValue: 1)
        let policy = ReadPolicy(coalescing: false, timeToLive: .seconds(4), tags: ["caller"])
        let read = try ApplicationCommandEndpoints.get(applicationID: app, commandID: command, guildID: guild, readPolicy: policy)
        #expect(read.readPolicy?.tags == ["caller", "application-commands:2", "application-command-permissions:2"])
        #expect(read.readPolicy?.coalescing == false && read.readPolicy?.timeToLive == .seconds(4))
        #expect(try ApplicationCommandEndpoints.get(applicationID: app, commandID: command, readPolicy: nil).readPolicy == nil)
        #expect(try ApplicationCommandEndpoints.list(applicationID: app, withLocalizations: false, readPolicy: nil).query == [.init(name: "with_localizations", value: "false")])
        for ttl in [Duration.zero, .seconds(-1)] {
            #expect(throws: (any Error).self) { try ApplicationCommandEndpoints.list(applicationID: app, readPolicy: ReadPolicy(timeToLive: ttl)) }
            #expect(throws: (any Error).self) { try ApplicationCommandEndpoints.permissions(applicationID: app, guildID: guild, commandID: command, readPolicy: ReadPolicy(timeToLive: ttl)) }
        }
        let globalOnly = try ApplicationCommandCreate(name: "command", description: "d", dmPermission: .null,
            integrationTypes: [.guildInstall], contexts: [.guild])
        #expect(throws: (any Error).self) { try ApplicationCommandEndpoints.create(applicationID: app, guildID: guild, request: globalOnly) }
        #expect(throws: (any Error).self) { try ApplicationCommandEndpoints.modify(applicationID: app, commandID: command,
            guildID: guild, request: ApplicationCommandModify(contexts: [.guild])) }
        let bulk = try BulkApplicationCommands(commands: [ApplicationCommandRegistration(command: globalOnly)])
        #expect(try ApplicationCommandEndpoints.bulkOverwrite(applicationID: app, guildID: guild, request: bulk).body != nil)
        let entry = try ApplicationCommandCreate(name: "Launch", type: .primaryEntryPoint, description: "Activity", handler: .discordLaunchActivity)
        #expect(throws: (any Error).self) { try ApplicationCommandEndpoints.create(applicationID: app, guildID: guild, request: entry) }
        #expect(throws: (any Error).self) { try ApplicationCommandEndpoints.modify(applicationID: app, commandID: command, guildID: guild, request: ApplicationCommandModify(type: .primaryEntryPoint)) }
        #expect(throws: (any Error).self) { try ApplicationCommandEndpoints.bulkOverwrite(applicationID: app, guildID: guild,
            request: BulkApplicationCommands(commands: [ApplicationCommandRegistration(command: entry)])) }
        #expect(try ApplicationCommandEndpoints.create(applicationID: app, request: entry).successStatuses == [200, 201])
    }

    /// Snapshot reconciliation proves exact no-ops, compares localization/defaults, and never treats an empty desired catalog as empty work.
    /// - Throws: Unexpected valid fixture/request failures fail this test; mismatched scope and identities are asserted.
    @Test func boundedSnapshotReconciliation() throws {
        let app = ApplicationID(rawValue: UInt64.max), guild = GuildID(rawValue: 3)
        let current = try ApplicationCommand(data: Data(Self.guildJSON.utf8))
        let desired = try ApplicationCommandCreate(name: "command", description: "description")
        let replacement = try BulkApplicationCommands(commands: [ApplicationCommandRegistration(command: desired)])
        #expect(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, guildID: guild, current: [current], request: replacement) == nil)
        let withID = try BulkApplicationCommands(commands: [ApplicationCommandRegistration(command: desired, id: current.id)])
        #expect(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, guildID: guild, current: [current], request: withID) == nil)
        #expect(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, current: [], request: BulkApplicationCommands(commands: [])) == nil)
        #expect(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, guildID: guild, current: [current], request: BulkApplicationCommands(commands: []))?.method == "PUT")
        let changed = try BulkApplicationCommands(commands: [ApplicationCommandRegistration(command: ApplicationCommandCreate(name: "changed", description: "description"))])
        #expect(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, guildID: guild, current: [current], request: changed)?.method == "PUT")
        #expect(throws: (any Error).self) { try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: .init(rawValue: 2), guildID: guild, current: [current], request: replacement) }
        #expect(throws: (any Error).self) { try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, current: [current], request: replacement) }
        #expect(throws: (any Error).self) { try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, guildID: .init(rawValue: 4), current: [current], request: replacement) }
        #expect(throws: (any Error).self) { try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, guildID: guild, current: [current, current], request: replacement) }
        var duplicate = current.rawFields; duplicate["id"] = .string("2")
        let duplicateName = try ApplicationCommand(data: JSONValue.object(duplicate).serialized())
        #expect(throws: (any Error).self) { try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, guildID: guild, current: [current, duplicateName], request: replacement) }
        let global = try ApplicationCommand(data: Data(Self.globalJSON.utf8))
        #expect(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, current: [global], request: replacement) != nil)
        let explicit = try BulkApplicationCommands(commands: [ApplicationCommandRegistration(command: ApplicationCommandCreate(name: "command", description: "description", integrationTypes: [.guildInstall], contexts: [.guild]))])
        var complete = global.rawFields
        complete["integration_types"] = .array([.number(try JSONNumber(rawValue: "0"))]); complete["contexts"] = .array([.number(try JSONNumber(rawValue: "0"))])
        let completeGlobal = try ApplicationCommand(data: JSONValue.object(complete).serialized())
        #expect(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, current: [completeGlobal], request: explicit) == nil)
        var localized = current.rawFields; localized.removeValue(forKey: "name_localizations"); localized["name_localized"] = .string("translated")
        #expect(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, guildID: guild,
            current: [ApplicationCommand(data: JSONValue.object(localized).serialized())], request: replacement) != nil)
        let wrongID = try BulkApplicationCommands(commands: [ApplicationCommandRegistration(command: desired, id: .init(rawValue: 999))])
        #expect(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, guildID: guild, current: [current], request: wrongID) != nil)
    }

    /// Nested localized response-only fields do not cause registration writes, while unknown option fields remain conservative.
    /// Array order remains meaningful within a command, and catalog order itself is matched by stable ID or name/type.
    /// - Throws: Unexpected valid payload/fixture construction failures fail this test.
    @Test func nestedSnapshotComparisonAndCatalogOrder() throws {
        let app = ApplicationID(rawValue: UInt64.max), guild = GuildID(rawValue: 3)
        let first = try ApplicationCommandOptionCreate(type: .string, name: "first", description: "first", required: true)
        let second = try ApplicationCommandOptionCreate(type: .attachment, name: "second", description: "second", fileTypes: ["image"])
        let create = try ApplicationCommandCreate(name: "command", description: "description", options: [first, second])
        let request = try BulkApplicationCommands(commands: [ApplicationCommandRegistration(command: create)])
        var raw = try ApplicationCommand(data: Data(Self.guildJSON.utf8)).rawFields
        guard case .object(var firstRaw) = first.jsonValue() else { Issue.record("fixture"); return }
        firstRaw["name_localized"] = .string("localized first")
        firstRaw["description_localized"] = .string("localized description")
        raw["options"] = .array([.object(firstRaw), second.jsonValue()])
        let current = try ApplicationCommand(data: JSONValue.object(raw).serialized())
        #expect(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, guildID: guild, current: [current], request: request) == nil)
        firstRaw["future"] = .bool(true)
        raw["options"] = .array([.object(firstRaw), second.jsonValue()])
        let future = try ApplicationCommand(data: JSONValue.object(raw).serialized())
        #expect(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, guildID: guild, current: [future], request: request) != nil)
        raw["options"] = .array([second.jsonValue(), first.jsonValue()])
        let reordered = try ApplicationCommand(data: JSONValue.object(raw).serialized())
        #expect(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, guildID: guild, current: [reordered], request: request) != nil)
        var otherRaw = current.rawFields
        otherRaw["id"] = .string("2"); otherRaw["name"] = .string("other")
        let other = try ApplicationCommand(data: JSONValue.object(otherRaw).serialized())
        let two = try BulkApplicationCommands(commands: [ApplicationCommandRegistration(command: create),
            ApplicationCommandRegistration(command: ApplicationCommandCreate(name: "other", description: "description", options: [first, second]))])
        #expect(try ApplicationCommandOperations.bulkOverwriteIfChanged(applicationID: app, guildID: guild, current: [other, current], request: two) == nil)
    }

    /// Produces every available operation with its original typed decoder and independent complete response fixture.
    /// - Returns: Stable global six, guild six, permissions list/get/modify catalog order.
    /// - Throws: Fixture/request/descriptor errors if a documented contract is accidentally broken.
    static func catalog() throws -> [(Endpoint<Data>, Data)] {
        let app = ApplicationID(rawValue: UInt64.max), guild = GuildID(rawValue: 3), command = ApplicationCommandID(rawValue: 1)
        let body = try ApplicationCommandCreate(name: "created", description: "description")
        let edit = try ApplicationCommandModify(name: .value("changed"))
        let bulk = try BulkApplicationCommands(commands: [ApplicationCommandRegistration(command: body, id: command)])
        var result: [(Endpoint<Data>, Data)] = []
        for scope: GuildID? in [nil, guild] {
            let single = Data((scope == nil ? globalJSON : guildJSON).utf8)
            let list = Data(("[" + (scope == nil ? globalJSON : guildJSON) + "]").utf8)
            result += [
                (try erase(ApplicationCommandEndpoints.list(applicationID: app, guildID: scope, withLocalizations: true)), list),
                (try erase(ApplicationCommandEndpoints.create(applicationID: app, guildID: scope, request: body)), single),
                (try erase(ApplicationCommandEndpoints.get(applicationID: app, commandID: command, guildID: scope)), single),
                (try erase(ApplicationCommandEndpoints.modify(applicationID: app, commandID: command, guildID: scope, request: edit)), single),
                (try erase(ApplicationCommandEndpoints.delete(applicationID: app, commandID: command, guildID: scope)), Data()),
                (try erase(ApplicationCommandEndpoints.bulkOverwrite(applicationID: app, guildID: scope, request: bulk)), list)]
        }
        result += [
            (try erase(ApplicationCommandEndpoints.listPermissions(applicationID: app, guildID: guild)), Data(("[" + permissionsJSON + "]").utf8)),
            (try erase(ApplicationCommandEndpoints.permissions(applicationID: app, guildID: guild, commandID: command)), Data(permissionsJSON.utf8)),
            (try erase(ApplicationCommandEndpoints.modifyPermissions(applicationID: app, guildID: guild, commandID: command,
                request: ApplicationCommandPermissionsModify(permissions: [ApplicationCommandPermissionOverwrite(id: .init(rawValue: UInt64.max), type: .user, permission: false)]))), Data(permissionsJSON.utf8))]
        return result
    }

    /// Preserves every production descriptor policy and validates the original typed response before returning its bytes.
    /// - Parameter endpoint: Typed production command/permission descriptor.
    /// - Returns: Equivalent finite Data descriptor retaining original schema validation, without I/O or mutation.
    /// - Throws: Descriptor errors if the policy cannot be represented unchanged.
    static func erase<T: Sendable>(_ endpoint: Endpoint<T>) throws -> Endpoint<Data> {
        try Endpoint(method: endpoint.method, path: endpoint.path, route: endpoint.route, query: endpoint.query,
            authentication: endpoint.authentication, successStatuses: endpoint.successStatuses,
            majorParameter: endpoint.majorParameter, usesGlobalLimit: endpoint.usesGlobalLimit,
            auditReason: endpoint.auditReason, body: endpoint.body, headers: endpoint.headers,
            retrySafety: endpoint.retrySafety, readPolicy: endpoint.readPolicy, invalidates: endpoint.invalidates,
            bulk: endpoint.bulk, decode: { _ = try endpoint.decode($0); return $0 })
    }

    /// Complete independently written global snapshot with explicit full nullable localization dictionaries.
    static let globalJSON = #"{"id":"1","application_id":"18446744073709551615","version":"2","type":1,"name":"command","description":"description","default_member_permissions":null,"name_localizations":null,"description_localizations":null}"#
    /// Complete independently written guild snapshot with all required fields and exact guild scope.
    static let guildJSON = #"{"id":"1","application_id":"18446744073709551615","guild_id":"3","version":"2","type":1,"name":"command","description":"description","default_member_permissions":null,"name_localizations":null,"description_localizations":null}"#
    /// Complete independently written permission envelope, including a large target and explicit deny.
    static let permissionsJSON = #"{"id":"1","application_id":"18446744073709551615","guild_id":"3","permissions":[{"id":"18446744073709551615","type":2,"permission":false}]}"#
}
