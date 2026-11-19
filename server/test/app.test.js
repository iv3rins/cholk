'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { once } = require('node:events');
const { setTimeout: sleep } = require('node:timers/promises');
const { createApp } = require('../src/app');

async function upstreamServer(handler) {
  const server = http.createServer(handler);
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  return {
    server,
    origin: `http://127.0.0.1:${server.address().port}`,
    close: () => new Promise((resolve) => { server.close(resolve); server.closeAllConnections(); }),
  };
}

async function startApp(t, handler, options = {}) {
  const upstream = await upstreamServer(handler || ((req, res) => {
    if (req.url === '/v1/models') {
      res.setHeader('Content-Type', 'application/json');
      res.end(JSON.stringify({ object: 'list', data: [{ id: 'fake-model', object: 'model', created: 1, owned_by: 'test' }] }));
    } else {
      res.writeHead(404).end();
    }
  }));
  const app = await createApp({
    host: '127.0.0.1', port: 0, databasePath: ':memory:',
    openaiApiKey: 'server-only-key', openaiBaseUrl: `${upstream.origin}/v1`,
    allowRegistration: true, scryptCost: 1024, ...options,
  });
  t.after(async () => { await app.close(); await upstream.close(); });
  return { app, upstream };
}

async function api(app, route, { method = 'GET', token, body, headers = {} } = {}) {
  return fetch(`${app.address}${route}`, {
    method,
    headers: {
      ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

async function register(app, username = 'alice', password = 'correct horse') {
  const response = await api(app, '/auth/register', { method: 'POST', body: { username, password } });
  assert.equal(response.status, 200);
  return response.json();
}

test('register and login return tokens; models work and logout revokes the exact token', async (t) => {
  const { app } = await startApp(t);
  const registered = await register(app);
  assert.deepEqual(Object.keys(registered).sort(), ['token', 'username']);
  assert.equal(registered.username, 'alice');
  assert.match(registered.token, /^[A-Za-z0-9_-]{43}$/);
  const login = await api(app, '/auth/login', { method: 'POST', body: { username: 'alice', password: 'correct horse' } });
  assert.equal(login.status, 200);
  const session = await login.json();
  assert.equal(session.username, 'alice');
  assert.notEqual(session.token, registered.token);
  const wrong = await api(app, '/auth/login', { method: 'POST', body: { username: 'alice', password: 'wrong password' } });
  assert.equal(wrong.status, 401);
  const models = await api(app, '/v1/models', { token: session.token });
  assert.equal(models.status, 200);
  assert.equal((await models.json()).data[0].id, 'fake-model');
  const logout = await api(app, '/auth/logout', { method: 'POST', token: session.token });
  assert.equal(logout.status, 204);
  assert.equal(logout.headers.get('cache-control'), 'no-store');
  assert.equal((await api(app, '/v1/models', { token: session.token })).status, 401);
  assert.equal((await api(app, '/v1/models', { token: registered.token })).status, 200);
  assert.equal((await api(app, '/v1/models', { token: `Bearer ${session.token}` })).status, 401);
});

test('accounts persist on disk without plaintext passwords or bearer tokens', async (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'cholk-accounts-'));
  const databasePath = path.join(directory, 'accounts.db');
  const upstream = await upstreamServer((req, res) => res.end('{}'));
  const options = { host: '127.0.0.1', port: 0, databasePath, openaiApiKey: 'server-key', openaiBaseUrl: `${upstream.origin}/v1`, allowRegistration: true, scryptCost: 1024 };
  let app = await createApp(options);
  // Hold the handle in a mutable slot so cleanup always releases this connection
  // before the temporary directory is removed; SQLite keeps files locked on
  // Windows and an early t.after() would fail with EBUSY.
  const open = { app };
  t.after(async () => {
    await open.app.close();
    await upstream.close();
    fs.rmSync(directory, { recursive: true, force: true, maxRetries: 10, retryDelay: 50 });
  });
  const session = await register(open.app);
  await open.app.close();
  open.app = await createApp(options);
  const login = await api(open.app, '/auth/login', { method: 'POST', body: { username: 'alice', password: 'correct horse' } });
  assert.equal(login.status, 200);
  assert.equal((await api(open.app, '/v1/models', { token: session.token })).status, 200);
  const stored = fs.readFileSync(databasePath);
  assert.equal(stored.includes('correct horse'), false);
  assert.equal(stored.includes(session.token), false);
  const { DatabaseSync } = require('node:sqlite');
  const db = new DatabaseSync(databasePath);
  try {
    const users = db.prepare('SELECT username, password_hash FROM users').all();
    const sessions = db.prepare('SELECT token_hash FROM sessions').all();
    assert.equal(users.length, 1);
    assert.equal(users[0].username, 'alice');
    assert.match(users[0].password_hash, /^scrypt\$1024\$[A-Za-z0-9+/=]+\$[A-Za-z0-9+/=]+$/);
    assert.equal(sessions.length, 2);
    for (const row of sessions) {
      assert.match(row.token_hash, /^[0-9a-f]{64}$/);
      assert.notEqual(row.token_hash, session.token);
    }
  } finally {
    db.close();
  }
});

test('registration defaults to closed and duplicate usernames are rejected', async (t) => {
  const closed = await startApp(t, undefined, { allowRegistration: false });
  assert.equal((await registerResponse(closed.app)).status, 403);
  const open = await startApp(t);
  await register(open.app);
  assert.equal((await registerResponse(open.app)).status, 409);
});

test('registration rolls back the account when its first session cannot be stored', async (t) => {
  const { app } = await startApp(t);
  app.accounts.db.exec(`
    CREATE TRIGGER reject_session BEFORE INSERT ON sessions
    BEGIN SELECT RAISE(ABORT, 'simulated session write failure'); END;
  `);
  const failed = await registerResponse(app);
  assert.equal(failed.status, 500);
  await failed.text();
  app.accounts.db.exec('DROP TRIGGER reject_session');
  const { token } = await register(app);
  assert.equal((await api(app, '/v1/models', { token })).status, 200);
});

function registerResponse(app) {
  return api(app, '/auth/register', { method: 'POST', body: { username: 'alice', password: 'correct horse' } });
}

test('auth endpoints are rate limited independently and validate request bodies', async (t) => {
  const { app } = await startApp(t, undefined, { authRateLimit: 3, maxBodyBytes: 128 });
  for (let i = 0; i < 3; i++) {
    const response = await api(app, '/auth/login', { method: 'POST', body: { username: 'nobody', password: 'long enough' } });
    assert.equal(response.status, 401);
  }
  assert.equal((await api(app, '/auth/login', { method: 'POST', body: { username: 'nobody', password: 'long enough' } })).status, 429);
  const malformed = await fetch(`${app.address}/auth/register`, { method: 'POST', headers: { 'Content-Type': 'text/plain' }, body: 'not json' });
  assert.equal(malformed.status, 415);
  const oversized = await api(app, '/auth/register', {
    method: 'POST', body: { username: 'alice', password: 'a'.repeat(128) },
  });
  assert.equal(oversized.status, 413);
  assert.equal((await oversized.json()).error.code, 'request_too_large');
});

test('unauthenticated and unknown proxy paths never reach upstream', async (t) => {
  let calls = 0;
  const { app } = await startApp(t, (req, res) => { calls++; res.end('{}'); });
  assert.equal((await api(app, '/v1/models')).status, 401);
  assert.equal((await api(app, '/v1/models', { token: 'A'.repeat(43) })).status, 401);
  const session = await register(app);
  assert.equal((await api(app, '/v1/other', { token: session.token })).status, 404);
  assert.equal(calls, 0);
});

test('chat forces streaming, uses only the server key and forwards whitelisted fields', async (t) => {
  let request;
  const { app } = await startApp(t, async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    request = { url: req.url, auth: req.headers.authorization, body: JSON.parse(Buffer.concat(chunks)) };
    res.writeHead(200, { 'Content-Type': 'text/event-stream' });
    res.write('data: {"choices":[{"delta":{"content":"hello"}}]}\n\n');
    await sleep(30);
    res.end('data: [DONE]\n\n');
  });
  const { token } = await register(app);
  const bad = await api(app, '/v1/chat/completions', { method: 'POST', token, body: { model: 'fake-model', messages: [], stream: false } });
  assert.equal(bad.status, 400);
  const response = await api(app, '/v1/chat/completions', {
    method: 'POST', token,
    body: {
      model: 'fake-model', messages: [{ role: 'user', content: 'hello' }], stream: true,
      temperature: 0.2, stream_options: { include_usage: true },
      base_url: 'http://attacker.invalid', url: 'http://attacker.invalid', api_key: 'client-key',
    },
  });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), 'text/event-stream');
  assert.match(await response.text(), /data: \[DONE\]/);
  assert.equal(request.url, '/v1/chat/completions');
  assert.equal(request.auth, 'Bearer server-only-key');
  assert.equal(request.body.stream, true);
  assert.equal(request.body.model, 'fake-model');
  assert.equal(request.body.temperature, 0.2);
  assert.equal('base_url' in request.body, false);
  assert.equal('url' in request.body, false);
  assert.equal('api_key' in request.body, false);
});

