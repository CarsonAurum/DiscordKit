import test from "node:test";
import assert from "node:assert/strict";
import { ActivityURLMapper, createActivityFetch, createActivityWebSocket } from "./ActivityNetwork.mjs";

const ACTIVITY = "https://123.discordsays.com";

/** Creates a deterministic proxy table that exercises host, target path, and variable boundaries. */
function mapper() {
    return new ActivityURLMapper({ activityOrigin: ACTIVITY, mappings: [
        { prefix: "/api", target: "api.example.com/v1" },
        { prefix: "/assets", target: "cdn.example.com" },
        { prefix: "/tenant/{tenant}", target: "{tenant}.example.net/api" },
        { prefix: "/port", target: "localhost:8443" },
    ] });
}

test("mapping preserves query, path, and trailing slash while using the Activity proxy origin", () => {
    const urls = mapper();
    for (const [input, output] of [
        ["https://api.example.com/v1/users?limit=2&name=a%20b", `${ACTIVITY}/api/users?limit=2&name=a%20b`],
        ["https://api.example.com/v1", `${ACTIVITY}/api/`],
        ["https://api.example.com/v1/", `${ACTIVITY}/api/`],
        ["https://cdn.example.com/image%20name.png", `${ACTIVITY}/assets/image%20name.png`],
        ["https://cdn.example.com/", `${ACTIVITY}/assets/`],
        ["https://some-tenant.example.net/api/item", `${ACTIVITY}/tenant/some-tenant/item`],
        ["http://localhost:8443/file", `${ACTIVITY}/port/file`],
        ["/local?value=1", `${ACTIVITY}/local?value=1`],
        ["relative", `${ACTIVITY}/relative`],
        [`${ACTIVITY}/assets/already.png`, `${ACTIVITY}/assets/already.png`],
        ["wss://api.example.com/v1/live", "wss://123.discordsays.com/api/live"],
        ["ws://cdn.example.com/socket", "wss://123.discordsays.com/assets/socket"],
    ]) assert.equal(urls.map(input).href, output);
    const original = new URL("https://cdn.example.com/image.png");
    urls.map(original);
    assert.equal(original.href, "https://cdn.example.com/image.png");
    const local = new ActivityURLMapper({ activityOrigin: "http://localhost:3333", mappings: [{ prefix: "/", target: "upstream.example" }] });
    assert.equal(local.map("wss://upstream.example/socket").href, "ws://localhost:3333/socket");
});

test("host and path matching require exact boundaries, escaped literals, and explicit mappings", () => {
    const urls = mapper();
    for (const input of [
        "https://api.example.com.evil.test/v1/user", "https://evil-api.example.com/v1/user",
        "https://apiXexampleXcom/v1/user", "https://api.example.com:8443/v1/user",
        "https://api.example.com/v10/user", "https://api.example.com/other/v1/user",
        "https://example.net/api/user", "https://one.two.example.net/api/user",
        "https://bad_tenant.example.net/api/user", "https://-tenant.example.net/api/user",
        "https://localhost:8444/file", "https://unmapped.example/file",
    ]) assert.throws(() => urls.map(input), TypeError, input);
    const firstWins = new ActivityURLMapper({ activityOrigin: ACTIVITY, mappings: [{ target: "api.example.com", prefix: "/one" }, { target: "api.example.com", prefix: "/two" }] });
    assert.equal(firstWins.map("https://api.example.com/item").pathname, "/one/item");
});

test("unsafe schemes, credentials, fragments, encoded separators, and proxy escape attempts fail", () => {
    const urls = mapper();
    for (const input of [
        "javascript:alert(1)", "data:text/plain,abc", "file:///private/file", "ftp://cdn.example.com/file",
        "https://user:password@cdn.example.com/file", "https://cdn.example.com/file#fragment",
        "https://cdn.example.com/a%2Fb", "https://cdn.example.com/a%5cb",
        "https://cdn.example.com/a%252Fb", "https://cdn.example.com/%252e%252e/escape",
        "https://cdn.example.com/a%00b", "https://cdn.example.com/a//b",
        "https://cdn.example.com/" + "x".repeat(16384),
    ]) assert.throws(() => urls.map(input), TypeError, input);
    assert.equal(urls.map("https://cdn.example.com/100%25.png").href, `${ACTIVITY}/assets/100%25.png`);
    assert.equal(urls.map("https://cdn.example.com/a%20b").href, `${ACTIVITY}/assets/a%20b`);
});

