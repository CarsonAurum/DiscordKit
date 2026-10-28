// File: Browser/DiscordActivityBridge/ActivityBridge.mjs
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

/** Owned Activity RPC v1 browser protocol. No construction starts listeners, timers, or I/O. */
export const ActivityOpcodes = Object.freeze({ HANDSHAKE: 0, FRAME: 1, CLOSE: 2, HELLO: 3 });

/** A bounded bridge failure. The `code` is safe for diagnostics; messages may contain host data. */
export class ActivityBridgeError extends Error {
    /**
     * Creates an error without retaining request payloads or credentials.
     * @param {string} code Stable local failure category.
     * @param {string} message Human-readable description; never log without considering host data.
     * @param {number|undefined} rpcCode Optional Discord-provided numeric error code.
     */
    constructor(code, message, rpcCode) {
        super(message);
        this.name = "ActivityBridgeError";
        this.code = code;
        this.rpcCode = rpcCode;
    }
}

/**
 * Parses the host's query parameters without inferring identity from document referrers.
 * Unknown parameters are ignored. Required identifiers must be nonempty and unique; optional
 * parameters preserve missing versus empty values. Known values are at most 4096 UTF-8 bytes and
 * cannot contain ASCII controls. Host IDs are opaque strings, never Numbers.
 * @param {string} search URL query text, optionally beginning with `?`; at most 16 KiB UTF-8.
 * @returns {Readonly<object>} Validated desktop/mobile Activity context.
 * @throws {ActivityBridgeError} For missing, duplicated, oversized, or invalid required parameters.
 */
export function parseActivityHostParameters(search) {
    if (typeof search !== "string" || utf8Bytes(search) > 16384) throw failure("invalidParameters", "Host query exceeds its bound");
    const query = new URLSearchParams(search);
    const result = {};
    const names = ["frame_id", "instance_id", "platform", "custom_id", "referrer_id", "guild_id", "channel_id", "location_id", "mobile_app_version"];
    for (const name of names) {
        const values = query.getAll(name);
        if (values.length > 1) throw failure("invalidParameters", `Duplicate host parameter: ${name}`);
        if (values.length && (utf8Bytes(values[0]) > 4096 || /[\x00-\x1f\x7f]/.test(values[0]))) throw failure("invalidParameters", `Invalid bounded host parameter: ${name}`);
        result[name] = values.length === 0 ? null : values[0];
    }
    for (const name of ["frame_id", "instance_id", "platform"]) {
        if (!result[name]) throw failure("invalidParameters", `Missing host parameter: ${name}`);
    }
    if (!["desktop", "mobile"].includes(result.platform)) throw failure("invalidParameters", "Unknown Activity platform");
    return Object.freeze(result);
}

/**
 * Creates an inert window adapter. The caller must obtain the trusted host WindowProxy from its
 * embedding contract (parent or parent.opener); neither this adapter nor the bridge trusts referrer.
 * @param {Window} activityWindow Local browser window that receives message events.
 * @param {WindowProxy} trustedSource Explicitly selected Discord host, never an arbitrary sender.
 * @returns {{listen: function(Function): Function, post: function(Array, string): void}} An injectable transport.
 */
export function createWindowTransport(activityWindow, trustedSource) {
    if (!activityWindow?.addEventListener || !activityWindow?.removeEventListener || !trustedSource?.postMessage) {
        throw failure("invalidTransport", "A window and explicit trusted host are required");
    }
    return Object.freeze({
        /** Installs one listener; its idempotent cleanup is owned by ActivityBridge. */
        listen(listener) {
            activityWindow.addEventListener("message", listener);
            let listening = true;
            return () => {
                if (listening) activityWindow.removeEventListener("message", listener);
                listening = false;
            };
        },
        /** Sends to an exact configured origin; no wildcard target is accepted. */
        post(tuple, origin) {
            validateOrigin(origin);
            trustedSource.postMessage(tuple, origin);
        },
    });
}

