import DiscordCore
import Foundation

/// Supported GitHub delivery events for the compatibility adapter; event payloads remain GitHub-owned.
public enum WebhookGitHubEvent: String, Sendable, CaseIterable {
    case commitComment = "commit_comment"
    case create = "create"
    case delete = "delete"
    case fork = "fork"
    case issueComment = "issue_comment"
    case issues = "issues"
    case member = "member"
    case `public` = "public"
    case pullRequest = "pull_request"
    case pullRequestReview = "pull_request_review"
    case pullRequestReviewComment = "pull_request_review_comment"
    case push = "push"
    case release = "release"
    case watch = "watch"
    case checkRun = "check_run"
    case checkSuite = "check_suite"
    case discussion = "discussion"
    case discussionComment = "discussion_comment"
}

/// Validated API v10 GithubAuthor compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubAuthor: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - username: Omitted by default; null permitted; wire username as String. Maximum 152133 Unicode scalars.
    ///   - name: Required wire name as String. Maximum 152133 Unicode scalars.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(username: Field<String> = .absent,
                name: String) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(username, name: "username", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        result["name"] = try guildRequestText(name, length: 0...152133)
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubCheckApp compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubCheckApp: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - name: Required wire name as String. Maximum 152133 Unicode scalars.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(name: String) throws {
        var result: [String: JSONValue] = [:]
        result["name"] = try guildRequestText(name, length: 0...152133)
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubCheckPullRequest compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubCheckPullRequest: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - number: Required wire number as Int64.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(number: Int64) throws {
        var result: [String: JSONValue] = [:]
        result["number"] = try guildRequestNumber(number)
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubCheckRun compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubCheckRun: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - conclusion: Omitted by default; null permitted; wire conclusion as String. Maximum 152133 Unicode scalars.
    ///   - name: Required wire name as String. Maximum 152133 Unicode scalars.
    ///   - htmlURL: Required wire html_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - checkSuite: Required wire check_suite as WebhookGitHubCheckSuite.
    ///   - detailsURL: Omitted by default; null permitted; wire details_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - output: Omitted by default; null permitted; wire output as WebhookGitHubCheckRunOutput.
    ///   - pullRequests: Omitted by default; null permitted; wire pull_requests as [WebhookGitHubCheckPullRequest]. At most 1521 ordered items.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(conclusion: Field<String> = .absent,
                name: String,
                htmlURL: String,
                checkSuite: WebhookGitHubCheckSuite,
                detailsURL: Field<String> = .absent,
                output: Field<WebhookGitHubCheckRunOutput> = .absent,
                pullRequests: Field<[WebhookGitHubCheckPullRequest]> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(conclusion, name: "conclusion", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        result["name"] = try guildRequestText(name, length: 0...152133)
        result["html_url"] = try webhookCompatibilityURL(htmlURL)
        result["check_suite"] = checkSuite.jsonValue()
        try guildRequestField(detailsURL, name: "details_url", nullable: true, into: &result) { try webhookCompatibilityURL($0) }
        try guildRequestField(output, name: "output", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(pullRequests, name: "pull_requests", nullable: true, into: &result) { try webhookCompatibilityArray($0, maximum: 1521) }
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubCheckRunOutput compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubCheckRunOutput: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - title: Omitted by default; null permitted; wire title as String. Maximum 152133 Unicode scalars.
    ///   - summary: Omitted by default; null permitted; wire summary as String. Maximum 152133 Unicode scalars.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(title: Field<String> = .absent,
                summary: Field<String> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(title, name: "title", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(summary, name: "summary", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubCheckSuite compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubCheckSuite: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - conclusion: Omitted by default; null permitted; wire conclusion as String. Maximum 152133 Unicode scalars.
    ///   - headBranch: Omitted by default; null permitted; wire head_branch as String. Maximum 152133 Unicode scalars.
    ///   - headSha: Required wire head_sha as String. Maximum 152133 Unicode scalars.
    ///   - pullRequests: Omitted by default; null permitted; wire pull_requests as [WebhookGitHubCheckPullRequest]. At most 1521 ordered items.
    ///   - app: Required wire app as WebhookGitHubCheckApp.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(conclusion: Field<String> = .absent,
                headBranch: Field<String> = .absent,
                headSha: String,
                pullRequests: Field<[WebhookGitHubCheckPullRequest]> = .absent,
                app: WebhookGitHubCheckApp) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(conclusion, name: "conclusion", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(headBranch, name: "head_branch", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        result["head_sha"] = try guildRequestText(headSha, length: 0...152133)
        try guildRequestField(pullRequests, name: "pull_requests", nullable: true, into: &result) { try webhookCompatibilityArray($0, maximum: 1521) }
        result["app"] = app.jsonValue()
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubComment compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubComment: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - id: Required wire id as Int64.
    ///   - htmlURL: Required wire html_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - user: Required wire user as WebhookGitHubUser.
    ///   - commitId: Omitted by default; null permitted; wire commit_id as String. Maximum 152133 Unicode scalars.
    ///   - body: Required wire body as String. Maximum 152133 Unicode scalars.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(id: Int64,
                htmlURL: String,
                user: WebhookGitHubUser,
                commitId: Field<String> = .absent,
                body: String) throws {
        var result: [String: JSONValue] = [:]
        result["id"] = try guildRequestNumber(id)
        result["html_url"] = try webhookCompatibilityURL(htmlURL)
        result["user"] = user.jsonValue()
        try guildRequestField(commitId, name: "commit_id", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        result["body"] = try guildRequestText(body, length: 0...152133)
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubCommit compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubCommit: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - id: Required wire id as String. Maximum 152133 Unicode scalars.
    ///   - url: Required wire url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - message: Required wire message as String. Maximum 152133 Unicode scalars.
    ///   - author: Required wire author as WebhookGitHubAuthor.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(id: String,
                url: String,
                message: String,
                author: WebhookGitHubAuthor) throws {
        var result: [String: JSONValue] = [:]
        result["id"] = try guildRequestText(id, length: 0...152133)
        result["url"] = try webhookCompatibilityURL(url)
        result["message"] = try guildRequestText(message, length: 0...152133)
        result["author"] = author.jsonValue()
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubDiscussion compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubDiscussion: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - title: Required wire title as String. Maximum 152133 Unicode scalars.
    ///   - number: Required wire number as Int64.
    ///   - htmlURL: Required wire html_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - answerHTMLURL: Omitted by default; null permitted; wire answer_html_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - body: Omitted by default; null permitted; wire body as String. Maximum 152133 Unicode scalars.
    ///   - user: Required wire user as WebhookGitHubUser.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(title: String,
                number: Int64,
                htmlURL: String,
                answerHTMLURL: Field<String> = .absent,
                body: Field<String> = .absent,
                user: WebhookGitHubUser) throws {
        var result: [String: JSONValue] = [:]
        result["title"] = try guildRequestText(title, length: 0...152133)
        result["number"] = try guildRequestNumber(number)
        result["html_url"] = try webhookCompatibilityURL(htmlURL)
        try guildRequestField(answerHTMLURL, name: "answer_html_url", nullable: true, into: &result) { try webhookCompatibilityURL($0) }
        try guildRequestField(body, name: "body", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        result["user"] = user.jsonValue()
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubIssue compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubIssue: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - id: Required wire id as Int64.
    ///   - number: Required wire number as Int64.
    ///   - htmlURL: Required wire html_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - user: Required wire user as WebhookGitHubUser.
    ///   - title: Required wire title as String. Maximum 152133 Unicode scalars.
    ///   - body: Omitted by default; null permitted; wire body as String. Maximum 152133 Unicode scalars.
    ///   - pullRequest: Omitted by default; null permitted; wire pull_request as JSONValue.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(id: Int64,
                number: Int64,
                htmlURL: String,
                user: WebhookGitHubUser,
                title: String,
                body: Field<String> = .absent,
                pullRequest: Field<JSONValue> = .absent) throws {
        var result: [String: JSONValue] = [:]
        result["id"] = try guildRequestNumber(id)
        result["number"] = try guildRequestNumber(number)
        result["html_url"] = try webhookCompatibilityURL(htmlURL)
        result["user"] = user.jsonValue()
        result["title"] = try guildRequestText(title, length: 0...152133)
        try guildRequestField(body, name: "body", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(pullRequest, name: "pull_request", nullable: true, into: &result) { $0 }
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubRelease compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubRelease: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - id: Required wire id as Int64.
    ///   - tagName: Required wire tag_name as String. Maximum 152133 Unicode scalars.
    ///   - htmlURL: Required wire html_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - author: Required wire author as WebhookGitHubUser.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(id: Int64,
                tagName: String,
                htmlURL: String,
                author: WebhookGitHubUser) throws {
        var result: [String: JSONValue] = [:]
        result["id"] = try guildRequestNumber(id)
        result["tag_name"] = try guildRequestText(tagName, length: 0...152133)
        result["html_url"] = try webhookCompatibilityURL(htmlURL)
        result["author"] = author.jsonValue()
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubRepository compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubRepository: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - id: Required wire id as Int64.
    ///   - htmlURL: Required wire html_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - name: Required wire name as String. Maximum 152133 Unicode scalars.
    ///   - fullName: Required wire full_name as String. Maximum 152133 Unicode scalars.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(id: Int64,
                htmlURL: String,
                name: String,
                fullName: String) throws {
        var result: [String: JSONValue] = [:]
        result["id"] = try guildRequestNumber(id)
        result["html_url"] = try webhookCompatibilityURL(htmlURL)
        result["name"] = try guildRequestText(name, length: 0...152133)
        result["full_name"] = try guildRequestText(fullName, length: 0...152133)
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubReview compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubReview: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - user: Required wire user as WebhookGitHubUser.
    ///   - body: Omitted by default; null permitted; wire body as String. Maximum 152133 Unicode scalars.
    ///   - htmlURL: Required wire html_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - state: Required wire state as String. Maximum 152133 Unicode scalars.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(user: WebhookGitHubUser,
                body: Field<String> = .absent,
                htmlURL: String,
                state: String) throws {
        var result: [String: JSONValue] = [:]
        result["user"] = user.jsonValue()
        try guildRequestField(body, name: "body", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        result["html_url"] = try webhookCompatibilityURL(htmlURL)
        result["state"] = try guildRequestText(state, length: 0...152133)
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubUser compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubUser: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - id: Required wire id as Int64.
    ///   - login: Required wire login as String. Maximum 152133 Unicode scalars.
    ///   - htmlURL: Required wire html_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - avatarURL: Required wire avatar_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(id: Int64,
                login: String,
                htmlURL: String,
                avatarURL: String) throws {
        var result: [String: JSONValue] = [:]
        result["id"] = try guildRequestNumber(id)
        result["login"] = try guildRequestText(login, length: 0...152133)
        result["html_url"] = try webhookCompatibilityURL(htmlURL)
        result["avatar_url"] = try webhookCompatibilityURL(avatarURL)
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 GithubWebhook compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookGitHubExecute: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - action: Omitted by default; null permitted; wire action as String. Maximum 152133 Unicode scalars.
    ///   - reference: Omitted by default; null permitted; wire ref as String. Maximum 152133 Unicode scalars.
    ///   - refType: Omitted by default; null permitted; wire ref_type as String. Maximum 152133 Unicode scalars.
    ///   - comment: Omitted by default; null permitted; wire comment as WebhookGitHubComment.
    ///   - issue: Omitted by default; null permitted; wire issue as WebhookGitHubIssue.
    ///   - pullRequest: Omitted by default; null permitted; wire pull_request as WebhookGitHubIssue.
    ///   - repository: Omitted by default; null permitted; wire repository as WebhookGitHubRepository.
    ///   - forkee: Omitted by default; null permitted; wire forkee as WebhookGitHubRepository.
    ///   - sender: Required wire sender as WebhookGitHubUser.
    ///   - member: Omitted by default; null permitted; wire member as WebhookGitHubUser.
    ///   - release: Omitted by default; null permitted; wire release as WebhookGitHubRelease.
    ///   - headCommit: Omitted by default; null permitted; wire head_commit as WebhookGitHubCommit.
    ///   - commits: Omitted by default; null permitted; wire commits as [WebhookGitHubCommit]. At most 1521 ordered items.
    ///   - forced: Omitted by default; null permitted; wire forced as Bool.
    ///   - compare: Omitted by default; null permitted; wire compare as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - review: Omitted by default; null permitted; wire review as WebhookGitHubReview.
    ///   - checkRun: Omitted by default; null permitted; wire check_run as WebhookGitHubCheckRun.
    ///   - checkSuite: Omitted by default; null permitted; wire check_suite as WebhookGitHubCheckSuite.
    ///   - discussion: Omitted by default; null permitted; wire discussion as WebhookGitHubDiscussion.
    ///   - answer: Omitted by default; null permitted; wire answer as WebhookGitHubComment.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(action: Field<String> = .absent,
                reference: Field<String> = .absent,
                refType: Field<String> = .absent,
                comment: Field<WebhookGitHubComment> = .absent,
                issue: Field<WebhookGitHubIssue> = .absent,
                pullRequest: Field<WebhookGitHubIssue> = .absent,
                repository: Field<WebhookGitHubRepository> = .absent,
                forkee: Field<WebhookGitHubRepository> = .absent,
                sender: WebhookGitHubUser,
                member: Field<WebhookGitHubUser> = .absent,
                release: Field<WebhookGitHubRelease> = .absent,
                headCommit: Field<WebhookGitHubCommit> = .absent,
                commits: Field<[WebhookGitHubCommit]> = .absent,
                forced: Field<Bool> = .absent,
                compare: Field<String> = .absent,
                review: Field<WebhookGitHubReview> = .absent,
                checkRun: Field<WebhookGitHubCheckRun> = .absent,
                checkSuite: Field<WebhookGitHubCheckSuite> = .absent,
                discussion: Field<WebhookGitHubDiscussion> = .absent,
                answer: Field<WebhookGitHubComment> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(action, name: "action", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(reference, name: "ref", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(refType, name: "ref_type", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(comment, name: "comment", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(issue, name: "issue", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(pullRequest, name: "pull_request", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(repository, name: "repository", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(forkee, name: "forkee", nullable: true, into: &result) { $0.jsonValue() }
        result["sender"] = sender.jsonValue()
        try guildRequestField(member, name: "member", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(release, name: "release", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(headCommit, name: "head_commit", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(commits, name: "commits", nullable: true, into: &result) { try webhookCompatibilityArray($0, maximum: 1521) }
        try guildRequestField(forced, name: "forced", nullable: true, into: &result) { .bool($0) }
        try guildRequestField(compare, name: "compare", nullable: true, into: &result) { try webhookCompatibilityURL($0) }
        try guildRequestField(review, name: "review", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(checkRun, name: "check_run", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(checkSuite, name: "check_suite", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(discussion, name: "discussion", nullable: true, into: &result) { $0.jsonValue() }
        try guildRequestField(answer, name: "answer", nullable: true, into: &result) { $0.jsonValue() }
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 SlackWebhook compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookSlackExecute: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - text: Omitted by default; null permitted; wire text as String. Maximum 2000 Unicode scalars.
    ///   - username: Omitted by default; null permitted; wire username as String. Maximum 152133 Unicode scalars.
    ///   - iconURL: Omitted by default; null permitted; wire icon_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - attachments: Omitted by default; null permitted; wire attachments as [WebhookSlackEmbed]. At most 1521 ordered items.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(text: Field<String> = .absent,
                username: Field<String> = .absent,
                iconURL: Field<String> = .absent,
                attachments: Field<[WebhookSlackEmbed]> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(text, name: "text", nullable: true, into: &result) { try guildRequestText($0, length: 0...2000) }
        try guildRequestField(username, name: "username", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(iconURL, name: "icon_url", nullable: true, into: &result) { try webhookCompatibilityURL($0) }
        try guildRequestField(attachments, name: "attachments", nullable: true, into: &result) { try webhookCompatibilityArray($0, maximum: 1521) }
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 WebhookSlackEmbed compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookSlackEmbed: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - title: Omitted by default; null permitted; wire title as String. Maximum 152133 Unicode scalars.
    ///   - titleLink: Omitted by default; null permitted; wire title_link as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - text: Omitted by default; null permitted; wire text as String. Maximum 152133 Unicode scalars.
    ///   - color: Omitted by default; null permitted; wire color as String. Maximum 7 Unicode scalars. A three- or six-digit hexadecimal color prefixed by #.
    ///   - ts: Omitted by default; null permitted; wire ts as Int64.
    ///   - pretext: Omitted by default; null permitted; wire pretext as String. Maximum 152133 Unicode scalars.
    ///   - footer: Omitted by default; null permitted; wire footer as String. Maximum 152133 Unicode scalars.
    ///   - footerIcon: Omitted by default; null permitted; wire footer_icon as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - authorName: Omitted by default; null permitted; wire author_name as String. Maximum 152133 Unicode scalars.
    ///   - authorLink: Omitted by default; null permitted; wire author_link as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - authorIcon: Omitted by default; null permitted; wire author_icon as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - imageURL: Omitted by default; null permitted; wire image_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - thumbURL: Omitted by default; null permitted; wire thumb_url as String. Maximum 2048 Unicode scalars. Absolute URI with a scheme; no dereferencing occurs.
    ///   - fields: Omitted by default; null permitted; wire fields as [WebhookSlackEmbedField]. At most 1521 ordered items.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(title: Field<String> = .absent,
                titleLink: Field<String> = .absent,
                text: Field<String> = .absent,
                color: Field<String> = .absent,
                ts: Field<Int64> = .absent,
                pretext: Field<String> = .absent,
                footer: Field<String> = .absent,
                footerIcon: Field<String> = .absent,
                authorName: Field<String> = .absent,
                authorLink: Field<String> = .absent,
                authorIcon: Field<String> = .absent,
                imageURL: Field<String> = .absent,
                thumbURL: Field<String> = .absent,
                fields: Field<[WebhookSlackEmbedField]> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(title, name: "title", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(titleLink, name: "title_link", nullable: true, into: &result) { try webhookCompatibilityURL($0) }
        try guildRequestField(text, name: "text", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(color, name: "color", nullable: true, into: &result) { try webhookCompatibilityColor($0) }
        try guildRequestField(ts, name: "ts", nullable: true, into: &result) { try guildRequestNumber($0) }
        try guildRequestField(pretext, name: "pretext", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(footer, name: "footer", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(footerIcon, name: "footer_icon", nullable: true, into: &result) { try webhookCompatibilityURL($0) }
        try guildRequestField(authorName, name: "author_name", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(authorLink, name: "author_link", nullable: true, into: &result) { try webhookCompatibilityURL($0) }
        try guildRequestField(authorIcon, name: "author_icon", nullable: true, into: &result) { try webhookCompatibilityURL($0) }
        try guildRequestField(imageURL, name: "image_url", nullable: true, into: &result) { try webhookCompatibilityURL($0) }
        try guildRequestField(thumbURL, name: "thumb_url", nullable: true, into: &result) { try webhookCompatibilityURL($0) }
        try guildRequestField(fields, name: "fields", nullable: true, into: &result) { try webhookCompatibilityArray($0, maximum: 1521) }
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validated API v10 WebhookSlackEmbedField compatibility fields from the official OpenAPI preview, verified 2026-10-16.
/// Omitted and explicit nullable fields remain distinct; no request, permission lookup or external read occurs.
public struct WebhookSlackEmbedField: GuildRequestPayload {
    private let fields: [String: JSONValue]

    /// Validates every supplied known field synchronously without mutating server state.
    /// - Parameters:
    ///   - name: Omitted by default; null permitted; wire name as String. Maximum 152133 Unicode scalars.
    ///   - value: Omitted by default; null permitted; wire value as String. Maximum 152133 Unicode scalars.
    ///   - inline: Omitted by default; null permitted; wire inline as Bool.
    /// - Throws: Sanitized validation errors for forbidden nulls or violations of the field constraints
    ///   documented above. Nested payload validation errors propagate without echoing caller content.
    public init(name: Field<String> = .absent,
                value: Field<String> = .absent,
                inline: Field<Bool> = .absent) throws {
        var result: [String: JSONValue] = [:]
        try guildRequestField(name, name: "name", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(value, name: "value", nullable: true, into: &result) { try guildRequestText($0, length: 0...152133) }
        try guildRequestField(inline, name: "inline", nullable: true, into: &result) { .bool($0) }
        self.fields = result
    }
    /// Produces exact validated compatibility JSON, retaining explicit null and caller ordering.
    /// - Returns: Non-file request object without defaults, hidden hydration or credential values.
    public func jsonValue() -> JSONValue { .object(fields) }
}

/// Validates an absolute URI under the preview 2,048-scalar bound without fetching it.
/// - Parameter value: Exact caller-supplied URI; GitHub/Slack may apply additional scheme policy.
/// - Returns: Original JSON string.
/// - Throws: Sanitized invalid-value errors for missing schemes or overlong/invalid URI syntax.
private func webhookCompatibilityURL(_ value: String) throws -> JSONValue {
    guard value.unicodeScalars.count <= 2_048, let url = URL(string: value), url.scheme != nil,
          !value.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.properties.generalCategory == .control })
    else { throw DiscordError.validation(.invalidValue) }
    return .string(value)
}

/// Encodes one typed compatibility-object array after checking the written preview count bound.
/// - Parameters:
///   - values: Ordered immutable nested request objects, including empty arrays.
///   - maximum: Positive schema maximum; current compatibility arrays use 1,521.
/// - Returns: Ordered JSON object array without fetching or copying external data.
/// - Throws: A safe limit-exceeded error when the array exceeds its explicit schema cap.
private func webhookCompatibilityArray<T: GuildRequestPayload>(_ values: [T], maximum: Int) throws -> JSONValue {
    guard values.count <= maximum else { throw DiscordError.validation(.limitExceeded) }
    return .array(values.map { $0.jsonValue() })
}

/// Validates Slack attachment hexadecimal colors without accepting undocumented symbolic names.
/// - Parameter value: A # prefix followed by exactly three or six hexadecimal digits.
/// - Returns: Original color JSON string without normalization.
/// - Throws: Sanitized invalid-value errors for every other format.
private func webhookCompatibilityColor(_ value: String) throws -> JSONValue {
    guard [4, 7].contains(value.utf8.count), value.first == "#",
          value.utf8.dropFirst().allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) })
    else { throw DiscordError.validation(.invalidValue) }
    return .string(value)
}