test('SSE streams immediately and stays open beyond the upstream header timeout', async (t) => {
  const upstreamFirstByteTimeoutMs = 150;
  let releaseUpstream;
  const holdOpen = new Promise((resolve) => { releaseUpstream = resolve; });
  const { app } = await startApp(t, async (req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/event-stream' });
    res.write('data: {"choices":[{"delta":{"content":"first"}}]}\n\n');
    await holdOpen;
    res.end('data: [DONE]\n\n');
  }, { upstreamFirstByteTimeoutMs });
  const { token } = await register(app);
  const response = await api(app, '/v1/chat/completions', {
    method: 'POST', token,
    body: { model: 'fake-model', messages: [{ role: 'user', content: 'hi' }], stream: true },
  });
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('content-type'), 'text/event-stream');
  assert.equal(response.headers.get('cache-control'), 'no-cache, no-transform');
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  // The upstream has not ended this stream yet; the first event must already
  // have arrived, which is what makes the proxy streaming rather than buffering.
  const first = await reader.read();
  assert.equal(first.done, false);
  assert.match(decoder.decode(first.value), /"content":"first"/);
  await sleep(upstreamFirstByteTimeoutMs + 50);
  releaseUpstream();
  let rest = '';
  for (;;) {
    const chunk = await reader.read();
    if (chunk.done) break;
    rest += decoder.decode(chunk.value);
  }
  assert.match(rest, /data: \[DONE\]/);
});

