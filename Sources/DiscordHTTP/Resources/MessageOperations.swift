import DiscordCore
import DiscordModels
import DiscordTransport

/// Explicit, lazy API v10 message workflows using caller-owned execution and deadlines.
///
/// These helpers do not create a client, cache responses, prefetch, or retry failed requests.
/// Supply a cancellation-cooperative closure such as `{ try await client.execute($0) }`;
/// the client's shared rate coordinator still governs each descriptor independently.
/// Iterators are single-consumer; separate iterators have independent progress and may
/// execute concurrently. Each retained cursor set is bounded by at most 10,000 pages.
/// Endpoint permissions, API v10 content eligibility and server-side rate limits still apply;
/// these helpers confer no authorization. Verified 2026-10-16 against
/// https://docs.discord.com/developers/resources/message and
/// https://docs.discord.com/developers/resources/poll.
public enum MessageOperations {
    /// Lazily reads channel history newest first, advancing the exclusive before-message cursor.
    /// A short page continues; only an empty response completes this traversal.
    /// - Parameters:
    ///   - channelID: Channel requiring VIEW_CHANNEL and READ_MESSAGE_HISTORY.
    ///   - before: Optional initial exclusive message ID; nil starts at the newest message.
    ///   - limit: Requested and accepted page size, 1...100; default 100.
    ///   - maximumPages: Local request/page budget, 1...10,000; default 10,000.
    ///   - context: Injected monotonic clock, cancellation and optional inclusive deadline.
    ///   - execute: Sequential bounded descriptor executor; must release resources on cancellation.
    /// - Returns: Independent lazy page iterators, including the final empty page.
    /// - Throws: Safe configuration errors now; execution errors, repeated/nonadvancing cursors,
    ///   oversized responses, cancellation, deadlines or page exhaustion during iteration.
    /// No completed-result caching or read coalescing is requested by these descriptors.
    public static func historyPages<C: Clock>(
        channelID: ChannelID, before: MessageID? = nil, limit: Int = 100, maximumPages: Int = 10_000,
        context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<[Message]>) async throws -> [Message]
    ) throws -> CursorPagination<Message, MessageID, C> where C.Duration == Duration {
        try operationPageLimit(maximumPages)
        _ = try MessageEndpoints.history(channelID: channelID, limit: limit, readPolicy: nil)
        return try CursorPagination(initialCursor: before, maximumPages: maximumPages, context: context) { cursor in
            let items = try await execute(MessageEndpoints.history(channelID: channelID,
                position: cursor.map(MessageHistoryPosition.before), limit: limit, readPolicy: nil))
            guard items.count <= limit else { throw DiscordError.transport(.invalidResponse) }
            let next = items.last?.id
            if let cursor, let next, next >= cursor { throw DiscordError.transport(.invalidResponse) }
            return CursorPage(items: items, nextCursor: next)
        }
    }

    /// Lazily reads current pin objects using `has_more` and the last exact `pinned_at` spelling.
    /// Page length does not imply completion. Legacy message-only pin routes are not used.
    /// - Parameters:
    ///   - channelID: Channel requiring VIEW_CHANNEL and READ_MESSAGE_HISTORY.
    ///   - before: Optional initial exclusive timestamp; its precision and offset are preserved.
    ///   - limit: Requested and accepted page size, 1...50; default 50.
    ///   - maximumPages: Local request/page budget, 1...10,000; default 10,000.
    ///   - context: Shared clock, cancellation and optional inclusive deadline.
    ///   - execute: Cancellation-cooperative executor, invoked only when a page is pulled.
    /// - Returns: Lazy pages of pin objects; `has_more == false` finishes after that page.
    /// - Throws: Configuration or executor errors, cancellation/deadlines, oversized pages,
    ///   repeated cursors, or `has_more` with no item from which to obtain the next cursor.
    public static func pinPages<C: Clock>(
        channelID: ChannelID, before: DiscordTimestamp? = nil, limit: Int = 50, maximumPages: Int = 10_000,
        context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<MessagePins>) async throws -> MessagePins
    ) throws -> CursorPagination<MessagePin, DiscordTimestamp, C> where C.Duration == Duration {
        try operationPageLimit(maximumPages)
        _ = try MessageEndpoints.pins(channelID: channelID, limit: limit, readPolicy: nil)
        return try CursorPagination(initialCursor: before, maximumPages: maximumPages, context: context) { cursor in
            let page = try await execute(MessageEndpoints.pins(channelID: channelID, before: cursor, limit: limit, readPolicy: nil))
            guard page.items.count <= limit, !page.hasMore || !page.items.isEmpty
            else { throw DiscordError.transport(.invalidResponse) }
            let next = page.hasMore ? page.items.last?.pinnedAt : nil
            if let cursor, let next {
                guard next.unixSeconds < cursor.unixSeconds ||
                        (next.unixSeconds == cursor.unixSeconds && next.nanosecond < cursor.nanosecond)
                else { throw DiscordError.transport(.invalidResponse) }
            }
            return CursorPage(items: page.items, nextCursor: next)
        }
    }

    /// Lazily reads normal or burst reaction users using exclusive ascending user-ID cursors.
    /// A short page continues; only an empty response completes traversal.
    /// - Parameters:
    ///   - channelID: Channel requiring VIEW_CHANNEL and READ_MESSAGE_HISTORY.
    ///   - messageID: Reacted message in that channel.
    ///   - emoji: Unescaped Unicode or named custom emoji, escaped once by the descriptor.
    ///   - type: Normal reactions by default; burst selects super-reaction users.
    ///   - after: Optional starting exclusive user ID.
    ///   - limit: Requested and accepted page size, 1...100; default 100.
    ///   - maximumPages: Local request/page budget, 1...10,000; default 10,000.
    ///   - context: Shared cancellation, clock and optional deadline domain.
    ///   - execute: Sequential executor with cooperative cancellation and bounded response bytes.
    /// - Returns: Independent lazy user pages including the final empty page.
    /// - Throws: Configuration/emoji errors now; executor errors, oversized/nonadvancing pages,
    ///   cancellation, deadlines or exhausted page budget during iteration.
    public static func reactionPages<C: Clock>(
        channelID: ChannelID, messageID: MessageID, emoji: ReactionEmoji, type: MessageReactionType = .normal,
        after: UserID? = nil, limit: Int = 100, maximumPages: Int = 10_000, context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<[User]>) async throws -> [User]
    ) throws -> CursorPagination<User, UserID, C> where C.Duration == Duration {
        try operationPageLimit(maximumPages)
        _ = try MessageEndpoints.reactions(channelID: channelID, messageID: messageID, emoji: emoji,
            type: type, limit: limit, readPolicy: nil)
        return try userPages(after: after, limit: limit, maximumPages: maximumPages, context: context) { cursor in
            try await execute(MessageEndpoints.reactions(channelID: channelID, messageID: messageID,
                emoji: emoji, type: type, after: cursor, limit: limit, readPolicy: nil))
        }
    }

    /// Lazily reads poll answer voters using exclusive ascending user-ID cursors until an empty page.
    /// - Parameters:
    ///   - channelID: Channel containing the poll; server visibility rules apply.
    ///   - messageID: Message containing the poll.
    ///   - answerID: Positive answer identifier from the poll, rather than its array index.
    ///   - after: Optional starting exclusive voter ID.
    ///   - limit: Requested and accepted page size, 1...100; default 100.
    ///   - maximumPages: Local request/page budget, 1...10,000; default 10,000.
    ///   - context: Injected monotonic deadline and cooperative cancellation domain.
    ///   - execute: Sequential cancellation-cooperative executor; descriptors request no read reuse.
    /// - Returns: Lazy voter pages, including a final empty page even after a short nonempty page.
    /// - Throws: Configuration errors now; executor errors, malformed/oversized/nonadvancing pages,
    ///   cancellation, deadlines or page-budget exhaustion during iteration.
    public static func pollVoterPages<C: Clock>(
        channelID: ChannelID, messageID: MessageID, answerID: Int, after: UserID? = nil,
        limit: Int = 100, maximumPages: Int = 10_000, context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<[User]>) async throws -> [User]
    ) throws -> CursorPagination<User, UserID, C> where C.Duration == Duration {
        try operationPageLimit(maximumPages)
        _ = try PollEndpoints.voters(channelID: channelID, messageID: messageID, answerID: answerID,
            limit: limit, readPolicy: nil)
        return try userPages(after: after, limit: limit, maximumPages: maximumPages, context: context) { cursor in
            try await execute(PollEndpoints.voters(channelID: channelID, messageID: messageID,
                answerID: answerID, after: cursor, limit: limit, readPolicy: nil))
        }
    }

    /// Lazily pages guild-message search, polling 202 indexing responses before yielding each page.
    /// The offset advances by the requested limit, including empty or short intermediate results.
    /// - Parameters:
    ///   - guildID: Guild requiring READ_MESSAGE_HISTORY and MESSAGE_CONTENT eligibility.
    ///   - query: Immutable filters, initial offset and page size, verified by `MessageSearchQuery`.
    ///   - maximumPages: Local completed-page budget, 1...10,000; default 10,000.
    ///   - maximumIndexingAttempts: Per-page request budget including the first attempt, 1...1,000;
    ///     default 10. A request failure propagates immediately and is never polled again.
    ///   - maximumRetryDelaySeconds: Maximum accepted server retry delay in seconds, finite and
    ///     in 0.1...3,600; default 60. Zero server delay becomes 100 ms to avoid a busy loop.
    ///   - context: Shared clock and optional inclusive deadline for requests and indexing sleeps.
    ///   - execute: Cancellation-cooperative executor. Search descriptors disable caching/coalescing.
    /// - Returns: Lazy pages of message groups, retaining the API's nested match/context shape.
    ///   Completion requires both no deep historical indexing and `offset + limit >= total_results`.
    /// - Throws: Configuration errors now; original executor errors, cancellation/deadlines,
    ///   malformed/oversized responses, indexing budget/delay violations, or local page exhaustion.
    ///   Needing an offset above 9,975 throws `validation(.limitExceeded)` on the next pull;
    ///   this search-window boundary is never reported as successful complete traversal.
    public static func searchPages<C: Clock>(
        guildID: GuildID, query: MessageSearchQuery, maximumPages: Int = 10_000,
        maximumIndexingAttempts: Int = 10, maximumRetryDelaySeconds: Double = 60,
        context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<MessageSearchResponse>) async throws -> MessageSearchResponse
    ) throws -> CursorPagination<[Message], Int, C> where C.Duration == Duration {
        try operationPageLimit(maximumPages)
        guard (1...1_000).contains(maximumIndexingAttempts), maximumRetryDelaySeconds.isFinite,
              (0.1...3_600).contains(maximumRetryDelaySeconds)
        else { throw DiscordError.validation(.invalidValue) }
        _ = try MessageEndpoints.search(guildID: guildID, query: query)
        return try CursorPagination(initialCursor: query.offset, maximumPages: maximumPages, context: context) { cursor in
            let offset = cursor ?? query.offset
            guard offset <= 9_975 else { throw DiscordError.validation(.limitExceeded) }
            let result = try await searchResult(guildID: guildID, query: query, offset: offset,
                maximumAttempts: maximumIndexingAttempts, maximumDelay: maximumRetryDelaySeconds,
                context: context, execute: execute)
            guard result.messages.count <= query.limit else { throw DiscordError.transport(.invalidResponse) }
            let next = offset + query.limit
            let complete = !result.doingDeepHistoricalIndex && next >= result.totalResults
            return CursorPage(items: result.messages, nextCursor: complete ? nil : next)
        }
    }

    /// Implements sequential indexing polling inside the caller's enclosing structured deadline race.
    /// - Parameters:
    ///   - guildID: Exact guild search scope.
    ///   - query: Validated immutable filters and page size.
    ///   - offset: Validated current search offset, 0...9,975.
    ///   - maximumAttempts: Validated finite per-page request budget.
    ///   - maximumDelay: Validated finite accepted server delay in seconds.
    ///   - context: Cancellation/deadline checks and clock used for owned sleeps.
    ///   - execute: Original executor; calls are awaited before another is started.
    /// - Returns: The first completed results envelope, including empty deep-indexing pages.
    /// - Throws: Original executor, clock, cancellation and deadline errors; invalid-response errors
    ///   for negative/nonfinite/excessive retry delays; limit-exceeded after the final pending attempt.
    private static func searchResult<C: Clock>(
        guildID: GuildID, query: MessageSearchQuery, offset: Int, maximumAttempts: Int,
        maximumDelay: Double, context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<MessageSearchResponse>) async throws -> MessageSearchResponse
    ) async throws -> MessageSearchResults where C.Duration == Duration {
        for attempt in 0..<maximumAttempts {
            try context.check()
            switch try await execute(MessageEndpoints.search(guildID: guildID, query: query, offset: offset)) {
            case .results(let result): return result
            case .indexing(let pending):
                let delay = pending.retryAfter
                guard delay.isFinite, delay >= 0, delay <= maximumDelay
                else { throw DiscordError.transport(.invalidResponse) }
                guard attempt + 1 < maximumAttempts else { throw DiscordError.validation(.limitExceeded) }
                try context.check()
                try await context.clock.sleep(until: context.clock.now.advanced(by: .seconds(max(0.1, delay))), tolerance: nil)
            }
        }
        throw DiscordError.validation(.limitExceeded)
    }

    /// Shares bounded ascending user-cursor traversal between reaction and poll endpoints.
    /// - Parameters:
    ///   - after: Optional initial exclusive user ID.
    ///   - limit: Already validated accepted maximum users per response.
    ///   - maximumPages: Already validated page/cursor-history budget.
    ///   - context: Structured execution, cancellation and deadline domain.
    ///   - fetch: Cancellation-cooperative endpoint-specific user read.
    /// - Returns: Lazy pages ending only after an empty response.
    /// - Throws: Executor/cancellation/deadline errors, invalid-response errors for oversized or
    ///   nonadvancing pages, and a safe limit error when the cursor/page budget is exhausted.
    private static func userPages<C: Clock>(
        after: UserID?, limit: Int, maximumPages: Int, context: TransportContext<C>,
        fetch: @escaping @Sendable (UserID?) async throws -> [User]
    ) throws -> CursorPagination<User, UserID, C> where C.Duration == Duration {
        try CursorPagination(initialCursor: after, maximumPages: maximumPages, context: context) { cursor in
            let users = try await fetch(cursor)
            guard users.count <= limit else { throw DiscordError.transport(.invalidResponse) }
            let next = users.last?.id
            if let cursor, let next, next <= cursor { throw DiscordError.transport(.invalidResponse) }
            return CursorPage(items: users, nextCursor: next)
        }
    }
}

