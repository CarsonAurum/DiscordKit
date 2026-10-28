// File: Examples/ActivityHost/Web/activity.mjs
// Created by Carson Rau.
// Copyright (c) 2026 Aurum Studios.
// https://aurum-studios.com

import {ActivityBridge, createWindowTransport} from '../../../Browser/DiscordActivityBridge/ActivityBridge.mjs';

const allowedOrigins = ['https://discord.com', 'https://ptb.discord.com', 'https://canary.discord.com'];
const status = document.querySelector('#status');
const button = document.querySelector('#authenticate');
const source = window.parent.opener ?? window.parent;
let bridge;

/** Initializes only inside an explicitly allowlisted Discord host; public client ID comes from deployment configuration. */
async function initialize() {
    const clientId = document.querySelector('meta[name="discord-client-id"]')?.content;
    const hostOrigin = document.querySelector('meta[name="discord-host-origin"]')?.content;
    if (!clientId || !allowedOrigins.includes(hostOrigin) || source === window) throw new Error('host unavailable');
    bridge = new ActivityBridge({clientId, search: window.location.search, hostOrigin, allowedOrigins,
        source, transport: createWindowTransport(window, source)});
    await bridge.start();
    status.textContent = 'Discord host ready.';
    button.disabled = false;
}

/** Requests consent then exchanges the code through an application-authenticated backend; never embeds a client secret. */
async function authenticate() {
    button.disabled = true;
    try {
        const authorization = await bridge.request('AUTHORIZE', {client_id: document.querySelector('meta[name="discord-client-id"]').content, scope: ['identify'], response_type: 'code'});
        const response = await fetch('/api/token', {method: 'POST', credentials: 'same-origin',
            headers: {'Content-Type': 'application/json'}, body: JSON.stringify({code: authorization.data.code})});
        if (!response.ok) throw new Error('exchange rejected');
        const token = await response.json();
        if (typeof token.access_token !== 'string' || !token.access_token) throw new Error('invalid token');
        await bridge.request('AUTHENTICATE', {access_token: token.access_token});
        const participants = await bridge.request('GET_ACTIVITY_INSTANCE_CONNECTED_PARTICIPANTS', {});
        status.textContent = `Authenticated. Connected participants: ${participants.data.participants.length}`;
    } catch { status.textContent = 'Authentication did not complete.'; }
    finally { button.disabled = false; }
}

button.addEventListener('click', authenticate);
window.addEventListener('pagehide', () => bridge?.close(), {once: true});
initialize().catch(() => { status.textContent = 'Open this configured Activity inside Discord to connect.'; });