for (const partial of [false, true]) {
  test(partial ? 'SSE never pings through a partial line' : 'SSE pings before the first upstream event', async (t) => {
    const { app } = await startApp(t, async (_req, res) => {
      res.writeHead(200, { 'Content-Type': 'text/event-stream' });
      res.flushHeaders();
      if (partial) res.write('data: {"a"');
      await sleep(100);
      res.end(partial ? ':1}\n\n' : 'data: [DONE]\n\n');
    }, { sseHeartbeatMs: 15 });
    const { token } = await register(app);
    const response = await api(app, '/v1/chat/completions', {
      method: 'POST', token,
      body: { model: 'fake-model', messages: [], stream: true },
    });
    const text = await response.text();
    if (partial) {
      assert.equal(text, 'data: {"a":1}\n\n');
    } else {
      assert.match(text, /^: ping\n\n/);
      assert.ok(text.endsWith('data: [DONE]\n\n'));
    }
  });
}

test('an upstream timeout before headers returns the documented gateway error', async (t) => {
  const { app } = await startApp(t, () => {}, { upstreamFirstByteTimeoutMs: 100 });
  const { token } = await register(app);
  const response = await api(app, '/v1/models', { token });
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), { error: {
    message: 'upstream_unavailable', type: 'api_error', code: 'upstream_unavailable',
  } });
});

