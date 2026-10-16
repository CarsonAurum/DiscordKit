import Foundation
import Testing
@testable import DiscordCore

/// Diagnostic filtering and typed failures are tested as deterministic pure values.
@Suite struct RedactionCapabilityTests {
    /// Exercises raw, overlapping, JSON escaped, form and mixed/nested percent
    /// encodings, including a malformed escape alongside a valid encoded secret.
    /// - Parameter text: Diagnostic representation containing the registered secret.
    @Test(arguments: [
        "Authorization: abc/DEF+ghi", "abc%2FDEF%2bghi", "abc%252fDEF%252Bghi",
        "%61%62%63%2f%44%45%46%2B%67%68%69", "bad%zz/abc%2FDEF+ghi",
        #"{\"token\":\"abc\/DEF+ghi\"}"#,
    ])
    func redactsKnownEncodings(text: String) {
        let redactor = DiagnosticRedactor(secrets: ["abc", "abc/DEF+ghi", "", "abc/DEF+ghi"])
        let safe = redactor.redact(text)
        #expect(!safe.contains("abc"))
        #expect(!safe.contains("DEF"))
        #expect(!safe.contains("ghi"))
        #expect(safe.contains("[REDACTED]"))
        #expect(redactor.redact(text) == safe)
    }

    /// Covers empty inputs, UTF-8 triplets, literal malformed escapes, common JSON
    /// string escaping, form spaces and reflection of the secret registry itself.
    @Test func redactionEdgeCases() {
        let redactor = DiagnosticRedactor(secrets: ["é!", "a b", "quoted\"\\value\n\t\r"])
        #expect(redactor.redact("%c3%a9%21") == "[REDACTED]")
        #expect(redactor.redact("a+b") == "[REDACTED]")
        #expect(redactor.redact(#"quoted\"\\value\n\t\r"#) == "[REDACTED]")
        #expect(redactor.redact("") == "")
        #expect(DiagnosticRedactor().redact("bad%x/%2/%G0/%0G/end%") == "bad%x/%2/%G0/%0G/end%")
        #expect(DiagnosticRedactor(secrets: [""]).redact("plain") == "plain")
        #expect(DiagnosticRedactor().redact("%FF") == "�")
        #expect(String(describing: redactor) == "DiagnosticRedactor([REDACTED])")
        #expect(String(reflecting: redactor) == redactor.description)
        #expect(redactor.customMirror.children.count == 1)
        var output = ""
        dump(redactor, to: &output)
        #expect(!output.contains("quoted"))
        #expect(!output.contains("a b"))
    }

    /// Decodes exactly 32 nested layers and suppresses the complete diagnostic above that bound.
    ///
    /// The malformed suffix remains visible at the supported boundary, while
    /// unresolved valid escapes never return partially decoded secret fragments.
    /// - Parameter depth: Percent-decoding passes needed to reveal the sentinel.
    @Test(arguments: [1, 31, 32, 33, 1_000])
    func percentNestingIsBounded(depth: Int) {
        let encoded = "%" + String(repeating: "25", count: depth - 1) + "53ENTINEL"
        let text = "prefix/" + encoded + "/suffix%zz"
        let redactor = DiagnosticRedactor(secrets: ["SENTINEL"])
        if depth <= 32 {
            #expect(DiagnosticRedactor().redact(text) == "prefix/SENTINEL/suffix%zz")
            #expect(redactor.redact(text) == "prefix/[REDACTED]/suffix%zz")
            #expect(redactor.path("/channels/" + encoded) == "/channels/[REDACTED]")
        } else {
            #expect(DiagnosticRedactor().redact(text) == "[REDACTED]")
            #expect(redactor.redact(text) == "[REDACTED]")
            #expect(redactor.path("/channels/" + encoded + "/suffix") == "[REDACTED]")
            #expect(redactor.headers(["Accept": text]) == ["Accept": "[REDACTED]"])
        }
    }