/**
 * Creates an inert authenticated raw-byte adapter for Swift/Wasm, a native WebKit message handler,
 * or another host binding that owns the RPC lifecycle. This adapter handles browser provenance and
 * JSON/byte framing only: the Swift owner performs handshake, READY, nonce correlation, deadlines,
 * subscription reference counts, and bounded receive-queue/pending-read ownership. No timers or
 * read promises exist here. Each callback must synchronously copy/enqueue its bytes into that owner.
 * @param {object} options Explicit browser security boundary.
 * @param {Window} options.activityWindow Activity window whose message events are observed.
 * @param {WindowProxy} options.trustedSource Embedding-contract-selected Discord WindowProxy.
 * @param {string} options.hostOrigin Exact configured host origin, never `*`, `null`, or a referrer URL.
 * @param {string[]} options.allowedOrigins Explicit bounded deployment allowlist containing hostOrigin.
 * @param {number} [options.maxFrameBytes=1048576] Positive UTF-8 byte bound on individual tuples.
 * @returns {{start: Function, send: Function, close: Function}} Single-owner lifecycle and byte transport.
 * @throws {ActivityBridgeError} Invalid source, window, origin allowlist, or byte bound.
 */
export function createActivityTransport({ activityWindow, trustedSource, hostOrigin, allowedOrigins, maxFrameBytes = 1048576 }) {
    validateOrigin(hostOrigin);
    positiveInteger(maxFrameBytes);
    if (!Array.isArray(allowedOrigins) || allowedOrigins.length === 0 || allowedOrigins.length > 32) throw failure("invalidOrigin", "An explicit bounded origin allowlist is required");
    for (const origin of allowedOrigins) validateOrigin(origin);
    if (!allowedOrigins.includes(hostOrigin)) throw failure("invalidOrigin", "Host origin is absent from allowlist");
    const transport = createWindowTransport(activityWindow, trustedSource);
    let state = "idle";
    let cleanup;
    let receive;
    let ended;

    /** Detaches the listener once and notifies the read owner to reject every queued/pending read. */
    function finish(error) {
        if (state === "closed") return;
        state = "closed";
        try { cleanup?.(); } catch { /* Host teardown must not strand Swift read ownership. */ }
        cleanup = undefined;
        const callback = ended;
        receive = undefined;
        ended = undefined;
        try { callback?.(error); } catch { /* Owner callback failures cannot prevent cleanup. */ }
    }

    return Object.freeze({
        /**
         * Installs the sole host listener. Starting twice throws; a closed adapter cannot reopen.
         * @param {function(Uint8Array): void} onFrame Receives owned bounded UTF-8 JSON tuple bytes.
         * @param {function(ActivityBridgeError): void} onClose Must release native receive/read waiters.
         * @throws {ActivityBridgeError} Invalid callbacks, reused lifecycle, or listener adapter failure.
         */
        start(onFrame, onClose) {
            if (state !== "idle") throw failure("invalidState", "Raw Activity adapter has already started or closed");
            if (typeof onFrame !== "function" || typeof onClose !== "function") throw failure("invalidTransport", "Frame and close callbacks are required");
            state = "started";
            receive = onFrame;
            ended = onClose;
            try {
                cleanup = transport.listen((event) => {
                    if (state !== "started" || event?.source !== trustedSource || event.origin !== hostOrigin) return;
                    try {
                        const incoming = normalizeIncomingPermissions(event.data);
                        if (jsonBytes(incoming) > maxFrameBytes) throw failure("capacity", "Incoming tuple exceeds byte capacity");
                        const tuple = jsonCopy(incoming);
                        validateTuple(tuple);
                        receive(new TextEncoder().encode(JSON.stringify(tuple)));
                    } catch (error) { finish(error instanceof ActivityBridgeError ? error : failure("invalidFrame", "Invalid host tuple or receive callback failure")); }
                });
            } catch (error) { finish(normalizeError(error)); throw normalizeError(error); }
        },
        /**
         * Decodes one Swift-owned byte frame using strict UTF-8 and posts its JSON tuple to the exact
         * host origin. The call copies/parses synchronously; it never retains native buffer storage.
         * @param {Uint8Array} bytes Bounded UTF-8 `[opcode, objectPayload]`; numbers must be finite and integer-valued numbers safe integers.
         * @throws {ActivityBridgeError} Closed/unstarted transport, malformed UTF-8/JSON, bound or I/O failure.
         */
        send(bytes) {
            if (state !== "started") throw failure("invalidState", "Raw Activity adapter is not started");
            if (!(bytes instanceof Uint8Array) || bytes.byteLength > maxFrameBytes) throw failure("capacity", "Expected bounded UTF-8 tuple bytes");
            let tuple;
            try { tuple = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)); }
            catch { throw failure("invalidFrame", "Expected valid UTF-8 JSON tuple bytes"); }
            tuple = jsonCopy(tuple);
            validateTuple(tuple);
            try { transport.post(tuple, hostOrigin); } catch (error) { throw normalizeError(error); }
        },
        /**
         * Detaches the browser listener and calls onClose once. The RPC owner sends its own opcode-2
         * close before this call if needed; this method does not fabricate protocol lifecycle frames.
         */
        close() { finish(failure("closed", "Raw Activity adapter closed")); },
    });
}