test('disconnecting before upstream headers aborts the pending request', async (t) => {
  let upstreamStarted;
  let upstreamClosed;
  const started = new Promise((resolve) => { upstreamStarted = resolve; });
  const closed = new Promise((resolve) => { upstreamClosed = resolve; });
  const { app } = await startApp(t, (req, res) => {
    res.once('close', upstreamClosed);
    upstreamStarted();
  });
  const { token } = await register(app);
  const request = http.get(`${app.address}/v1/models`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  request.on('error', () => {});
  try {
    await Promise.race([started, sleep(1000).then(() => assert.fail('upstream was not reached'))]);
  } finally {
    request.destroy();
  }
  await Promise.race([closed, sleep(1000).then(() => assert.fail('upstream was not aborted'))]);
});

test('disconnecting an SSE client aborts a quiet upstream response', async (t) => {
  let upstreamClosed;
  const closed = new Promise((resolve) => { upstreamClosed = resolve; });
  const { app } = await startApp(t, (req, res) => {
    res.once('close', upstreamClosed);
    res.writeHead(200, { 'Content-Type': 'text/event-stream' });
    res.flushHeaders();
  }, { sseHeartbeatMs: 15 });
  const { token } = await register(app);
  const controller = new AbortController();
  const response = await fetch(`${app.address}/v1/chat/completions`, {
    method: 'POST', signal: controller.signal,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'fake-model', messages: [], stream: true }),
  });
  const reader = response.body.getReader();
  assert.match(new TextDecoder().decode((await reader.read()).value), /: ping/);
  controller.abort();
  await Promise.race([closed, sleep(1000).then(() => assert.fail('upstream was not aborted'))]);
});

test('closing the server aborts active streams and waits for the same close task', async (t) => {
  let upstreamClosed;
  const closed = new Promise((resolve) => { upstreamClosed = resolve; });
  const { app } = await startApp(t, (req, res) => {
    res.once('close', upstreamClosed);
    res.writeHead(200, { 'Content-Type': 'text/event-stream' });
    res.write('data: first\n\n');
  }, { upstreamFirstByteTimeoutMs: 2000 });
  const { token } = await register(app);
  const request = http.request(`${app.address}/v1/chat/completions`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
  });
  const responseStarted = once(request, 'response');
  request.end(JSON.stringify({ model: 'fake-model', messages: [], stream: true }));
  const [response] = await responseStarted;
  response.on('error', () => {});
  const closeTask = app.close();
  assert.equal(app.close(), closeTask);
  await Promise.race([
    Promise.all([closeTask, closed]),
    sleep(1000, undefined, { ref: false }).then(() => assert.fail('server did not cancel the upstream')),
  ]);
});

test('CORS is opt-in and restricted to configured origins', async (t) => {
  const { app } = await startApp(t, undefined, { corsOrigins: ['https://app.example'] });
  const preflight = await fetch(`${app.address}/auth/login`, {
    method: 'OPTIONS',
    headers: { Origin: 'https://app.example', 'Access-Control-Request-Method': 'POST' },
  });
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('access-control-allow-origin'), 'https://app.example');
  const denied = await fetch(`${app.address}/auth/login`, {
    method: 'OPTIONS',
    headers: { Origin: 'https://other.example', 'Access-Control-Request-Method': 'POST' },
  });
  assert.equal(denied.status, 403);
  const closed = await startApp(t);
  assert.equal((await registerResponse(closed.app)).headers.get('access-control-allow-origin'), null);
});

test('expired tokens cannot authenticate', async (t) => {
  const { app } = await startApp(t, undefined, { tokenTtlMs: -1 });
  const { token } = await register(app);
  assert.equal((await api(app, '/v1/models', { token })).status, 401);
});