    /// An unresolved secret registration suppresses all nonempty diagnostic text to avoid incomplete matching.
    ///
    /// Supported registrations match their fully decoded spelling. Unsupported
    /// registrations suppress names, values and paths as well as the raw secret,
    /// while empty diagnostics and body suppression retain their ordinary behavior.
    /// - Parameter depth: Secret-registration encoding depth at and above the supported boundary.
    @Test(arguments: [32, 33, 1_000])
    func nestedSecretRegistrationFailsClosed(depth: Int) {
        let encoded = "%" + String(repeating: "25", count: depth - 1) + "53ENTINEL"
        let redactor = DiagnosticRedactor(secrets: [encoded])
        if depth == 32 {
            #expect(redactor.redact("prefix SENTINEL suffix") == "prefix [REDACTED] suffix")
            #expect(redactor.path("/channels/SENTINEL") == "/channels/[REDACTED]")
            #expect(redactor.headers(["Accept": "SENTINEL"]) == ["Accept": "[REDACTED]"])
        } else {
            #expect(redactor.redact("prefix SENTINEL suffix") == "[REDACTED]")
            #expect(redactor.redact("benign") == "[REDACTED]")
            #expect(redactor.path("/channels/SENTINEL") == "[REDACTED]")
            #expect(redactor.path("/channels/SENTINEL?token=other") == "[REDACTED]")
            #expect(redactor.headers(["Accept": "SENTINEL"]) == ["[REDACTED]": "[REDACTED]"])
        }
        #expect(redactor.redact(encoded) == "[REDACTED]")
        #expect(redactor.redact("") == "")
        #expect(redactor.path("") == "")
        #expect(redactor.headers([:]).isEmpty)
        #expect(redactor.body("SENTINEL") == "[REDACTED BODY]")
    }

    /// Checks case-insensitive sensitive headers, registered secrets in arbitrary
    /// values/names, redacted-name collisions and preservation of benign metadata.
    @Test func structuredHeadersConcealSecrets() {
        let redactor = DiagnosticRedactor(secrets: ["SENTINEL", "ALIAS"])
        let safe = redactor.headers([
            "Authorization": "unregistered", "PROXY-AUTHORIZATION": "unregistered",
            "Cookie": "unregistered", "set-cookie": "unregistered", "X_API_KEY": "unregistered",
            "X-Custom-Token": "unregistered", "client-secret": "unregistered",
            "Accept": "application/json", "X-Diagnostic": "prefix SENTINEL suffix",
            "SENTINEL": "one", "ALIAS": "two",
        ])
        for name in ["Authorization", "PROXY-AUTHORIZATION", "Cookie", "set-cookie", "X_API_KEY", "X-Custom-Token", "client-secret"] {
            #expect(safe[name] == "[REDACTED]")
        }
        #expect(safe["Accept"] == "application/json")
        #expect(safe["X-Diagnostic"] == "prefix [REDACTED] suffix")
        #expect(safe["[REDACTED]"] == "[REDACTED]")
        #expect(redactor.headers([:]).isEmpty)
    }

