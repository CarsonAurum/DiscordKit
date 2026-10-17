/** Safe, explicit Activity proxy URL mapping and injected networking; no globals are patched. */
export class ActivityURLMapper {
    #origin; #routes;

    /**
     * Compiles a bounded deterministic mapping table. Targets use developer-portal host/path syntax,
     * e.g. `api.example.com/v1`, and prefixes use Activity paths, e.g. `/api`. Whole DNS-label variables
     * such as `{tenant}.example.com` may be repeated in the prefix. Matching is anchored to the entire
     * host and target-path boundary; dots and other regex characters never acquire regex semantics.
     * @param {object} options Origin and ordered routes; first matching route wins.
     * @param {string} options.activityOrigin Explicit HTTPS Activity origin (HTTP permitted for local peers).
     * @param {Array<{prefix: string, target: string}>} options.mappings Up to 128 bounded routes.
     * @throws {TypeError} Invalid origin, ambiguous variables, credentials, traversal, or unsafe paths.
     */
    constructor({ activityOrigin, mappings }) {
        const origin = new URL(activityOrigin);
        if (!["https:", "http:"].includes(origin.protocol) || activityOrigin !== origin.origin || origin.username || origin.password) throw new TypeError("Expected an exact Activity web origin");
        if (!Array.isArray(mappings) || mappings.length > 128) throw new TypeError("Expected at most 128 URL mappings");
        this.#origin = origin;
        this.#routes = mappings.map(compileRoute);
    }