/// An explicit bounded bulk-delete plan. Construction sends no request and changes no server state.
///
/// Discord's bulk endpoint requires MANAGE_MESSAGES and rejects messages older than two weeks.
/// Planning validates age at an explicit trusted wall time; Discord checks age again at execution.
/// Delayed plans can therefore fail as messages age. Chunks run sequentially with no automatic retry,
/// rollback, parallel submission, or fallback to single-message deletion.
public struct BulkMessageDeletePlan: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Complete validated input in its original order; no ID is silently skipped.
    public let messageIDs: [MessageID]
    /// Explicit legal request groups, each containing 2...100 IDs and preserving input order.
    public let chunks: [[MessageID]]
    private let endpoints: [Endpoint<EmptyResponse>]

    /// Validates the entire plan before building legal chunks of 2...100 messages in input order.
    /// - Parameters:
    ///   - channelID: Guild channel requiring MANAGE_MESSAGES and channel visibility.
    ///   - messageIDs: 2...10,000 distinct recent message IDs; duplicates and any too-old ID reject
    ///     the entire plan. A 101-item remainder becomes 99 + 2, avoiding singleton requests.
    ///   - nowMilliseconds: Trusted current Unix milliseconds for exact two-week age validation.
    ///   - auditReason: Optional audit reason, at most 512 Unicode scalars, validated by descriptors.
    /// - Throws: Safe count, duplicate, age, audit or descriptor validation errors before any I/O.
    /// Storage and work are linear in the bounded number of IDs; chunks retain input ordering.
    public init(channelID: ChannelID, messageIDs: [MessageID], nowMilliseconds: UInt64,
                auditReason: String? = nil) throws {
        try validateBulkMessageIDs(messageIDs, maximum: 10_000, nowMilliseconds: nowMilliseconds)
        var chunks: [[MessageID]] = []
        var offset = 0
        while offset < messageIDs.count {
            let remaining = messageIDs.count - offset
            let count = remaining == 101 ? 99 : min(100, remaining)
            chunks.append(Array(messageIDs[offset..<(offset + count)]))
            offset += count
        }
        self.messageIDs = messageIDs
        self.chunks = chunks
        self.endpoints = try chunks.map { try MessageEndpoints.bulkDelete(channelID: channelID,
            messageIDs: $0, nowMilliseconds: nowMilliseconds, auditReason: auditReason) }
    }

    /// Explicitly executes each planned chunk once, awaiting its acknowledgement before submitting another.
    /// - Parameters:
    ///   - context: Shared monotonic clock, cancellation and optional inclusive overall deadline.
    ///   - execute: Caller-owned cancellation-cooperative executor; each unsafe descriptor retains
    ///     normal REST rate admission. The closure must not replay an uncertain mutation.
    /// - Returns: All input IDs in their original order after every chunk is acknowledged.
    /// - Throws: `BulkMessageDeleteFailure` for any execution/check failure, preserving the original
    ///   underlying error, completed chunks, current attempted chunk and wholly unattempted IDs.
    ///   An attempted chunk is not proof of deletion or of submission; reconcile its original error.
    ///   Cancellation before submission records no attempted IDs. All deadline children and resources
    ///   owned by a cooperative executor are awaited before failure returns. Repeating this method
    ///   deliberately starts the entire plan again; it never implicitly resumes partial progress.
    public func execute<C: Clock>(
        context: TransportContext<C>,
        execute: @escaping @Sendable (Endpoint<EmptyResponse>) async throws -> EmptyResponse
    ) async throws -> [MessageID] where C.Duration == Duration {
        var completed: [MessageID] = []
        for (index, endpoint) in endpoints.enumerated() {
            let progress = BulkChunkProgress()
            do { try context.check() }
            catch {
                throw BulkMessageDeleteFailure(completed: completed, attempted: [],
                    unattempted: Array(messageIDs.dropFirst(completed.count)), underlying: error)
            }
            do {
                _ = try await context.run {
                    await progress.start()
                    let response = try await execute(endpoint)
                    await progress.acknowledge()
                    return response
                }
                completed += chunks[index]
            } catch {
                let state = await progress.snapshot()
                if state.acknowledged { completed += chunks[index] }
                let attempted = state.started && !state.acknowledged ? chunks[index] : []
                throw BulkMessageDeleteFailure(completed: completed, attempted: attempted,
                    unattempted: Array(messageIDs.dropFirst(completed.count + attempted.count)), underlying: error)
            }
        }
        return completed
    }

    /// Redacts identifiers, audit text and route details from interpolation.
    public var description: String { "BulkMessageDeletePlan(redacted)" }
    /// Uses the same safe marker for debug output.
    public var debugDescription: String { description }
    /// Prevents reflection from expanding the retained payloads and descriptors.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Tracks one chunk across a structured cancellation/deadline race without losing an acknowledgement.