    /// Ensures known token-bearing routes, all query/fragment values and complete
    /// bodies are suppressed even without registered secrets.
    @Test func structuredPathsAndBodiesConcealSecrets() {
        let redactor = DiagnosticRedactor(secrets: ["SENTINEL"])
        #expect(redactor.path("/api/v10/webhooks/123/unregistered/messages/@original") == "/api/v10/webhooks/123/[REDACTED]/messages/@original")
        #expect(redactor.path("/interactions/123/unregistered/callback") == "/interactions/123/[REDACTED]/callback")
        #expect(redactor.path("/webhooks/1/abc%2Fdef/messages/@original") == "/webhooks/1/[REDACTED]/messages/@original")
        #expect(redactor.path("/interactions/1/abc%252fdef/callback") == "/interactions/1/[REDACTED]/callback")
        #expect(redactor.path("/web%68ooks/1/abc%2fdef") == "/webhooks/1/[REDACTED]")
        #expect(DiagnosticRedactor(secrets: ["abc/def"]).path("/webhooks/1/abc/def") == "/webhooks/1/[REDACTED]")
        #expect(redactor.path("https://discord.com/api/v10/webhooks/1/unregistered?signature=other#fragment") == "https://discord.com/api/v10/webhooks/1/[REDACTED]?[REDACTED]")
        #expect(redactor.path("/channels/1?unknown=unregistered") == "/channels/1?[REDACTED]")
        #expect(redactor.path("/channels/1#unregistered") == "/channels/1?[REDACTED]")
        #expect(redactor.path("/SENTINEL") == "/[REDACTED]")
        #expect(redactor.path("/webhooks/1") == "/webhooks/1")
        #expect(redactor.path("") == "")
        #expect(redactor.body("SENTINEL or unknown secret") == "[REDACTED BODY]")
        #expect(redactor.body("") == "")
    }

    /// Requires capability availability and preserves every specific unavailable
    /// reason rather than silently succeeding or collapsing host limitations.
    /// - Parameter reason: Each declared reason for unavailable functionality.
    /// - Throws: Unexpected Codable or availability errors.
    @Test(arguments: CapabilityUnavailableReason.allCases)
    func capabilityResults(reason: CapabilityUnavailableReason) throws {
        try CapabilityAvailability.available.requireAvailable()
        let unavailable = CapabilityAvailability.unavailable(reason)
        #expect(throws: DiscordError.capabilityUnavailable(reason)) { try unavailable.requireAvailable() }
        #expect(try JSONDecoder().decode(CapabilityAvailability.self, from: JSONEncoder().encode(unavailable)) == unavailable)
        #expect(try JSONDecoder().decode(CapabilityUnavailableReason.self, from: JSONEncoder().encode(reason)) == reason)
    }

    /// Preserves explicit capability names through wire coding without performing
    /// a platform probe or implying any implementation is available.
    /// - Parameter capability: Each declared capability descriptor.
    /// - Throws: Unexpected coding failures.
    @Test(arguments: PlatformCapability.allCases)
    func capabilityNames(capability: PlatformCapability) throws {
        #expect(try JSONDecoder().decode(PlatformCapability.self, from: JSONEncoder().encode(capability)) == capability)
        #expect(!capability.rawValue.isEmpty)
    }

    /// Distinguishes validation, API, cancellation, transport and uncertain mutation
    /// outcomes while retaining future numeric API codes in safe diagnostic text.
    @Test func typedErrorsHaveSafeDescriptions() {
        let errors: [DiscordError] = [
            .api(status: 429, code: 99_999_999), .api(status: 500, code: nil),
            .validation(.emptyCredential), .validation(.invalidCredential), .validation(.invalidValue),
            .validation(.missingValue), .validation(.limitExceeded),
            .transport(.connectionFailed), .transport(.disconnected), .transport(.deadlineExceeded),
            .transport(.invalidResponse), .transport(.limitExceeded), .cancelled,
            .unknownMutationOutcome(.cancelledAfterSubmission),
            .unknownMutationOutcome(.connectionLostAfterSubmission),
            .unknownMutationOutcome(.deadlineAfterSubmission), .capabilityUnavailable(.restrictedByHost),
        ]
        #expect(Set(errors.map(\.description)).count == errors.count)
        #expect(errors[0].description.contains("99999999"))
        #expect(errors[1].description.contains("unknown"))
        #expect(DiscordError.cancelled != .unknownMutationOutcome(.cancelledAfterSubmission))
        for error in errors {
            #expect(!error.description.isEmpty)
            #expect(error.debugDescription == error.description)
            #expect(String(reflecting: error) == error.description)
            #expect(error.customMirror.children.count == 1)
        }
    }
}
