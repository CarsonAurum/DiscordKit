import test from "node:test";
import assert from "node:assert/strict";
import { ActivityBridge, ActivityBridgeError, createActivityTransport, createWindowTransport, parseActivityHostParameters } from "./ActivityBridge.mjs";

const ORIGIN = "https://discord.com";
const QUERY = "?frame_id=frame&instance_id=18446744073709551615&platform=desktop";
const READY = { cmd: "DISPATCH", evt: "READY", nonce: null, data: { v: 1, config: { api_endpoint: "//discord.com/api", environment: "production" } } };

/** Deterministic timers: callbacks run only when a test advances the manual clock. */
class Timers {
    next = 0;
    now = 0;
    values = new Map();
    /** Records a deadline without scheduling real event-loop work. */
    setTimeout(callback, delay) { const id = ++this.next; this.values.set(id, { callback, at: this.now + delay }); return id; }
    /** Removes an owned deterministic deadline. */
    clearTimeout(id) { this.values.delete(id); }
    /** Advances once and fires all deadlines due at the new time, in admission order. */
    advance(milliseconds) {
        this.now += milliseconds;
        for (const [id, timer] of [...this.values]) if (timer.at <= this.now) { this.values.delete(id); timer.callback(); }
    }
}

/** Creates an inert fake host with explicit source identity and manually delivered message events. */
function fixture({ limits, post, listen, nonceFactory, query = QUERY } = {}) {
    const source = {};
    const timers = new Timers();
    const sent = [];
    let receiver;
    let cleanups = 0;
    const transport = {
        /** Records one listener and returns deterministic cleanup. */
        listen(callback) { if (listen) return listen(callback); receiver = callback; return () => { receiver = undefined; cleanups++; }; },
        /** Captures immutable wire messages and optional synchronous simulated-host responses. */
        post(tuple, origin) { sent.push({ tuple, origin }); post?.(tuple, receive); },
    };
    /** Injects a host MessageEvent while allowing source/origin substitution for adversarial tests. */
    function receive(data, options = {}) { receiver?.({ source, origin: ORIGIN, data, ...options }); }
    const bridge = new ActivityBridge({ clientId: "123", search: query, source, hostOrigin: ORIGIN, allowedOrigins: [ORIGIN], transport, timers, limits, nonceFactory });
    return { bridge, source, timers, sent, receive, get cleanups() { return cleanups; }, get listening() { return Boolean(receiver); } };
}

/** Starts one fixture using a schema-valid synthetic READY frame from the trusted host. */
async function ready(f) { const startup = f.bridge.start(); f.receive([1, READY]); await startup; }

/** Acknowledges the newest wire command while preserving its complete command/event/nonce correlation. */
function acknowledge(f, data = {}, overrides = {}) {
    const wire = f.sent.at(-1).tuple[1];
    f.receive([1, { cmd: wire.cmd, evt: null, nonce: wire.nonce, data: wire.evt === undefined ? data : { ...data, evt: wire.evt }, ...overrides }]);
}

/** Allows bounded promise-chain reconciliation without relying on elapsed wall-clock time. */
async function settle() { for (let index = 0; index < 6; index++) await Promise.resolve(); }

/** Asserts the stable public error category used by a rejected local operation. */
function category(code) { return (error) => error instanceof ActivityBridgeError && error.code === code; }

test("host parameters preserve opaque IDs, unknown fields, missing and empty optional values", () => {
    const context = parseActivityHostParameters(`${QUERY}&guild_id=&custom_id=hello%20world&future=value`);
    assert.equal(context.instance_id, "18446744073709551615");
    assert.equal(context.guild_id, "");
    assert.equal(context.channel_id, null);
    assert.equal(context.custom_id, "hello world");
    assert.equal(context.future, undefined);
    assert.ok(Object.isFrozen(context));
    assert.equal(parseActivityHostParameters(QUERY.replace("desktop", "mobile")).platform, "mobile");
});

