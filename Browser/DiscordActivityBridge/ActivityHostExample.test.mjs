// File: Browser/DiscordActivityBridge/ActivityHostExample.test.mjs
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import test from "node:test";
import assert from "node:assert/strict";

let moduleID = 0;

/**
 * Loads the real browser entry module against an injected DOM, authenticated message peer and backend.
 * No browser, credentials, external package, server, or real network call is involved. The referrer
 * getter throws to prove that explicit deployment configuration is the only source of origin trust.
 */
async function example({ clientId = "123", hostOrigin = "https://discord.com", backendOK = true } = {}) {
    const saved = Object.fromEntries(["window", "document", "fetch"].map((key) => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
    const sent = [];
    const exchanges = [];
    const listeners = new Map();
    const statusWaiters = [];
    let text = "Waiting for a Discord Activity host.";
    const status = {
        /** Returns the visible example status without requiring a DOM implementation. */
        get textContent() { return text; },
        /** Records rendering and releases exact-status barriers without polling or sleeping. */
        set textContent(value) {
            text = value;
            for (let index = statusWaiters.length - 1; index >= 0; index--) {
                if (statusWaiters[index].expected === value) statusWaiters.splice(index, 1)[0].resolve();
            }
        },
    };
    const button = {
        disabled: true,
        clickListener: undefined,
        /** Captures the real entry module's authentication click callback. */
        addEventListener(event, callback) { assert.equal(event, "click"); this.clickListener = callback; },
        /** Invokes and awaits the real async authentication handler. */
        async click() { assert.equal(this.disabled, false); await this.clickListener(); },
    };
    const window = {
        location: { search: "?frame_id=f&instance_id=i&platform=desktop" },
        /** Installs exactly the browser message or page-lifecycle listeners requested by the example. */
        addEventListener(event, callback, options) {
            const values = listeners.get(event) ?? new Set();
            values.add({ callback, once: options?.once ?? false });
            listeners.set(event, values);
        },
        /** Removes the exact transport listener when bridge ownership ends. */
        removeEventListener(event, callback) {
            for (const value of listeners.get(event) ?? []) if (value.callback === callback) listeners.get(event).delete(value);
        },
    };
    /** Delivers a simulated browser event synchronously, preserving authenticated peer identity. */
    function dispatch(event, value) {
        for (const listener of [...(listeners.get(event) ?? [])]) {
            listener.callback(value);
            if (listener.once) listeners.get(event).delete(listener);
        }
    }
    const source = {
        /** Replies to the actual handshake/commands, preserving their nonce and command correlation. */
        postMessage(tuple, origin) {
            sent.push({ tuple, origin });
            if (tuple[0] === 0) {
                dispatch("message", { source, origin, data: [1, { cmd: "DISPATCH", evt: "READY", nonce: null,
                    data: { v: 1, config: { api_endpoint: "//discord.com/api", environment: "production" } } }] });
            }
            if (tuple[0] !== 1) return;
            const request = tuple[1];
            const responses = {
                AUTHORIZE: { code: "synthetic-code" },
                AUTHENTICATE: { user: { id: "1" } },
                GET_ACTIVITY_INSTANCE_CONNECTED_PARTICIPANTS: { participants: [{ id: "1" }, { id: "2" }] },
            };
            assert.ok(request.cmd in responses, `Unexpected command ${request.cmd}`);
            dispatch("message", { source, origin, data: [1, { cmd: request.cmd, evt: null, nonce: request.nonce, data: responses[request.cmd] }] });
        },
    };
    window.parent = source;
    const document = {
        /** Referrer must not be read for establishing source/origin trust. */
        get referrer() { throw new Error("Referrer trust is forbidden"); },
        /** Resolves only DOM nodes and explicit deployment metadata used by the real example. */
        querySelector(selector) {
            if (selector === "#status") return status;
            if (selector === "#authenticate") return button;
            if (selector === 'meta[name="discord-client-id"]') return clientId === null ? null : { content: clientId };
            if (selector === 'meta[name="discord-host-origin"]') return hostOrigin === null ? null : { content: hostOrigin };
            throw new Error(`Unexpected selector ${selector}`);
        },
    };
    Object.defineProperties(globalThis, {
        window: { value: window, configurable: true, writable: true },
        document: { value: document, configurable: true, writable: true },
        fetch: { configurable: true, writable: true, value: async (url, init) => {
            exchanges.push({ url, init });
            return { ok: backendOK, async json() { return { access_token: "synthetic-access-token" }; } };
        } },
    });
    /** Restores globals after closing all example-owned work, including when an assertion fails. */
    function restore() {
        dispatch("pagehide", {});
        for (const [key, descriptor] of Object.entries(saved)) {
            if (descriptor) Object.defineProperty(globalThis, key, descriptor);
            else delete globalThis[key];
        }
    }
    try {
        const url = new URL("../../Examples/ActivityHost/Web/activity.mjs", import.meta.url);
        await import(`${url.href}?simulatedHost=${++moduleID}`);
    } catch (error) { restore(); throw error; }
    return { status, button, sent, exchanges, listeners, restore,
        /** Waits for a real render state through a setter barrier rather than an elapsed delay. */
        waitStatus(expected) { return text === expected ? Promise.resolve() : new Promise((resolve) => statusWaiters.push({ expected, resolve })); },
        /** Fires browser disposal so the test can assert listener and close-frame ownership. */
        pagehide() { dispatch("pagehide", {}); },
    };
}

test("real browser example imports bridge, becomes READY, exchanges authorization and loads participants", { timeout: 1000 }, async (t) => {
    const f = await example(); t.after(f.restore);
    await f.waitStatus("Discord host ready.");
    assert.equal(f.button.disabled, false);
    await f.button.click();
    assert.equal(f.status.textContent, "Authenticated. Connected participants: 2");
    assert.deepEqual(f.sent.filter((value) => value.tuple[0] === 1).map((value) => value.tuple[1].cmd), ["AUTHORIZE", "AUTHENTICATE", "GET_ACTIVITY_INSTANCE_CONNECTED_PARTICIPANTS"]);
    assert.ok(f.sent.every((value) => value.origin === "https://discord.com"));
    assert.equal(f.exchanges.length, 1);
    assert.equal(f.exchanges[0].url, "/api/token");
    assert.equal(f.exchanges[0].init.method, "POST");
    assert.equal(f.exchanges[0].init.credentials, "same-origin");
    assert.deepEqual(JSON.parse(f.exchanges[0].init.body), { code: "synthetic-code" });
    assert.equal(f.sent.find((value) => value.tuple[1].cmd === "AUTHENTICATE").tuple[1].args.access_token, "synthetic-access-token");
    f.pagehide();
    assert.equal(f.listeners.get("message").size, 0);
    assert.equal(f.sent.at(-1).tuple[0], 2);
});

test("real browser example refuses missing/unknown configured origins and missing application IDs", { timeout: 1000 }, async () => {
    for (const options of [{ hostOrigin: "https://evil.example" }, { hostOrigin: null }, { clientId: null }]) {
        const f = await example(options);
        try {
            await f.waitStatus("Open this configured Activity inside Discord to connect.");
            assert.equal(f.button.disabled, true);
            assert.equal(f.sent.length, 0);
            assert.equal(f.exchanges.length, 0);
        } finally { f.restore(); }
    }
});

test("real browser example surfaces backend rejection and does not authenticate with an unexchanged code", { timeout: 1000 }, async (t) => {
    const f = await example({ backendOK: false }); t.after(f.restore);
    await f.waitStatus("Discord host ready.");
    await f.button.click();
    assert.equal(f.status.textContent, "Authentication did not complete.");
    assert.equal(f.button.disabled, false);
    assert.deepEqual(f.sent.filter((value) => value.tuple[0] === 1).map((value) => value.tuple[1].cmd), ["AUTHORIZE"]);
});