/// Actor isolation protects the executor child and its awaiting owner; no transport work is retained.
private actor BulkChunkProgress {
    private var started = false
    private var acknowledged = false

    /// Marks entry into the executor closure before calling caller-owned code.
    /// Repeated calls are harmless; this does not claim network submission occurred.
    func start() { started = true }

    /// Records that the executor returned success, including cancellation racing after its return.
    func acknowledge() { acknowledged = true }

    /// Reads final chunk evidence after the structured child has finished and cleanup has completed.
    /// - Returns: Whether execution was entered and whether its success was acknowledged.
    func snapshot() -> (started: Bool, acknowledged: Bool) { (started, acknowledged) }
}

/// A bulk workflow's exact progress without classifying an uncertain chunk as success or failure.
///
/// Inspect the explicit properties to reconcile progress. Diagnostic descriptions and reflection
/// expose neither message IDs nor the original error's potentially unsafe text. An underlying
/// `unknownMutationOutcome` remains that same error; this wrapper never invents retry safety.
public struct BulkMessageDeleteFailure: Error, Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// IDs in chunks for which the executor returned successful acknowledgement.
    public let completed: [MessageID]
    /// Current chunk entered into execution without success acknowledgement; submission may be unknown.
    public let attempted: [MessageID]
    /// Remaining IDs never entered into execution during this invocation.
    public let unattempted: [MessageID]
    /// Original cause, retained without translating mutation uncertainty or exposing it in diagnostics.
    public let underlying: any Error

    /// Records immutable bounded progress from the owning plan, without normalizing the cause.
    /// - Parameters:
    ///   - completed: IDs belonging to earlier acknowledged chunks, in original order.
    ///   - attempted: Current chunk passed to execution, or empty if a prior check prevented execution.
    ///   - unattempted: Remaining IDs never passed to execution, in original order.
    ///   - underlying: Original cancellation, deadline, API, transport or unknown-outcome error.
    /// No retry, rollback, logging, string interpolation or resource ownership occurs here.
    init(completed: [MessageID], attempted: [MessageID], unattempted: [MessageID], underlying: any Error) {
        self.completed = completed; self.attempted = attempted; self.unattempted = unattempted; self.underlying = underlying
    }

    /// Reports a fixed marker without disclosing any progress IDs or underlying text.
    public var description: String { "BulkMessageDeleteFailure(redacted)" }
    /// Uses the same redacted marker for debugging.
    public var debugDescription: String { description }
    /// Suppresses reflective expansion of payloads and the potentially sensitive original error.
    public var customMirror: Mirror { Mirror(self, children: ["redacted": true]) }
}

/// Enforces a finite local bound independently of Discord's endpoint-specific page size.
/// - Parameter count: Requested maximum pages, including final empty pages; valid 1...10,000.
/// - Throws: `DiscordError.validation(.invalidValue)` outside the supported range.
private func operationPageLimit(_ count: Int) throws {
    guard (1...10_000).contains(count) else { throw DiscordError.validation(.invalidValue) }
}