test("host parameters reject missing, duplicate, empty, oversized, and invalid platform values", () => {
    for (const query of ["", "?frame_id=f&instance_id=i", QUERY.replace("frame_id=frame", "frame_id="), `${QUERY}&frame_id=again`, QUERY.replace("desktop", "web"), `${QUERY}&custom_id=%00`, `${QUERY}&custom_id=${"x".repeat(4097)}`, "x".repeat(16385)]) {
        assert.throws(() => parseActivityHostParameters(query), category("invalidParameters"));
    }
});

test("construction is inert and explicitly trusted allowlisted origins are required", () => {
    const f = fixture();
    assert.equal(f.bridge.state, "idle");
    assert.equal(f.sent.length, 0);
    assert.equal(f.listening, false);
    assert.equal(f.timers.values.size, 0);
    assert.throws(() => { f.bridge.clientId = "other"; }, TypeError);
    const options = { clientId: "1", search: QUERY, source: {}, transport: { listen() {}, post() {} }, hostOrigin: ORIGIN, allowedOrigins: [ORIGIN] };
    for (const hostOrigin of ["*", "null", "https://discord.com/", "https://user@discord.com", "https://discord.com/path", "file://local"]) assert.throws(() => new ActivityBridge({ ...options, hostOrigin, allowedOrigins: [hostOrigin] }), category("invalidOrigin"));
    assert.throws(() => new ActivityBridge({ ...options, allowedOrigins: ["https://evil.example"] }), category("invalidOrigin"));
    assert.throws(() => new ActivityBridge({ ...options, source: null }), category("invalidTransport"));
    assert.throws(() => new ActivityBridge({ ...options, clientId: "" }), category("invalidConfiguration"));
    for (const limits of [{ maxPending: 0 }, { timeoutMs: 2147483648 }, { unknown: 1 }, { maxListeners: NaN }]) assert.throws(() => new ActivityBridge({ ...options, limits }), category("invalidConfiguration"));
});

test("start sends exact v1 handshake and rejects wrong-source/origin and spoofed READY", async () => {
    const f = fixture();
    const startup = f.bridge.start();
    assert.equal(f.bridge.start(), startup);
    assert.deepEqual(f.sent, [{ tuple: [0, { v: 1, encoding: "json", client_id: "123", frame_id: "frame" }], origin: ORIGIN }]);
    f.receive([1, READY], { source: {} });
    f.receive([1, READY], { origin: "https://canary.discord.com" });
    f.receive([1, READY], { origin: "null" });
    f.receive([1, { ...READY, nonce: "forged" }]);
    f.receive([1, { ...READY, data: { ...READY.data, v: 2 } }]);
    f.receive([1, { ...READY, data: { v: 1, config: {} } }]);
    f.receive([0, {}]);
    f.receive([3, {}]);
    assert.equal(f.bridge.state, "starting");
    f.receive([1, READY]);
    assert.deepEqual(await startup, READY.data);
    assert.equal(f.bridge.state, "ready");
    assert.equal(f.timers.values.size, 0);
    await f.bridge.start();
    assert.equal(f.sent.length, 1);
    f.bridge.close();
});

test("READY validates optional user and CDN fields before completing startup", async () => {
    const f = fixture();
    const startup = f.bridge.start();
    const invalid = [
        { ...READY.data, config: { ...READY.data.config, cdn_host: null } },
        { ...READY.data, user: null },
        { ...READY.data, user: {} },
        { ...READY.data, user: { id: 1, username: "test", discriminator: "0" } },
        { ...READY.data, user: { id: "1", username: "test", discriminator: 0 } },
        { ...READY.data, user: { id: "1", username: "test", discriminator: "0", avatar: null } },
    ];
    for (const data of invalid) {
        f.receive([1, { ...READY, data }]);
        assert.equal(f.bridge.state, "starting");
    }
    const valid = { ...READY.data, config: { ...READY.data.config, cdn_host: "cdn.discordapp.com" },
        user: { id: "18446744073709551615", username: "test", discriminator: "0", avatar: "hash", future: true } };
    f.receive([1, { ...READY, data: valid }]);
    assert.deepEqual(await startup, valid);
    assert.equal(f.bridge.state, "ready");
    f.bridge.close();
});