const DEFAULT_LIMITS = Object.freeze({
    maxFrameBytes: 1024 * 1024,
    maxPending: 64,
    maxPendingBytes: 4 * 1024 * 1024,
    maxListeners: 128,
    maxSubscriptions: 64,
    maxQueuedEvents: 128,
    maxQueuedEventBytes: 4 * 1024 * 1024,
    timeoutMs: 15000,
});

/**
 * Owned, transport-independent Activity iframe RPC v1 lifecycle. Every incoming frame checks source
 * identity AND an exact allowlisted origin. Command retries are deliberately absent: mutations may
 * already have happened when a deadline/cancellation fires. Unknown dispatch names remain observable.
 * Callers sharing a bridge also share its admission bounds; control work does not await listeners.
 */
export class ActivityBridge {
    #transport; #source; #origin; #limits; #timers; #nonce; #counter = 0;
    #cleanup; #state = "idle"; #startup; #pending = new Map(); #pendingBytes = 0;
    #subscriptions = new Map(); #listenerCount = 0; #events = []; #eventBytes = 0;
    #bridgeID; #closeError;

    /**
     * Validates configuration synchronously without listeners, timers, commands, or background work.
     * @param {object} options Configuration.
     * @param {string} options.clientId Discord application ID as an opaque nonempty string.
     * @param {string} options.search Discord host query string; see parseActivityHostParameters.
     * @param {object} options.source Explicit trusted source identity matched with strict equality.
     * @param {string} options.hostOrigin Exact trusted host origin, including scheme and optional port.
     * @param {string[]} options.allowedOrigins Explicit deployment allowlist; must include hostOrigin.
     * @param {{listen: Function, post: Function}} options.transport Injected window/native host adapter.
     * @param {object} [options.limits] Positive integer resource/deadline overrides; timeout <= 2^31-1 ms.
     * @param {{setTimeout: Function, clearTimeout: Function}} [options.timers] Injectable deterministic timers.
     * @param {function(): string} [options.nonceFactory] Bounded nonce suffix for tests; session counter guarantees uniqueness.
     * @throws {ActivityBridgeError} Invalid context, transport, origin, client ID, or resource bounds.
     */
    constructor({ clientId, search, source, hostOrigin, allowedOrigins, transport, limits = {}, timers = globalThis, nonceFactory }) {
        if (typeof clientId !== "string" || !clientId || clientId.length > 128) throw failure("invalidConfiguration", "A bounded application ID is required");
        validateOrigin(hostOrigin);
        if (!Array.isArray(allowedOrigins) || allowedOrigins.length === 0 || allowedOrigins.length > 32) throw failure("invalidOrigin", "An explicit bounded origin allowlist is required");
        for (const origin of allowedOrigins) validateOrigin(origin);
        if (!allowedOrigins.includes(hostOrigin)) throw failure("invalidOrigin", "Host origin is absent from allowlist");
        if (!source || typeof transport?.listen !== "function" || typeof transport?.post !== "function") throw failure("invalidTransport", "Explicit source and transport are required");
        if (typeof timers?.setTimeout !== "function" || typeof timers?.clearTimeout !== "function") throw failure("invalidConfiguration", "Timer adapter is invalid");
        if (nonceFactory !== undefined && typeof nonceFactory !== "function") throw failure("invalidConfiguration", "Nonce factory is invalid");
        for (const key of Object.keys(limits)) if (!(key in DEFAULT_LIMITS)) throw failure("invalidConfiguration", "Unknown resource limit");
        this.#limits = Object.freeze({ ...DEFAULT_LIMITS, ...limits });
        for (const value of Object.values(this.#limits)) positiveInteger(value);
        if (this.#limits.timeoutMs > 2147483647) throw failure("invalidConfiguration", "Timeout exceeds timer range");
        Object.defineProperties(this, {
            context: { value: parseActivityHostParameters(search), enumerable: true },
            clientId: { value: clientId, enumerable: true },
        });
        this.#source = source;
        this.#origin = hostOrigin;
        this.#transport = transport;
        this.#timers = timers;
        this.#nonce = nonceFactory;
        this.#bridgeID = globalThis.crypto.randomUUID();
    }

    /** Returns lifecycle status without starting work. @returns {string} idle, starting, ready, or closed. */
    get state() { return this.#state; }

    /**
     * Returns bounded diagnostic counts without payloads, user IDs, tokens, or listener references.
     * @returns {Readonly<object>} Current pending, subscription, listener, and event accounting.
     */
    get diagnostics() {
        return Object.freeze({ state: this.#state, pending: this.#pending.size, pendingBytes: this.#pendingBytes,
            subscriptions: this.#subscriptions.size, listeners: this.#listenerCount,
            queuedEvents: this.#events.length, queuedEventBytes: this.#eventBytes });
    }

    /**
     * Installs a listener and sends exactly one opcode-0 v1 handshake, then waits for authenticated
     * DISPATCH/READY with null nonce. Repeated calls while starting share that startup; a later call's
     * options do not replace the first deadline/signal. Already-ready calls resolve immediately.
     * @param {object} [options] First-start cancellation and deadline.
     * @param {AbortSignal} [options.signal] Aborting startup closes the session and rejects all work.
     * @param {number} [options.timeoutMs] Positive deadline in ms; defaults to configured timeout.
     * @returns {Promise<object>} READY data from the explicitly trusted host.
     */
    start({ signal, timeoutMs = this.#limits.timeoutMs } = {}) {
        if (this.#state === "closed") return Promise.reject(this.#closeError);
        if (this.#startup) return this.#startup.promise;
        try { this.#validateOperation(signal, timeoutMs); } catch (error) { return Promise.reject(error); }
        if (signal?.aborted) return Promise.reject(aborted());
        this.#state = "starting";
        this.#startup = deferred();
        const startup = this.#startup;
        startup.timer = this.#timers.setTimeout(() => this.#terminate(failure("timeout", "Activity READY deadline elapsed")), timeoutMs);
        startup.abort = () => this.#terminate(aborted());
        startup.signal = signal;
        signal?.addEventListener("abort", startup.abort, { once: true });
        try {
            this.#cleanup = this.#transport.listen((event) => this.#receive(event));
            if (typeof this.#cleanup !== "function") throw failure("invalidTransport", "listen must return cleanup");
            const handshake = { v: 1, encoding: "json", client_id: this.clientId, frame_id: this.context.frame_id };
            // Upstream protocol permits sdk_version on desktop and mobile >=250. We omit that optional
            // field: this owned bridge is not the upstream npm SDK and must not impersonate its version.
            this.#post([ActivityOpcodes.HANDSHAKE, handshake]);
        } catch (error) { this.#terminate(normalizeError(error)); }
        return startup.promise;
    }

    /**
     * Sends one correlated frame after READY. Reply command AND nonce must match; unknown/mismatched
     * replies cannot consume another caller's continuation. Cancellation removes local ownership only;
     * host mutation outcome may be indeterminate. No automatic retries occur.
     * @param {string} cmd Nonempty protocol command, including future unknown command names.
     * @param {object|null} args JSON arguments; null is preserved, numbers finite, integer-valued numbers safe.
     * @param {object} [options] Optional event correlation, cancellation, and deadline.
     * @param {string} [options.evt] Subscription event qualifier, checked against successful reply data.evt.
     * @param {AbortSignal} [options.signal] Rejects before or during admission; no wire cancellation exists.
     * @param {number} [options.timeoutMs] Positive timeout in milliseconds.
     * @returns {Promise<object>} Complete matching response frame, preserving unknown data fields.
     */
    request(cmd, args = {}, { evt, signal, timeoutMs = this.#limits.timeoutMs } = {}) {
        if (this.#state !== "ready") return Promise.reject(this.#state === "closed" ? this.#closeError : failure("notReady", "Activity has not received READY"));
        try {
            this.#validateOperation(signal, timeoutMs);
            validName(cmd);
            if (evt !== undefined) validName(evt);
            if (signal?.aborted) throw aborted();
            if (this.#pending.size >= this.#limits.maxPending) throw failure("capacity", "Pending command capacity exhausted");
            if (this.#counter === Number.MAX_SAFE_INTEGER) throw failure("capacity", "Session nonce space exhausted");
            const suffix = this.#nonce ? this.#nonce() : "";
            if (typeof suffix !== "string" || suffix.length > 128) throw failure("invalidNonce", "Nonce factory must return bounded strings");
            const nonce = `${this.#bridgeID}:${++this.#counter}:${suffix}`;
            const frame = { cmd, args, nonce, ...(evt === undefined ? {} : { evt }) };
            const tuple = jsonCopy([ActivityOpcodes.FRAME, frame]);
            const bytes = jsonBytes(tuple);
            if (bytes > this.#limits.maxFrameBytes || bytes + this.#pendingBytes > this.#limits.maxPendingBytes) throw failure("capacity", "Command byte capacity exhausted");
            const pending = { ...deferred(), cmd, evt, bytes, signal };
            pending.abort = () => this.#settle(nonce, aborted());
            pending.timer = this.#timers.setTimeout(() => this.#settle(nonce, failure("timeout", "Activity command deadline elapsed")), timeoutMs);
            this.#pending.set(nonce, pending);
            this.#pendingBytes += bytes;
            signal?.addEventListener("abort", pending.abort, { once: true });
            try { this.#transport.post(tuple, this.#origin); } catch (error) { this.#settle(nonce, normalizeError(error)); }
            return pending.promise;
        } catch (error) { return Promise.reject(error); }
    }

    /**
     * Retains a listener and joins a canonical event+arguments subscription. Concurrent duplicate
     * subscriptions send one upstream SUBSCRIBE. Transitions serialize across cancellation and final
     * release; failed transition closes the session because host subscription state is indeterminate.
     * Listeners run synchronously in receipt order; throws are isolated. They should enqueue heavy work.
     * @param {string} event Event name; unknown future events are accepted. READY is lifecycle-only.
     * @param {object|null} args JSON subscription arguments; object key order does not affect identity.
     * @param {function(*): void} listener Receives event data; exceptions do not interrupt other listeners.
     * @param {object} [options] Listener cancellation and upstream transition timeout.
     * @param {AbortSignal} [options.signal] Removes this listener; never cancels another subscriber.
     * @param {number} [options.timeoutMs] Positive deadline for a newly created upstream group.
     * @returns {Promise<{unsubscribe: function(): Promise<void>}>} Idempotent owned subscription handle.
     */
    subscribe(event, args = {}, listener, { signal, timeoutMs = this.#limits.timeoutMs } = {}) {
        if (this.#state !== "ready") return Promise.reject(this.#state === "closed" ? this.#closeError : failure("notReady", "Activity has not received READY"));
        try {
            validName(event);
            this.#validateOperation(signal, timeoutMs);
            if (["READY", "ERROR"].includes(event) || typeof listener !== "function") throw failure("invalidSubscription", "Use lifecycle/event queue for READY and ERROR");
            if (signal?.aborted) throw aborted();
            if (this.#listenerCount >= this.#limits.maxListeners) throw failure("capacity", "Listener capacity exhausted");
            const copied = jsonCopy(args);
            const key = `${event}:${canonicalJSON(copied)}`;
            if (utf8Bytes(key) > this.#limits.maxFrameBytes) throw failure("capacity", "Subscription arguments exceed byte capacity");
            let group = this.#subscriptions.get(key);
            if (!group) {
                if (this.#subscriptions.size >= this.#limits.maxSubscriptions) throw failure("capacity", "Subscription capacity exhausted");
                group = { key, event, args: copied, tokens: new Set(), active: false, running: false, timeoutMs, releases: [] };
                this.#subscriptions.set(key, group);
            }
            const token = { listener, signal, ...deferred(), released: false };
            token.abort = () => { this.#release(group, token, aborted()).catch(() => {}); };
            group.tokens.add(token);
            this.#listenerCount++;
            signal?.addEventListener("abort", token.abort, { once: true });
            if (group.active && !group.running) token.resolve(this.#handle(group, token));
            this.#reconcile(group);
            return token.promise;
        } catch (error) { return Promise.reject(error); }
    }

    /**
     * Drains all queued dispatch/error frames in receive order and releases their accounted bytes.
     * Overflow closes the bridge; events are never silently dropped. Listener delivery also enqueues
     * frames, so consumers must drain this bounded diagnostic/native handoff queue regularly.
     * @returns {object[]} Owned JSON frames including unknown event names and data.
     */
    takeEvents() {
        const result = this.#events;
        this.#events = [];
        this.#eventBytes = 0;
        return result;
    }

    /**
     * Sends an optional opcode-2 close and deterministically releases listeners, timers, subscriptions,
     * queued events, and every waiter. Idempotent; no handshake or pending command can revive it.
     * @param {number} [code=1000] Nonnegative integer protocol close code.
     * @param {string} [message="Activity closed"] Bounded public reason; never include access tokens.
     */
    close(code = 1000, message = "Activity closed") {
        if (this.#state === "closed") return;
        if (!Number.isSafeInteger(code) || code < 0 || typeof message !== "string" || utf8Bytes(message) > 1024) throw failure("invalidClose", "Invalid close code or bounded reason");
        try { if (this.#state !== "idle") this.#post([ActivityOpcodes.CLOSE, { code, message }]); } catch { /* Local cleanup must always complete. */ }
        this.#terminate(failure("closed", message, code));
    }

    /** Validates operation bounds before installing cancellation handlers or allocating a request. */
    #validateOperation(signal, timeoutMs) {
        positiveInteger(timeoutMs);
        if (timeoutMs > 2147483647) throw failure("invalidConfiguration", "Timeout exceeds timer range");
        if (signal !== undefined && (typeof signal.addEventListener !== "function" || typeof signal.removeEventListener !== "function" || typeof signal.aborted !== "boolean")) throw failure("invalidConfiguration", "Expected AbortSignal");
    }

    /** Posts a bounded JSON copy so later caller mutation cannot alter an admitted message. */
    #post(tuple) {
        const copied = jsonCopy(tuple);
        if (jsonBytes(copied) > this.#limits.maxFrameBytes) throw failure("capacity", "Frame exceeds byte capacity");
        this.#transport.post(copied, this.#origin);
    }

    /** Validates authenticated host envelopes before interpreting opcode or correlated content. */
    #receive(event) {
        if (this.#state === "closed" || event?.source !== this.#source || event.origin !== this.#origin) return;
        let tuple;
        try {
            const incoming = normalizeIncomingPermissions(event.data);
            if (jsonBytes(incoming) > this.#limits.maxFrameBytes) { this.#terminate(failure("capacity", "Incoming frame exceeds byte capacity")); return; }
            tuple = jsonCopy(incoming);
        } catch { this.#terminate(failure("invalidFrame", "Host sent non-JSON frame")); return; }
        if (!Array.isArray(tuple) || tuple.length !== 2 || !Number.isInteger(tuple[0]) || !isObject(tuple[1])) {
            this.#terminate(failure("invalidFrame", "Invalid host tuple")); return;
        }
        const [opcode, frame] = tuple;
        if (opcode === ActivityOpcodes.HELLO || opcode === ActivityOpcodes.HANDSHAKE) return;
        if (opcode === ActivityOpcodes.CLOSE) {
            if (!Number.isSafeInteger(frame.code) || frame.code < 0 || (frame.message !== undefined && typeof frame.message !== "string")) { this.#terminate(failure("invalidFrame", "Invalid host close")); return; }
            this.#terminate(failure("closed", frame.message ?? "Activity host closed", frame.code)); return;
        }
        if (opcode !== ActivityOpcodes.FRAME || typeof frame.cmd !== "string" || !("data" in frame)) {
            this.#terminate(failure("invalidFrame", "Unknown opcode or invalid host frame")); return;
        }
        if (frame.cmd === "DISPATCH") {
            if (typeof frame.evt !== "string" || frame.nonce != null) return;
            if (frame.evt === "READY") {
                if (this.#state !== "starting" || frame.nonce !== null || !validReadyData(frame.data)) return;
                this.#state = "ready";
                this.#clearWaiter(this.#startup);
                this.#startup.resolve(frame.data);
            } else if (this.#state === "ready") {
                this.#enqueue(frame);
                if (this.#state === "closed") return;
                for (const group of this.#subscriptions.values()) {
                    if (group.event !== frame.evt) continue;
                    for (const token of [...group.tokens]) {
                        if (token.released) continue;
                        try { token.listener(jsonCopy(frame.data)); } catch { /* User listener failures are isolated. */ }
                    }
                }
            }
            return;
        }
        if (frame.evt === "ERROR" && frame.nonce == null) { if (this.#state === "ready") this.#enqueue(frame); return; }
        if (typeof frame.nonce !== "string") return;
        const pending = this.#pending.get(frame.nonce);
        if (!pending || pending.cmd !== frame.cmd) return;
        if (frame.evt === "ERROR") {
            if (!isObject(frame.data) || typeof frame.data.message !== "string" || !Number.isSafeInteger(frame.data.code)) return;
            this.#settle(frame.nonce, failure("rpc", frame.data.message, frame.data.code));
        } else if (frame.evt === null && (pending.evt === undefined || (isObject(frame.data) && frame.data.evt === pending.evt))) this.#settle(frame.nonce, null, frame);
    }

    /** Appends one complete event under count/byte bounds; overflow ends the session deterministically. */
    #enqueue(frame) {
        const bytes = jsonBytes(frame);
        if (this.#events.length >= this.#limits.maxQueuedEvents || this.#eventBytes + bytes > this.#limits.maxQueuedEventBytes) {
            this.#terminate(failure("capacity", "Event queue capacity exhausted")); return;
        }
        this.#events.push(frame);
        this.#eventBytes += bytes;
    }

    /** Settles exactly one admitted nonce and relinquishes its accounting before invoking promise code. */
    #settle(nonce, error, frame) {
        const pending = this.#pending.get(nonce);
        if (!pending) return;
        this.#pending.delete(nonce);
        this.#pendingBytes -= pending.bytes;
        this.#clearWaiter(pending);
        if (error) pending.reject(error); else pending.resolve(frame);
    }

    /** Clears an owned timer and cancellation listener; safe after it already fired. */
    #clearWaiter(waiter) {
        if (!waiter) return;
        this.#timers.clearTimeout(waiter.timer);
        waiter.signal?.removeEventListener("abort", waiter.abort);
    }

    /** Creates an idempotent release capability without exposing mutable group internals. */
    #handle(group, token) {
        return Object.freeze({ unsubscribe: () => this.#release(group, token) });
    }

    /** Removes one listener immediately and awaits any necessary serialized final upstream transition. */
    #release(group, token, error) {
        if (token.released) return token.releasePromise ?? Promise.resolve();
        token.released = true;
        group.tokens.delete(token);
        this.#listenerCount--;
        token.signal?.removeEventListener("abort", token.abort);
        token.reject(error ?? failure("cancelled", "Subscription released"));
        if (this.#state === "closed" || group.tokens.size > 0) return Promise.resolve();
        const release = deferred();
        group.releases.push(release);
        token.releasePromise = release.promise;
        this.#reconcile(group);
        return release.promise;
    }

    /** Drives one group through bounded subscribe/unsubscribe transitions, with no concurrent wire commands. */
    async #reconcile(group) {
        if (group.running || this.#state !== "ready") return;
        group.running = true;
        try {
            while (this.#state === "ready" && group.active !== (group.tokens.size > 0)) {
                const subscribing = group.tokens.size > 0;
                await this.request(subscribing ? "SUBSCRIBE" : "UNSUBSCRIBE", group.args, { evt: group.event, timeoutMs: group.timeoutMs });
                if (this.#state !== "ready") return;
                group.active = subscribing;
                if (subscribing) for (const token of group.tokens) token.resolve(this.#handle(group, token));
            }
            if (group.tokens.size === 0 && !group.active) this.#subscriptions.delete(group.key);
            for (const release of group.releases.splice(0)) release.resolve();
        } catch (error) { this.#terminate(normalizeError(error)); }
        finally { group.running = false; }
    }

    /** Rejects all ownership, empties bounds, and detaches the host listener once; never throws. */
    #terminate(error) {
        if (this.#state === "closed") return;
        this.#state = "closed";
        this.#closeError = error;
        try { this.#cleanup?.(); } catch { /* Host adapter cleanup must not strand waiters. */ }
        this.#cleanup = undefined;
        this.#clearWaiter(this.#startup);
        this.#startup?.reject(error);
        for (const nonce of this.#pending.keys()) this.#settle(nonce, error);
        for (const group of this.#subscriptions.values()) {
            for (const token of group.tokens) {
                token.released = true;
                token.signal?.removeEventListener("abort", token.abort);
                token.reject(error);
            }
            for (const release of group.releases) release.reject(error);
        }
        this.#subscriptions.clear();
        this.#listenerCount = 0;
        this.#events = [];
        this.#eventBytes = 0;
    }
}

/** Creates a stable local error category and optional upstream numeric code. */
function failure(code, message, rpcCode) { return new ActivityBridgeError(code, message, rpcCode); }
/** Normalizes arbitrary adapter throws without retaining adapter payloads. */
function normalizeError(error) { return error instanceof ActivityBridgeError ? error : failure("transport", "Activity transport failed"); }
/** Creates the cancellation category used for startup, requests, and listener ownership. */
function aborted() { return failure("cancelled", "Activity operation cancelled"); }
/** Returns a deferred promise; continuations are kept only within configured ownership bounds. */
function deferred() { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }
/** Validates an exact web origin, excluding opaque/null origins, credentials, paths, and wildcards. */
function validateOrigin(origin) {
    let url;
    try { url = new URL(origin); } catch { throw failure("invalidOrigin", "Expected an exact HTTPS or HTTP origin"); }
    if (!["https:", "http:"].includes(url.protocol) || origin !== url.origin || url.username || url.password || origin.includes("*")) throw failure("invalidOrigin", "Expected an exact HTTPS or HTTP origin");
}
/** Requires a positive safe integer capacity or deadline; zero cannot disable a bound. */
function positiveInteger(value) { if (!Number.isSafeInteger(value) || value <= 0) throw failure("invalidConfiguration", "Expected positive integer bound"); }
/** Checks bounded opaque protocol names without requiring knowledge of future command/event names. */
function validName(value) { if (typeof value !== "string" || !value || value.length > 128) throw failure("invalidName", "Expected a nonempty bounded protocol name"); }
/** Tests for a nonnull object record, excluding arrays. */
function isObject(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
/** Checks the transport-neutral tuple envelope; opcode-specific schemas remain the RPC owner's job. */
function validateTuple(tuple) { if (!Array.isArray(tuple) || tuple.length !== 2 || !Number.isSafeInteger(tuple[0]) || !isObject(tuple[1])) throw failure("invalidFrame", "Expected [opcode, objectPayload] tuple"); }
/** Validates all published READY fields while preserving unknown extensions and the optional user projection. */
function validReadyData(data) {
    if (!isObject(data) || data.v !== 1 || !isObject(data.config)
        || typeof data.config.api_endpoint !== "string" || typeof data.config.environment !== "string"
        || (data.config.cdn_host !== undefined && typeof data.config.cdn_host !== "string")) return false;
    if (data.user === undefined) return true;
    return isObject(data.user) && typeof data.user.id === "string" && typeof data.user.username === "string"
        && typeof data.user.discriminator === "string" && (data.user.avatar === undefined || typeof data.user.avatar === "string");
}
/**
 * Normalizes the published GET_CHANNEL_PERMISSIONS structured-clone bigint|string union at the JSON
 * binding boundary. Only this documented field converts; decimal strings preserve every permission
 * bit without Number rounding. Other BigInts remain invalid JSON and are rejected rather than guessed.
 */
function normalizeIncomingPermissions(tuple) {
    if (Array.isArray(tuple) && tuple.length === 2 && tuple[0] === ActivityOpcodes.FRAME && isObject(tuple[1])
        && tuple[1].cmd === "GET_CHANNEL_PERMISSIONS" && tuple[1].evt === null && isObject(tuple[1].data) && typeof tuple[1].data.permissions === "bigint") {
        return [tuple[0], { ...tuple[1], data: { ...tuple[1].data, permissions: tuple[1].data.permissions.toString() } }];
    }
    return tuple;
}
/** Measures UTF-8 bytes, never UTF-16 code units, for portable resource accounting. */
function utf8Bytes(value) { return new TextEncoder().encode(value).byteLength; }
/** Measures JSON frame bytes and rejects unsupported serialization. */
function jsonBytes(value) { const json = JSON.stringify(value); if (json === undefined) throw failure("invalidFrame", "Expected JSON data"); return utf8Bytes(json); }
/**
 * Copies values within the JavaScript JSON numeric domain: finite numbers and safe integer-valued
 * Numbers only. Unsafe integers are rejected before postMessage instead of silently rounding Swift's
 * lossless JSON numeric lexemes. Fractional values follow native JavaScript binary-number semantics.
 * Undefined/functions/symbols, BigInts outside the documented permissions normalization, and cycles fail.
 */
function jsonCopy(value) {
    const text = JSON.stringify(value, (_key, item) => {
        if (item === undefined || typeof item === "function" || typeof item === "symbol" || typeof item === "bigint"
            || (typeof item === "number" && (!Number.isFinite(item) || (Number.isInteger(item) && !Number.isSafeInteger(item))))) throw failure("invalidFrame", "Expected supported JSON values and safe integer numbers");
        return item;
    });
    if (text === undefined) throw failure("invalidFrame", "Expected JSON data");
    return JSON.parse(text);
}
/** Produces a deterministic structural subscription key; arrays preserve order and objects sort keys. */
function canonicalJSON(value) {
    if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
    if (isObject(value)) return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJSON(value[key])}`).join(",")}}`;
    return JSON.stringify(value);
}
