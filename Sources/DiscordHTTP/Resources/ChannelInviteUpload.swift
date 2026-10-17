import DiscordCore
import DiscordModels
import Foundation

/// Validates optional acceptance-list CSV and builds a bounded replayable invite body.
/// - Parameters:
///   - request: Non-file invite parameters, independently range/type/target validated.
///   - csv: Optional UTF-8 single-column exact UInt64 snowflake lines. CRLF/LF and one trailing newline
///     are accepted; empty records, headers, commas, quotes, BOMs and other whitespace are rejected.
///     Duplicate user lines are preserved; Discord ignores them. No undocumented row-count cap is inferred.
///   - maximumBytes: Positive local complete-body cap, at most 8 MiB; includes all framing.
/// - Returns: JSON even for `{}`, or multipart with payload_json and target_users_file. Materialized
///   bounded bytes are replayable without file handles or producer ownership.
/// - Throws: Safe validation errors for byte limits, malformed CSV or conflict with targetUserIDs;
///   request validation and multipart bounds errors propagate. No I/O or suspension occurs.
func channelInviteBody(_ request: ChannelInviteCreate, csv: Data?, maximumBytes: Int) throws -> RequestBody {
    guard (1...8_388_608).contains(maximumBytes) else { throw DiscordError.validation(.invalidValue) }
    let payload = try request.jsonValue().serialized(limits: JSONLimits(maximumBytes: maximumBytes))
    guard let csv else { return try RequestBody(bytes: payload, contentType: "application/json", maximumBytes: maximumBytes) }
    guard request.targetUserIDs == nil, !csv.isEmpty else { throw DiscordError.validation(.invalidValue) }
    guard csv.count <= maximumBytes else { throw DiscordError.validation(.limitExceeded) }
    _ = try inviteCSVRows(csv, hasHeader: false, maximumUsers: nil, response: false)
    // All request strings are decimal IDs and CSV is numeric-only; fixed field names cannot
    // contain this boundary. Multipart still independently checks every part for collisions.
    let boundary = "DiscordKitInvite"
    return try RequestBody.multipart([
        MultipartPart(name: "payload_json", contentType: "application/json", bytes: payload),
        MultipartPart(name: "target_users_file", filename: "users.csv", contentType: "text/csv", bytes: csv),
    ], boundary: boundary, maximumBytes: maximumBytes)
}