test("route compilation rejects invalid origins, malformed routes, traversal, and unmatched variables", () => {
    for (const activityOrigin of ["*", "null", `${ACTIVITY}/`, `${ACTIVITY}/path`, "https://user@123.discordsays.com", "file://host"]) assert.throws(() => new ActivityURLMapper({ activityOrigin, mappings: [] }));
    assert.throws(() => new ActivityURLMapper({ activityOrigin: ACTIVITY, mappings: new Array(129).fill({ target: "foo.example", prefix: "/foo" }) }));
    for (const route of [
        { prefix: "api", target: "example.com" }, { prefix: "//evil.com", target: "example.com" },
        { prefix: "/api", target: "https://example.com" }, { prefix: "/api", target: "user@example.com" },
        { prefix: "/api", target: "example.com/path?query=1" }, { prefix: "/api", target: "example.com/../escape" },
        { prefix: "/../api", target: "example.com" }, { prefix: "/%2e%2e/api", target: "example.com" },
        { prefix: "/api/", target: "example.com" }, { prefix: "/api", target: "example.com/path/" },
        { prefix: "/api/{other}", target: "{tenant}.example.com" }, { prefix: "/api", target: "{tenant}.example.com" },
        { prefix: "/api/{tenant}", target: "x{tenant}.example.com" }, { prefix: "/api/{tenant}", target: "{tenant}.{tenant}.example.com" },
        { prefix: "/{broken", target: "example.com" }, { prefix: "/api", target: "example.com\\evil" },
        { prefix: "/api", target: "example.com:443" },
    ]) assert.throws(() => new ActivityURLMapper({ activityOrigin: ACTIVITY, mappings: [route] }), TypeError, JSON.stringify(route));
});

test("fetch URL input uses explicit adapters and preserves init without global mutation", async () => {
    const nativeFetch = globalThis.fetch;
    const calls = [];
    const response = { status: 200 };
    const fetch = createActivityFetch(mapper(), async (...args) => { calls.push(args); return response; });
    assert.equal(calls.length, 0);
    const init = { headers: { Accept: "application/json" } };
    assert.equal(await fetch("https://api.example.com/v1/users", init), response);
    assert.equal(calls[0][0].href, `${ACTIVITY}/api/users`);
    assert.equal(calls[0][1], init);
    assert.equal(globalThis.fetch, nativeFetch);
    await assert.rejects(fetch("https://unmapped.example"), TypeError);
    assert.equal(calls.length, 1);
    assert.throws(() => createActivityFetch({}, () => {}), TypeError);
});

test("fetch Request mapping preserves streaming body, method, headers, signal, and explicit overrides", async () => {
    const requests = [];
    const fetch = createActivityFetch(mapper(), async (request) => { requests.push(request); return { body: await request.text() }; });
    const controller = new AbortController();
    const request = new Request("https://api.example.com/v1/items", {
        method: "POST", body: "original", headers: { "content-type": "text/plain", "x-original": "yes" }, signal: controller.signal,
    });
    const response = await fetch(request, { body: "replacement", headers: { "x-override": "yes" }, credentials: "omit" });
    assert.equal(response.body, "replacement");
    assert.equal(requests[0].url, `${ACTIVITY}/api/items`);
    assert.equal(requests[0].method, "POST");
    assert.equal(requests[0].headers.get("x-override"), "yes");
    assert.equal(requests[0].headers.get("x-original"), null);
    assert.equal(requests[0].credentials, "omit");
    controller.abort();
    assert.equal(requests[0].signal.aborted, true);
    assert.equal(await request.text(), "original");
    const stream = new ReadableStream({ start(controller) { controller.enqueue(new TextEncoder().encode("streamed")); controller.close(); } });
    const streaming = new Request("https://api.example.com/v1/upload", { method: "PUT", body: stream, duplex: "half" });
    assert.equal((await fetch(streaming)).body, "streamed");
    const get = new Request("https://api.example.com/v1/items");
    assert.equal((await fetch(get)).body, "");
});

test("network adapter failures propagate and WebSocket mapping preserves protocol lists lazily", async () => {
    const expected = new Error("Network unavailable");
    const fetch = createActivityFetch(mapper(), async () => { throw expected; });
    await assert.rejects(fetch("https://api.example.com/v1/items"), (error) => error === expected);
    const calls = [];
    class Socket {
        /** Captures construction without opening real network resources. */
        constructor(...args) { calls.push(args); }
    }
    const nativeSocket = globalThis.WebSocket;
    const connect = createActivityWebSocket(mapper(), Socket);
    assert.equal(calls.length, 0);
    assert.ok(connect("wss://api.example.com/v1/live", ["json"]) instanceof Socket);
    connect(new URL("ws://cdn.example.com/live"));
    assert.equal(calls[0][0].href, "wss://123.discordsays.com/api/live");
    assert.deepEqual(calls[0][1], ["json"]);
    assert.equal(calls[1].length, 1);
    assert.equal(globalThis.WebSocket, nativeSocket);
    assert.throws(() => connect("https://api.example.com/v1/live"), TypeError);
    assert.throws(() => connect("wss://unmapped.example/live"), TypeError);
    assert.throws(() => createActivityWebSocket(mapper(), null), TypeError);
});