test("startup deadlines, cancellation, and teardown settle all waiters without remaining ownership", async () => {
    for (const mode of ["timeout", "abort", "close", "hostClose"]) {
        const f = fixture();
        const controller = new AbortController();
        const startup = f.bridge.start({ signal: controller.signal, timeoutMs: 10 });
        const rejected = assert.rejects(startup, category(mode === "abort" ? "cancelled" : mode === "timeout" ? "timeout" : "closed"));
        if (mode === "timeout") f.timers.advance(10);
        if (mode === "abort") controller.abort();
        if (mode === "close") f.bridge.close();
        if (mode === "hostClose") f.receive([2, { code: 4000, message: "Host stopped" }]);
        await rejected;
        assert.equal(f.bridge.state, "closed");
        assert.equal(f.cleanups, 1);
        assert.equal(f.timers.values.size, 0);
        assert.equal(f.listening, false);
        await assert.rejects(f.bridge.start(), category(mode === "abort" ? "cancelled" : mode === "timeout" ? "timeout" : "closed"));
    }
    const f = fixture();
    const controller = new AbortController(); controller.abort();
    await assert.rejects(f.bridge.start({ signal: controller.signal }), category("cancelled"));
    assert.equal(f.bridge.state, "idle");
    assert.equal(f.sent.length, 0);
    await assert.rejects(f.bridge.start({ timeoutMs: 0 }), category("invalidConfiguration"));
});

test("synchronous host responses cannot race pending command registration", async () => {
    const f = fixture({ post(tuple, receive) {
        if (tuple[0] === 0) receive([1, READY]);
        if (tuple[0] === 1) receive([1, { ...tuple[1], data: { ok: true }, evt: null }]);
    } });
    await f.bridge.start();
    const response = await f.bridge.request("GET_USER", { id: "18446744073709551615" });
    assert.deepEqual(response.data, { ok: true });
    assert.equal(f.bridge.diagnostics.pending, 0);
    assert.equal(f.bridge.diagnostics.pendingBytes, 0);
    f.bridge.close();
});

test("nonce and command matching isolate out-of-order callers, stale replies, and repeated nonce factory output", async () => {
    const f = fixture({ nonceFactory: () => "repeated" }); await ready(f);
    const first = f.bridge.request("GET_USER", { id: "1" });
    const firstFrame = f.sent.at(-1).tuple[1];
    const second = f.bridge.request("GET_CHANNEL", { channel_id: "2" });
    const secondFrame = f.sent.at(-1).tuple[1];
    assert.notEqual(firstFrame.nonce, secondFrame.nonce);
    f.receive([1, { cmd: firstFrame.cmd, evt: null, nonce: secondFrame.nonce, data: "wrong-command" }]);
    f.receive([1, { cmd: secondFrame.cmd, evt: null, nonce: "unknown", data: "unknown" }]);
    assert.equal(f.bridge.diagnostics.pending, 2);
    f.receive([1, { cmd: secondFrame.cmd, evt: null, nonce: secondFrame.nonce, data: { second: true, future: 1 } }]);
    assert.deepEqual((await second).data, { second: true, future: 1 });
    f.receive([1, { cmd: firstFrame.cmd, evt: null, nonce: firstFrame.nonce, data: { first: true } }]);
    assert.deepEqual((await first).data, { first: true });
    const third = f.bridge.request("GET_USER", {});
    const thirdFrame = f.sent.at(-1).tuple[1];
    f.receive([1, { cmd: firstFrame.cmd, evt: null, nonce: firstFrame.nonce, data: "late" }]);
    assert.equal(f.bridge.diagnostics.pending, 1);
    f.receive([1, { cmd: thirdFrame.cmd, evt: null, nonce: thirdFrame.nonce, data: null }]);
    assert.equal((await third).data, null);
    f.bridge.close();
});

