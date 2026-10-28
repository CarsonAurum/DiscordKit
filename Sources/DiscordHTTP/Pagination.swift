// File: Sources/DiscordHTTP/Pagination.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordTransport
import Foundation

/// An operation-specific page whose explicit next cursor alone controls termination.
public struct CursorPage<Item: Sendable, Cursor: Sendable & Hashable>: Sendable {
    public let items: [Item]
    public let nextCursor: Cursor?

    /// Stores one page without inferring completion from item count.
    /// - Parameters:
    ///   - items: Ordered results, including empty or short intermediate pages.
    ///   - nextCursor: Exact next request cursor; `nil` explicitly means complete.
    public init(items: [Item], nextCursor: Cursor?) { self.items = items; self.nextCursor = nextCursor }
}

/// Lazy, nonprefetching page iteration with operation-defined cursors and termination.
/// Each iterator owns independent cursor state. Do not use one iterator concurrently.
/// The injected fetch closure must enforce an operation-specific page-byte/item limit;
/// this helper bounds page count and cursor history rather than retaining page results.
public struct CursorPagination<Item: Sendable, Cursor: Sendable & Hashable, C: Clock>: AsyncSequence, Sendable
where C.Duration == Duration {
    public typealias Element = [Item]
    private let initialCursor: Cursor?
    private let maximumPages: Int
    private let context: TransportContext<C>
    private let fetch: @Sendable (Cursor?) async throws -> CursorPage<Item, Cursor>

    /// Configures a lazy sequence; no network request occurs before iterator `next()`.
    /// - Parameters:
    ///   - initialCursor: Exact starting token, or `nil` for the operation's first page.
    ///   - maximumPages: Positive page budget, default 10,000, bounding cursor history.
    ///   - context: Clock/cancellation/deadline domain used for every fetch.
    ///   - fetch: Operation-specific read, returning an explicit next token. Must honor cancellation.
    /// - Throws: Safe validation errors for a nonpositive page budget.
    public init(initialCursor: Cursor? = nil, maximumPages: Int = 10_000, context: TransportContext<C>,
                fetch: @escaping @Sendable (Cursor?) async throws -> CursorPage<Item, Cursor>) throws {
        guard maximumPages > 0 else { throw DiscordError.validation(.invalidValue) }
        self.initialCursor = initialCursor; self.maximumPages = maximumPages; self.context = context; self.fetch = fetch
    }

    /// Creates independent cursor history without starting a fetch or prefetch task.
    /// - Returns: A single-consumer iterator yielding one complete page per pull.
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(cursor: initialCursor, maximumPages: maximumPages, context: context, fetch: fetch)
    }

    /// A page iterator preserving exact cursors and terminating permanently after failure.
    public struct AsyncIterator: AsyncIteratorProtocol {
        private var cursor: Cursor?
        private var visited: Set<Cursor> = []
        private var pageCount = 0
        private var finished = false
        private let maximumPages: Int
        private let context: TransportContext<C>
        private let fetch: @Sendable (Cursor?) async throws -> CursorPage<Item, Cursor>

        /// Binds a new iterator to immutable sequence configuration.
        /// - Parameters:
        ///   - cursor: Starting request cursor, preserved exactly.
        ///   - maximumPages: Validated positive page budget.
        ///   - context: Shared monotonic deadline and cancellation checks.
        ///   - fetch: Operation-specific bounded page read.
        fileprivate init(cursor: Cursor?, maximumPages: Int, context: TransportContext<C>,
                         fetch: @escaping @Sendable (Cursor?) async throws -> CursorPage<Item, Cursor>) {
            self.cursor = cursor; self.maximumPages = maximumPages; self.context = context; self.fetch = fetch
            if let cursor { visited.insert(cursor) }
        }

        /// Fetches exactly one page and advances only after successful completion.
        /// - Returns: Page items, including empty intermediate/final pages, or `nil` after explicit completion.
        /// - Throws: Fetch errors, cancellation, deadline expiry, safe page-budget failure, or invalid-response
        ///   errors for repeated cursors. Any failure permanently finishes this iterator; create another to retry.
        public mutating func next() async throws -> [Item]? {
            guard !finished else { return nil }
            do {
                try context.check()
                guard pageCount < maximumPages else { throw DiscordError.validation(.limitExceeded) }
                let cursor = self.cursor
                let fetch = self.fetch
                let page = try await context.run { try await fetch(cursor) }
                if let next = page.nextCursor {
                    guard visited.insert(next).inserted else { throw DiscordError.transport(.invalidResponse) }
                } else { finished = true }
                self.cursor = page.nextCursor; pageCount += 1
                return page.items
            } catch { finished = true; throw error }
        }
    }
}

/// An operation-defined async-job result; no generic HTTP status implies completion.
public enum PollingState<Value: Sendable>: Sendable {
    case pending
    case complete(Value)
}

/// Sequential async-job polling sharing the caller's cancellation and monotonic deadline.
public enum PollingOperation {
    /// Polls until an operation-specific completion state or a finite attempt budget.
    /// - Parameters:
    ///   - context: Clock and optional absolute deadline; checked before each attempt and sleep.
    ///   - maximumAttempts: Positive total request budget, including the first attempt.
    ///   - interval: Positive delay between pending results; no sleep follows the final attempt.
    ///   - operation: Cancellation-cooperative, bounded operation-specific status read.
    /// - Returns: The first `.complete` value; pending results are never returned as successful values.
    /// - Throws: Safe invalid-configuration/budget errors, operation errors, cancellation, or deadline expiry.
    ///   Polls never overlap, and an operation failure is never automatically retried.
    public static func poll<Value: Sendable, C: Clock>(
        context: TransportContext<C>, maximumAttempts: Int, interval: Duration,
        operation: @escaping @Sendable () async throws -> PollingState<Value>
    ) async throws -> Value where C.Duration == Duration {
        guard maximumAttempts > 0, interval > .zero else { throw DiscordError.validation(.invalidValue) }
        return try await context.run {
            for attempt in 0..<maximumAttempts {
                try context.check()
                switch try await operation() {
                case .complete(let value): return value
                case .pending:
                    if attempt + 1 < maximumAttempts {
                        try await context.clock.sleep(until: context.clock.now.advanced(by: interval), tolerance: nil)
                    }
                }
            }
            throw DiscordError.validation(.limitExceeded)
        }
    }
}