    /**
     * Maps one HTTP(S)/WS(S) resource into the configured Activity proxy origin. Relative and already
     * proxied URLs remain local. Unmapped external URLs throw rather than silently bypassing the proxy.
     * URL credentials, fragments, encoded path separators, and traversal are rejected. Query parameters
     * are preserved exactly; callers must keep secrets out of URLs. No network request is performed.
     * @param {string|URL} input Resource URL, or relative path resolved against the Activity origin.
     * @returns {URL} Independent URL; HTTP resources use the Activity web scheme and sockets use WS/WSS.
     * @throws {TypeError} Unsupported scheme, unsafe path/credentials, oversized URL, or unmapped host.
     */
    map(input) {
        const raw = input instanceof URL ? input.href : input;
        if (typeof raw !== "string" || new TextEncoder().encode(raw).byteLength > 16384) throw new TypeError("Expected a bounded URL");
        const url = new URL(raw, this.#origin);
        if (!["http:", "https:", "ws:", "wss:"].includes(url.protocol) || url.username || url.password || url.hash) throw new TypeError("Unsafe Activity network URL");
        safePath(url.pathname);
        const socket = url.protocol === "ws:" || url.protocol === "wss:";
        const localProtocol = socket ? (this.#origin.protocol === "https:" ? "wss:" : "ws:") : this.#origin.protocol;
        if (url.host === this.#origin.host) {
            url.protocol = localProtocol;
            return url;
        }
        for (const route of this.#routes) {
            const match = route.host.exec(url.host);
            if (!match || (route.path !== "/" && url.pathname !== route.path && !url.pathname.startsWith(`${route.path}/`))) continue;
            const prefix = route.prefix.replace(/\{([a-z][a-z0-9_]*)\}/g, (_whole, name) => match.groups[name]);
            const suffix = route.path === "/" ? url.pathname : url.pathname.slice(route.path.length);
            const result = new URL(this.#origin);
            result.protocol = localProtocol;
            result.pathname = `${prefix === "/" ? "" : prefix}${suffix.startsWith("/") ? suffix : `/${suffix}`}` || "/";
            result.search = url.search;
            return result;
        }
        throw new TypeError("External URL has no Activity proxy mapping");
    }
}

/**
 * Creates a fetch helper around an explicit mapper and injected fetch. String/URL inputs preserve init.
 * Request inputs preserve streaming bodies, headers, method, credentials, signal, and init overrides via
 * the native Request constructor; bodies are never converted into unbounded blobs or prebuffered.
 * The helper performs no I/O until invoked and does not alter global fetch or Request prototypes.
 * @param {ActivityURLMapper} mapper Compiled deployment-specific proxy mappings.
 * @param {Function} fetchImpl Injected fetch implementation bound to its owning host if required.
 * @param {typeof Request} [RequestType=globalThis.Request] Injected native Request constructor.
 * @returns {Function} Async fetch-compatible function; proxy or native failures propagate unchanged.
 */
export function createActivityFetch(mapper, fetchImpl, RequestType = globalThis.Request) {
    if (!(mapper instanceof ActivityURLMapper) || typeof fetchImpl !== "function" || typeof RequestType !== "function") throw new TypeError("Expected mapper, fetch, and Request adapters");
    return async (input, init) => {
        if (input instanceof RequestType) {
            const url = mapper.map(input.url);
            const effective = new RequestType(input, init);
            const mapped = new RequestType(url, effective);
            return fetchImpl(mapped);
        }
        return fetchImpl(mapper.map(input), init);
    };
}

/**
 * Creates an explicit WebSocket factory with proxy mapping and protocol forwarding. No sockets are
 * created until invoked; close, event delivery, backpressure, and buffering belong to the injected
 * WebSocket implementation and caller. No global WebSocket or XHR patching occurs.
 * @param {ActivityURLMapper} mapper Deployment URL mapper; only WS/WSS input is accepted.
 * @param {Function} WebSocketType Injected native WebSocket constructor.
 * @returns {Function} `(url, protocols?) => WebSocket` factory; native failures propagate.
 */
export function createActivityWebSocket(mapper, WebSocketType) {
    if (!(mapper instanceof ActivityURLMapper) || typeof WebSocketType !== "function") throw new TypeError("Expected mapper and WebSocket adapter");
    return (input, protocols) => {
        const raw = input instanceof URL ? input : new URL(input);
        if (!["ws:", "wss:"].includes(raw.protocol)) throw new TypeError("Expected a WebSocket URL");
        const url = mapper.map(raw);
        return protocols === undefined ? new WebSocketType(url) : new WebSocketType(url, protocols);
    };
}

/** Compiles one route using escaped literal host text and whole-label named substitutions only. */
function compileRoute(mapping) {
    if (!mapping || typeof mapping.target !== "string" || typeof mapping.prefix !== "string" || mapping.target.length > 2048 || mapping.prefix.length > 2048) throw new TypeError("Expected bounded prefix and target strings");
    const { target, prefix } = mapping;
    if (!target || /[?#@\\\s]/.test(target) || target.includes("://") || !prefix.startsWith("/") || prefix.startsWith("//") || /[?#\\]/.test(prefix)) throw new TypeError("Unsafe mapping target or prefix");
    const slash = target.indexOf("/");
    const targetHost = slash === -1 ? target : target.slice(0, slash);
    const path = slash === -1 ? "/" : target.slice(slash);
    safePath(path);
    safePath(prefix.replace(/\{[a-z][a-z0-9_]*\}/g, "variable"));
    if (path.length > 1 && path.endsWith("/")) throw new TypeError("Target path must omit trailing slash");
    if (prefix.length > 1 && prefix.endsWith("/")) throw new TypeError("Prefix must omit trailing slash");
    const names = new Set();
    const hostParts = targetHost.split(".").map((part) => {
        const variable = /^\{([a-z][a-z0-9_]*)\}$/.exec(part);
        if (!variable) {
            if (/[{}]/.test(part)) throw new TypeError("Host variables must occupy an entire DNS label");
            return escapeRegex(part.toLowerCase());
        }
        if (names.has(variable[1])) throw new TypeError("Repeated target variable");
        names.add(variable[1]);
        return `(?<${variable[1]}>[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)`;
    });
    const validationHost = targetHost.replace(/\{[a-z][a-z0-9_]*\}/g, "variable");
    const validation = new URL(`https://${validationHost}`);
    if (validation.host !== validationHost.toLowerCase() || validation.pathname !== "/" || validation.search || validation.hash) throw new TypeError("Target must be a canonical host and optional port");
    const prefixNames = [...prefix.matchAll(/\{([a-z][a-z0-9_]*)\}/g)].map((match) => match[1]);
    if (/[{}]/.test(prefix.replace(/\{[a-z][a-z0-9_]*\}/g, "")) || prefixNames.some((name) => !names.has(name)) || [...names].some((name) => !prefixNames.includes(name))) throw new TypeError("Target and prefix variables must correspond");
    return { host: new RegExp(`^${hostParts.join("\\.")}$`, "i"), path, prefix };
}

/** Escapes all regex metacharacters before interpreting developer-supplied literal host segments. */
function escapeRegex(value) { return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"); }

/** Rejects literal/encoded traversal and separators, including multiply encoded forms, before mapping. */
function safePath(path) {
    if (path.includes("\\") || path.includes("//")) throw new TypeError("Unsafe mapping path");
    for (const segment of path.split("/")) {
        let decoded = segment;
        for (let pass = 0; pass < 5; pass++) {
            if (decoded === "." || decoded === ".." || /[/\\\x00-\x1f\x7f]/.test(decoded)) throw new TypeError("Unsafe path segment");
            if (!/%[0-9a-f]{2}/i.test(decoded)) break;
            if (pass === 4) throw new TypeError("Excessively encoded path segment");
            try { decoded = decodeURIComponent(decoded); } catch { throw new TypeError("Malformed path encoding"); }
        }
    }
}