test("request cancellation before/during work and timeout release accounting and ignore late replies", async () => {
    const f = fixture();
    await assert.rejects(f.bridge.request("GET_USER"), category("notReady"));
    await ready(f);
    const controller = new AbortController(); controller.abort();
    await assert.rejects(f.bridge.request("GET_USER", {}, { signal: controller.signal }), category("cancelled"));
    assert.equal(f.sent.length, 1);
    const during = new AbortController();
    const cancelled = f.bridge.request("GET_USER", {}, { signal: during.signal });
    const rejectCancelled = assert.rejects(cancelled, category("cancelled"));
    const wire = f.sent.at(-1).tuple[1];
    during.abort(); await rejectCancelled;
    const timed = f.bridge.request("GET_USER", {}, { timeoutMs: 10 });
    const rejectTimed = assert.rejects(timed, category("timeout"));
    f.timers.advance(10); await rejectTimed;
    f.receive([1, { cmd: wire.cmd, evt: null, nonce: wire.nonce, data: "late" }]);
    assert.equal(f.bridge.diagnostics.pending, 0);
    assert.equal(f.bridge.diagnostics.pendingBytes, 0);
    assert.equal(f.timers.values.size, 0);
    f.bridge.close();
});

test("RPC errors require matching command/nonce and retain the host numeric error code", async () => {
    const f = fixture(); await ready(f);
    const request = f.bridge.request("FUTURE_COMMAND", { nullable: null });
    const rejected = assert.rejects(request, (error) => category("rpc")(error) && error.rpcCode === 4002 && error.message === "Unsupported");
    acknowledge(f, { code: 4002, message: "Unsupported" }, { cmd: "WRONG", evt: "ERROR" });
    assert.equal(f.bridge.diagnostics.pending, 1);
    acknowledge(f, { code: 4002, message: "Unsupported" }, { evt: "ERROR" });
    await rejected;
    f.receive([1, { cmd: "FUTURE_COMMAND", evt: "ERROR", nonce: null, data: { code: 4001, message: "General error" } }]);
    assert.equal(f.bridge.takeEvents()[0].data.code, 4001);
    f.bridge.close();
});

test("published permission BigInts normalize to exact decimal strings without losing high bits", async () => {
    const f = fixture(); await ready(f);
    const request = f.bridge.request("GET_CHANNEL_PERMISSIONS");
    const permissions = (1n << 100n) | (1n << 53n) | 1n;
    acknowledge(f, { permissions, future: "kept" });
    assert.deepEqual((await request).data, { permissions: permissions.toString(), future: "kept" });
    assert.equal(f.bridge.state, "ready");
    f.bridge.close();
});

test("pending count/byte/frame and JSON validation bounds reject admission without sending", async () => {
    const f = fixture({ limits: { maxPending: 1, maxFrameBytes: 400, maxPendingBytes: 400 } }); await ready(f);
    const request = f.bridge.request("ONE");
    const rejected = assert.rejects(request, category("closed"));
    await assert.rejects(f.bridge.request("TWO"), category("capacity"));
    assert.equal(f.sent.length, 2);
    f.bridge.close(); await rejected;
    const g = fixture({ limits: { maxFrameBytes: 400, maxPendingBytes: 300 } }); await ready(g);
    await assert.rejects(g.bridge.request("BIG", { x: "é".repeat(500) }), category("capacity"));
    const cycle = {}; cycle.self = cycle;
    for (const args of [{ invalid: undefined }, { invalid: NaN }, { invalid: 1n }, cycle]) await assert.rejects(g.bridge.request("INVALID", args));
    await assert.rejects(g.bridge.request(""), category("invalidName"));
    await assert.rejects(g.bridge.request("ONE", {}, { evt: "" }), category("invalidName"));
    await assert.rejects(g.bridge.request("ONE", {}, { timeoutMs: 2147483648 }), category("invalidConfiguration"));
    assert.equal(g.bridge.diagnostics.pending, 0);
    assert.equal(g.sent.length, 1);
    g.bridge.close();
});

