import DiscordCore
import DiscordModels

/// Explicit webhook request-reduction helpers using caller-owned snapshots without hidden hydration or batching.
/// Equality applies only to requested wire fields. A snapshot never proves current authorization or freshness,
/// and image data is never compared as if it were an avatar hash. Callers choose when snapshot reuse is appropriate.
public enum WebhookOperations {
    /// Skips a bot-authenticated metadata PATCH when all supplied values exactly match the supplied snapshot.
    /// - Parameters:
    ///   - current: Caller-owned webhook projection; its exact ID selects the mutation target.
    ///   - request: Validated name/avatar/channel changes; empty changes need no request.
    ///   - auditReason: Optional reason validated even when all changes are already satisfied.
    /// - Returns: Nil for an exact no-op; otherwise one unsafe PATCH with normal bot admission and invalidation.
    /// - Throws: Body/descriptor/audit errors. No network, cache, background tasks or implicit retries occur.
    public static func modifyIfChanged(current: Webhook, request: WebhookModify,
                                       auditReason: String? = nil) throws -> Endpoint<Webhook>? {
        let endpoint = try WebhookEndpoints.modify(webhookID: current.id, request: request, auditReason: auditReason)
        return webhookChangesMatch(current: current, request: request) ? nil : endpoint
    }

    /// Skips a token-authenticated metadata PATCH when requested values exactly match a caller-supplied snapshot.
    /// - Parameters:
    ///   - current: Known webhook snapshot, whose ID is paired with the supplied token.
    ///   - token: Secret matching the dedicated RESTClient credential; does not establish ownership locally.
    ///   - request: Validated name/avatar changes; channel movement remains forbidden even when it would be a no-op.
    /// - Returns: Nil when every requested key matches; otherwise one unsafe token PATCH without Authorization.
    /// - Throws: Illegal channel-change/body/descriptor errors before comparison; execution remains caller-controlled.
    public static func modifyWithTokenIfChanged(current: Webhook, token: WebhookToken,
                                                request: WebhookModify) throws -> Endpoint<Webhook>? {
        let endpoint = try WebhookEndpoints.modifyWithToken(webhookID: current.id, token: token, request: request)
        return webhookChangesMatch(current: current, request: request) ? nil : endpoint
    }
}

/// Compares only explicitly requested metadata keys against the snapshot's exact raw values.
/// - Parameters:
///   - current: Caller-owned projection; explicit unsafe access is contained synchronously and never logged.
///   - request: Immutable validated PATCH fields, including explicit null avatar removal.
/// - Returns: True for empty changes or exact key/value matches; absent snapshot keys never match a supplied value.
private func webhookChangesMatch(current: Webhook, request: WebhookModify) -> Bool {
    guard case .object(let desired) = request.jsonValue() else { return false }
    if case .string = desired["avatar"] { return false }
    return current.withUnsafeFields { fields in desired.allSatisfy { fields[$0.key] == $0.value } }
}
