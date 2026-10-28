// File: Sources/DiscordHTTP/Resources/ApplicationEndpoints.swift
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import DiscordCore
import DiscordModels
import Foundation

/// Three API v10 Application operations, verified 2026-10-16 against the written reference and official preview.
/// All require the application's bot token, with no Gateway intents, pagination or audit reason headers.
/// The shared HTTP coordinator owns credential-global/server-route admission, cancellation and bounded 429 retries.
/// Activity instances are finite snapshots; fetching one does not create a connection or Activity lifecycle owner.
public enum ApplicationEndpoints {
    /// Gets the current complete application configuration associated with the authenticated bot user.
    /// - Parameter readPolicy: Credential-scoped eligible-read policy; default coalesces in flight without completed caching.
    ///   A positive caller-selected TTL can serve stale configuration until expiry or a successful local mutation.
    /// - Returns: Safe HTTP 200 GET descriptor with typed owned children and exact unknown-field preservation.
    /// - Throws: Descriptor/policy validation errors now; auth/API/transport/schema/cancellation errors at execution.
    public static func current(readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Application> {
        try Endpoint(method: "GET", path: ["applications", "@me"], route: "/applications/@me",
            authentication: .bot, retrySafety: .safe, readPolicy: applicationReadPolicy(readPolicy),
            decode: { try Application(data: $0) })
    }

    /// Edits only explicitly selected properties of the current authenticated application.
    /// - Parameter request: Validated presence-aware fields; empty changes remain an explicit empty object.
    /// - Returns: Unsafe HTTP 200 PATCH descriptor with the updated complete Application and credential-scoped
    ///   application-cache invalidation. It does not silently read configuration, merge writes or retry ambiguous submission.
    /// - Throws: Body/descriptor errors now; bot ownership, URL challenges, feature checks and API/transport errors later.
    ///   Submitted transport/server failures can be indeterminate; complete 429 rejections share the finite retry budget.
    public static func modifyCurrent(request: ApplicationModify) throws -> Endpoint<Application> {
        try Endpoint(method: "PATCH", path: ["applications", "@me"], route: "/applications/@me",
            authentication: .bot, body: guildJSON(request.jsonValue()), invalidates: ["application-catalog"],
            decode: { try Application(data: $0) })
    }

    /// Gets one existing serialized Activity instance without listing instances or creating an Activity session.
    /// - Parameters:
    ///   - applicationID: Owning application; Discord validates the bot token belongs to it.
    ///   - instanceID: Opaque nonempty identifier, at most 152133 Unicode scalars per the preview; path traversal,
    ///     separators and control characters are rejected. Other opaque characters are percent-encoded as one segment.
    ///     The shared 65536-byte UTF-8 descriptor metadata budget can impose a smaller local limit.
    ///   - readPolicy: Credential-scoped in-flight coalescing by default; nil disables reuse, a positive TTL may be stale.
    /// - Returns: Safe HTTP 200 GET with typed users/location; a missing instance remains the server's API error.
    /// - Throws: Path/policy errors before I/O; auth/API/transport/schema/cancellation errors at execution.
    /// No application major rate partition is invented; this uses ordinary coordinated credential-global admission.
    public static func activityInstance(applicationID: ApplicationID, instanceID: String,
                                        readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<ApplicationActivityInstance> {
        guard instanceID.unicodeScalars.count <= 152_133 else { throw DiscordError.validation(.invalidValue) }
        return try Endpoint(method: "GET", path: ["applications", applicationID.description, "activity-instances", instanceID],
            route: "/applications/{application.id}/activity-instances/{instance.id}", authentication: .bot,
            retrySafety: .safe, readPolicy: applicationReadPolicy(readPolicy),
            decode: { try ApplicationActivityInstance(data: $0) })
    }
}

extension DiscordEndpoints {
    /// Preserves the original current-application entry point while adopting the complete typed Application catalog.
    /// - Parameter readPolicy: Credential-scoped read reuse; default coalesces in flight without a completed cache.
    /// - Returns: The same immutable safe GET descriptor as ApplicationEndpoints.current, including mutation invalidation tags.
    /// - Throws: Descriptor/policy errors now; execution inherits shared auth, rate, bounded retry and cancellation behavior.
    public static func currentApplication(readPolicy: ReadPolicy? = ReadPolicy()) throws -> Endpoint<Application> {
        try ApplicationEndpoints.current(readPolicy: readPolicy)
    }
}

/// Adds shared application invalidation tags without changing caller coalescing or cache freshness choices.
/// - Parameter policy: Caller-selected read policy; nil disables read reuse entirely.
/// - Returns: Equivalent policy tagged for application mutations within the same authorization scope, or nil.
/// No I/O, tasks, global cache ownership or implicit freshness duration is introduced.
func applicationReadPolicy(_ policy: ReadPolicy?) -> ReadPolicy? {
    policy.map { ReadPolicy(coalescing: $0.coalescing, timeToLive: $0.timeToLive,
                           tags: $0.tags.union(["application-catalog"])) }
}