test("standalone command JSON rejects unsafe integer-valued numbers before admission", async () => {
    const f = fixture(); await ready(f);
    for (const value of [9007199254740992, -9007199254740992, 1e100, Infinity, -Infinity, NaN]) {
        await assert.rejects(f.bridge.request("FUTURE_COMMAND", { value }), category("invalidFrame"));
        assert.equal(f.sent.length, 1);
    }
    const request = f.bridge.request("FUTURE_COMMAND", { fraction: 0.125, positive: Number.MAX_SAFE_INTEGER, negative: Number.MIN_SAFE_INTEGER });
    assert.deepEqual(f.sent.at(-1).tuple[1].args, { fraction: 0.125, positive: Number.MAX_SAFE_INTEGER, negative: Number.MIN_SAFE_INTEGER });
    acknowledge(f, { fraction: 0.125 });
    assert.deepEqual((await request).data, { fraction: 0.125 });
    f.bridge.close();
});

test("teardown rejects concurrent commands, clears all resources, and remains idempotent", async () => {
    const f = fixture(); await ready(f);
    const first = assert.rejects(f.bridge.request("ONE"), category("closed"));
    const second = assert.rejects(f.bridge.request("TWO"), category("closed"));
    const subscription = assert.rejects(f.bridge.subscribe("FUTURE_EVENT", {}, () => {}), category("closed"));
    f.bridge.close(1000, "Finished");
    f.bridge.close();
    await Promise.all([first, second, subscription]); await settle();
    assert.deepEqual(f.bridge.diagnostics, { state: "closed", pending: 0, pendingBytes: 0, subscriptions: 0, listeners: 0, queuedEvents: 0, queuedEventBytes: 0 });
    assert.equal(f.cleanups, 1);
    assert.equal(f.timers.values.size, 0);
    await assert.rejects(f.bridge.request("THREE"), category("closed"));
    await assert.rejects(f.bridge.subscribe("EVENT", {}, () => {}), category("closed"));
});

test("duplicate subscriptions canonicalize arguments and perform one upstream subscribe/final unsubscribe", async () => {
    const f = fixture(); await ready(f);
    const delivered = [];
    const one = f.bridge.subscribe("FUTURE_EVENT", { b: 2, a: 1 }, (data) => { delivered.push(["one", data]); data.mutated = true; });
    const two = f.bridge.subscribe("FUTURE_EVENT", { a: 1, b: 2 }, (data) => delivered.push(["two", data]));
    assert.equal(f.sent.filter((x) => x.tuple[1].cmd === "SUBSCRIBE").length, 1);
    acknowledge(f, {}, { evt: "WRONG" });
    assert.equal(f.bridge.diagnostics.pending, 1);
    acknowledge(f, {}, { data: { evt: "WRONG" } });
    assert.equal(f.bridge.diagnostics.pending, 1);
    acknowledge(f);
    const [first, second] = await Promise.all([one, two]); await settle();
    f.receive([1, { cmd: "DISPATCH", evt: "FUTURE_EVENT", nonce: null, data: { value: 5 } }]);
    assert.deepEqual(delivered, [["one", { value: 5, mutated: true }], ["two", { value: 5 }]]);
    assert.deepEqual(f.bridge.takeEvents()[0].data, { value: 5 });
    await first.unsubscribe();
    assert.equal(f.sent.length, 2);
    const released = second.unsubscribe();
    assert.equal(f.sent.at(-1).tuple[1].cmd, "UNSUBSCRIBE");
    acknowledge(f); await released;
    await second.unsubscribe();
    assert.equal(f.bridge.diagnostics.listeners, 0);
    assert.equal(f.bridge.diagnostics.subscriptions, 0);
    f.bridge.close();
});

test("cancellation of one pending subscriber preserves another and no listeners leak", async () => {
    const f = fixture(); await ready(f);
    const controller = new AbortController();
    const first = f.bridge.subscribe("EVENT", {}, () => {}, { signal: controller.signal });
    const rejected = assert.rejects(first, category("cancelled"));
    const second = f.bridge.subscribe("EVENT", {}, () => {});
    controller.abort(); await rejected;
    assert.equal(f.bridge.diagnostics.listeners, 1);
    acknowledge(f); const handle = await second; await settle();
    const released = handle.unsubscribe(); acknowledge(f); await released;
    assert.equal(f.sent.filter((x) => x.tuple[1].cmd === "SUBSCRIBE").length, 1);
    assert.equal(f.bridge.diagnostics.subscriptions, 0);
    f.bridge.close();
});

test("cancel final subscriber during SUBSCRIBE waits for ack and then sends exactly one UNSUBSCRIBE", async () => {
    const f = fixture(); await ready(f);
    const controller = new AbortController();
    const subscribed = f.bridge.subscribe("EVENT", {}, () => {}, { signal: controller.signal });
    const rejected = assert.rejects(subscribed, category("cancelled"));
    controller.abort(); await rejected;
    assert.equal(f.sent.length, 2);
    acknowledge(f); await settle();
    assert.equal(f.sent.at(-1).tuple[1].cmd, "UNSUBSCRIBE");
    acknowledge(f); await settle();
    assert.equal(f.bridge.diagnostics.subscriptions, 0);
    assert.equal(f.bridge.diagnostics.listeners, 0);
    f.bridge.close();
});

test("subscribe during final UNSUBSCRIBE serializes a replacement without returning a stale active handle", async () => {
    const f = fixture(); await ready(f);
    const first = f.bridge.subscribe("EVENT", {}, () => {}); acknowledge(f);
    const handle = await first; await settle();
    const released = handle.unsubscribe();
    const second = f.bridge.subscribe("EVENT", {}, () => {});
    assert.equal(f.sent.at(-1).tuple[1].cmd, "UNSUBSCRIBE");
    acknowledge(f); await settle();
    assert.equal(f.sent.at(-1).tuple[1].cmd, "SUBSCRIBE");
    acknowledge(f);
    const replacement = await second; await released; await settle();
    const finalRelease = replacement.unsubscribe(); acknowledge(f); await finalRelease;
    assert.deepEqual(f.sent.filter((x) => x.tuple[0] === 1).map((x) => x.tuple[1].cmd), ["SUBSCRIBE", "UNSUBSCRIBE", "SUBSCRIBE", "UNSUBSCRIBE"]);
    f.bridge.close();
});

test("never-ack subscribe expires, closes ambiguous remote state, and rejects every subscriber", async () => {
    const f = fixture(); await ready(f);
    const first = assert.rejects(f.bridge.subscribe("EVENT", {}, () => {}, { timeoutMs: 5 }), category("timeout"));
    const second = assert.rejects(f.bridge.subscribe("EVENT", {}, () => {}), category("timeout"));
    f.timers.advance(5); await Promise.all([first, second]); await settle();
    assert.equal(f.bridge.state, "closed");
    assert.equal(f.bridge.diagnostics.listeners, 0);
    assert.equal(f.bridge.diagnostics.pending, 0);
    assert.equal(f.timers.values.size, 0);
});

test("subscription capacity, invalid callbacks, and already-aborted consumers reject without retention", async () => {
    const f = fixture({ limits: { maxListeners: 2, maxSubscriptions: 1 } }); await ready(f);
    const controller = new AbortController(); controller.abort();
    await assert.rejects(f.bridge.subscribe("EVENT", {}, () => {}, { signal: controller.signal }), category("cancelled"));
    for (const name of ["READY", "ERROR"]) await assert.rejects(f.bridge.subscribe(name, {}, () => {}), category("invalidSubscription"));
    await assert.rejects(f.bridge.subscribe("EVENT", {}, null), category("invalidSubscription"));
    const one = f.bridge.subscribe("EVENT", {}, () => {}); acknowledge(f); const first = await one; await settle();
    await assert.rejects(f.bridge.subscribe("OTHER", {}, () => {}), category("capacity"));
    const second = await f.bridge.subscribe("EVENT", {}, () => {});
    await assert.rejects(f.bridge.subscribe("EVENT", {}, () => {}), category("capacity"));
    await first.unsubscribe();
    const released = second.unsubscribe(); acknowledge(f); await released;
    f.bridge.close();
});

test("listener exceptions are isolated; unknown events retain order and count/byte overflow closes", async () => {
    const f = fixture({ limits: { maxQueuedEvents: 2 } }); await ready(f);
    let calls = 0;
    const one = f.bridge.subscribe("EVENT", {}, () => { throw new Error("Consumer failure"); });
    const two = f.bridge.subscribe("EVENT", {}, () => { calls++; });
    acknowledge(f); await Promise.all([one, two]); await settle();
    f.receive([1, { cmd: "DISPATCH", evt: "EVENT", nonce: null, data: {} }]);
    f.receive([1, { cmd: "DISPATCH", evt: "FUTURE_EVENT", nonce: null, data: { value: null } }]);
    assert.equal(calls, 1);
    assert.deepEqual(f.bridge.takeEvents().map((x) => x.evt), ["EVENT", "FUTURE_EVENT"]);
    assert.equal(f.bridge.diagnostics.queuedEventBytes, 0);
    for (let index = 0; index < 3; index++) f.receive([1, { cmd: "DISPATCH", evt: "EVENT", nonce: null, data: {} }]);
    assert.equal(f.bridge.state, "closed");
    assert.equal(f.bridge.diagnostics.queuedEvents, 0);
    const g = fixture({ limits: { maxQueuedEventBytes: 20 } }); await ready(g);
    g.receive([1, { cmd: "DISPATCH", evt: "EVENT", nonce: null, data: {} }]);
    assert.equal(g.bridge.state, "closed");
});

test("authenticated malformed/oversized frames terminate but unauthenticated malformed messages are ignored", async () => {
    for (const malformed of ["text", [1], [9, {}], [1, {}], [2, { code: "bad", message: "bad" }], [1, { cmd: "X", data: Infinity }]]) {
        const f = fixture(); await ready(f);
        f.receive(malformed, { source: {} }); assert.equal(f.bridge.state, "ready");
        f.receive(malformed); assert.equal(f.bridge.state, "closed");
        assert.equal(f.timers.values.size, 0);
    }
    const f = fixture({ limits: { maxFrameBytes: 400 } }); await ready(f);
    f.receive([1, { cmd: "DISPATCH", evt: "EVENT", nonce: null, data: { text: "é".repeat(400) } }]);
    assert.equal(f.bridge.state, "closed");
});

test("transport installation/send failures settle startup and command cleanup deterministically", async () => {
    const failedListen = fixture({ listen() { throw new Error("Unable to attach"); } });
    await assert.rejects(failedListen.bridge.start(), category("transport"));
    assert.equal(failedListen.timers.values.size, 0);
    const failedSend = fixture({ post() { throw new Error("Unable to send"); } });
    await assert.rejects(failedSend.bridge.start(), category("transport"));
    assert.equal(failedSend.cleanups, 1);
    const f = fixture({ post(tuple) { if (tuple[0] === 1) throw new Error("Command send failed"); } }); await ready(f);
    await assert.rejects(f.bridge.request("COMMAND"), category("transport"));
    assert.equal(f.bridge.diagnostics.pendingBytes, 0);
    assert.equal(f.timers.values.size, 0);
    f.bridge.close();
    assert.throws(() => fixture().bridge.close(-1), category("invalidClose"));
});

test("window transport installs only on listen, removes once, and posts to exact origins", () => {
    const listeners = [];
    const removed = [];
    const messages = [];
    const window = { addEventListener(...args) { listeners.push(args); }, removeEventListener(...args) { removed.push(args); } };
    const source = { postMessage(...args) { messages.push(args); } };
    const transport = createWindowTransport(window, source);
    assert.equal(listeners.length, 0);
    const listener = () => {};
    const cleanup = transport.listen(listener);
    assert.deepEqual(listeners, [["message", listener]]);
    transport.post([0, {}], ORIGIN);
    assert.deepEqual(messages, [[[0, {}], ORIGIN]]);
    assert.throws(() => transport.post([0, {}], "*"), category("invalidOrigin"));
    cleanup(); cleanup();
    assert.deepEqual(removed, [["message", listener]]);
    assert.throws(() => createWindowTransport({}, source), category("invalidTransport"));
});

test("raw Swift/browser transport stays inert until start and authenticates before delivering UTF-8 bytes", () => {
    const listeners = new Set();
    const messages = [];
    const frames = [];
    const closed = [];
    const source = { postMessage(...args) { messages.push(args); } };
    const window = { addEventListener(_event, listener) { listeners.add(listener); }, removeEventListener(_event, listener) { listeners.delete(listener); } };
    const raw = createActivityTransport({ activityWindow: window, trustedSource: source, hostOrigin: ORIGIN, allowedOrigins: [ORIGIN] });
    const bytes = new TextEncoder().encode(JSON.stringify([0, { v: 1, label: "é" }]));
    assert.equal(listeners.size, 0);
    assert.throws(() => raw.send(bytes), category("invalidState"));
    raw.start((frame) => frames.push(frame), (error) => closed.push(error));
    assert.equal(listeners.size, 1);
    assert.throws(() => raw.start(() => {}, () => {}), category("invalidState"));
    raw.send(bytes);
    assert.deepEqual(messages, [[[0, { v: 1, label: "é" }], ORIGIN]]);
    const receiver = [...listeners][0];
    receiver({ source: {}, origin: ORIGIN, data: [1, READY] });
    receiver({ source, origin: "https://evil.example", data: [1, READY] });
    receiver({ source, origin: ORIGIN, data: [1, READY] });
    assert.equal(frames.length, 1);
    assert.ok(frames[0] instanceof Uint8Array);
    assert.deepEqual(JSON.parse(new TextDecoder().decode(frames[0])), [1, READY]);
    receiver({ source, origin: ORIGIN, data: [1, { cmd: "GET_CHANNEL_PERMISSIONS", evt: null, nonce: "n", data: { permissions: (1n << 100n) | 1n } }] });
    assert.equal(JSON.parse(new TextDecoder().decode(frames[1]))[1].data.permissions, ((1n << 100n) | 1n).toString());
    for (const invalid of [new Uint8Array([0xff]), new TextEncoder().encode("not-json"), new TextEncoder().encode("[1,2]")]) assert.throws(() => raw.send(invalid), category("invalidFrame"));
    for (const number of ["1e1000", "-1e1000", "9007199254740993", "-9007199254740993"]) {
        assert.throws(() => raw.send(new TextEncoder().encode(`[1,{"cmd":"FUTURE_COMMAND","args":{"number":${number}}}]`)), category("invalidFrame"));
        assert.equal(messages.length, 1);
    }
    raw.close(); raw.close();
    assert.equal(listeners.size, 0);
    assert.equal(closed.length, 1);
    assert.equal(closed[0].code, "closed");
    assert.throws(() => raw.send(bytes), category("invalidState"));
});

test("raw adapter bounds frames and informs the Swift read owner once on invalid authenticated input", () => {
    for (const malformed of ["text", [1, { huge: "é".repeat(200) }], [1, { invalid: Infinity }]]) {
        let receiver;
        let removed = 0;
        const errors = [];
        const source = { postMessage() {} };
        const window = { addEventListener(_event, listener) { receiver = listener; }, removeEventListener() { removed++; } };
        const raw = createActivityTransport({ activityWindow: window, trustedSource: source, hostOrigin: ORIGIN, allowedOrigins: [ORIGIN], maxFrameBytes: 200 });
        raw.start(() => assert.fail("Malformed frames cannot reach Swift"), (error) => errors.push(error));
        assert.throws(() => raw.send(new Uint8Array(201)), category("capacity"));
        receiver({ source: {}, origin: ORIGIN, data: malformed });
        assert.equal(errors.length, 0);
        receiver({ source, origin: ORIGIN, data: malformed });
        receiver({ source, origin: ORIGIN, data: malformed });
        assert.equal(errors.length, 1);
        assert.equal(removed, 1);
    }
    assert.throws(() => createActivityTransport({ activityWindow: {}, trustedSource: {}, hostOrigin: ORIGIN, allowedOrigins: [] }), category("invalidOrigin"));
    assert.throws(() => createActivityTransport({ activityWindow: {}, trustedSource: {}, hostOrigin: ORIGIN, allowedOrigins: ["https://other.example"] }), category("invalidOrigin"));
});
