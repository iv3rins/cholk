import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import http from 'node:http';
import { buffer, json } from 'node:stream/consumers';
import { gzipSync } from 'node:zlib';

import { createProxyServer } from '../src/proxy.mjs';

const silentLogger = { info() {}, warn() {}, error() {} };

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve(server.address().port));
  });
}

function close(server) {
  return new Promise((resolve) => server.close(resolve));
}

async function createUpstream(handler) {
  const requests = [];
  const server = http.createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) chunks.push(chunk);
    const record = {
      method: req.method,
      url: req.url,
      headers: req.headers,
      body: Buffer.concat(chunks),
    };
    requests.push(record);
    try {
      await handler(req, res, record);
    } catch (error) {
      if (!res.headersSent) {
        res.statusCode = 500;
        res.setHeader('content-type', 'application/json');
      }
      res.end(JSON.stringify({ error: { message: error.message } }));
    }
  });
  const port = await listen(server);
  return {
    port,
    requests,
    close: () => close(server),
  };
}

const defaultHandler = async (req, res) => {
  if (req.url === '/models') {
    res.setHeader('content-type', 'application/json');
    res.end(JSON.stringify({ data: [{ id: 'deepseek-flash' }] }));
    return;
  }
  if (req.url === '/anthropic/v1/messages') {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write('event: message_start\ndata: {"type":"message_start"}\n\n');
    setTimeout(() => {
      res.write('event: message_stop\ndata: {"type":"message_stop"}\n\n');
      res.end();
    }, 500);
    return;
  }
  if (req.url === '/anthropic/v1/files') {
    res.setHeader('content-type', 'application/json');
    res.end(
      JSON.stringify({
        id: 'file_123',
        type: 'file',
        filename: 'hello.txt',
        mime_type: 'text/plain',
        size_bytes: 5,
      }),
    );
    return;
  }
  res.statusCode = 404;
  res.end('{}');
};

async function startProxy(t, overrides = {}) {
  const upstream = await createUpstream(overrides.handler ?? defaultHandler);
  t.after(() => upstream.close());
  const server = createProxyServer({
    upstream: `http://127.0.0.1:${upstream.port}`,
    apiKey: 'server-deepseek-key',
    proxyToken: 'client-token',
    maxBodyBytes: 80 * 1024 * 1024,
    allowedOrigins: '*',
    logger: silentLogger,
    ...overrides.proxy,
  });
  const port = await listen(server);
  t.after(() => close(server));
  return {
    upstream,
    base: `http://127.0.0.1:${port}`,
  };
}

function readWithTiming(url, headers) {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const req = http.request(url, { method: 'POST', headers }, (res) => {
      res.setEncoding('utf8');
      let text = '';
      let firstChunkAt = null;
      res.on('data', (chunk) => {
        if (firstChunkAt === null) firstChunkAt = Date.now() - started;
        text += chunk;
      });
      res.on('end', () => {
        resolve({
          status: res.statusCode,
          headers: res.headers,
          text,
          firstChunkAt,
          totalAt: Date.now() - started,
        });
      });
    });
    req.on('error', reject);
    req.end('{}');
  });
}

test('health endpoint works without authentication', async (t) => {
  const { base } = await startProxy(t);
  const response = await fetch(`${base}/healthz`);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.ok, true);
  assert.equal(body.auth, 'token');
});

test('rejects a wrong client token with 401', async (t) => {
  const { base } = await startProxy(t);
  const response = await fetch(`${base}/models`, {
    headers: { 'x-api-key': 'wrong-token' },
  });
  assert.equal(response.status, 401);
  const body = await response.json();
  assert.equal(body.error.type, 'proxy_error');
});

test('relays GET /models and replaces the client key with the server key', async (t) => {
  const { base, upstream } = await startProxy(t);
  const response = await fetch(`${base}/models`, {
    headers: { authorization: 'Bearer client-token' },
  });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.data[0].id, 'deepseek-flash');

  const record = upstream.requests[0];
  assert.equal(record.method, 'GET');
  assert.equal(record.url, '/models');
  assert.equal(record.headers['x-api-key'], 'server-deepseek-key');
  assert.equal(record.headers.authorization, 'Bearer server-deepseek-key');
  assert.equal(record.body.length, 0);
});

test('streams SSE chunks without buffering the full response', async (t) => {
  const { base, upstream } = await startProxy(t);
  const result = await readWithTiming(`${base}/anthropic/v1/messages`, {
    'x-proxy-token': 'client-token',
    'anthropic-beta': 'files-api-2025-04-14',
    accept: 'text/event-stream',
    'content-type': 'application/json',
  });
  assert.equal(result.status, 200);
  assert.match(result.headers['content-type'], /text\/event-stream/);
  assert.equal(result.headers['x-accel-buffering'], 'no');
  assert.match(result.headers['cache-control'], /no-transform/);
  assert.equal(result.firstChunkAt < 350, true, 'first chunk should arrive early');
  assert.equal(result.totalAt >= 400, true, 'stream should stay open for the upstream delay');
  assert.match(result.text, /message_start/);
  assert.match(result.text, /message_stop/);
  assert.equal(upstream.requests.length, 1);
  const record = upstream.requests[0];
  assert.equal(record.headers['x-proxy-token'], undefined);
  assert.equal(record.headers['anthropic-beta'], 'files-api-2025-04-14');
  assert.equal(record.headers['accept-encoding'], 'identity');
});

test('relays an encoded upstream response without changing its bytes', async (t) => {
  const payload = gzipSync(JSON.stringify({ data: [{ id: 'deepseek-flash' }] }));
  const { base } = await startProxy(t, {
    handler: (_req, res) => {
      res.writeHead(200, {
        'content-type': 'application/json',
        'content-encoding': 'gzip',
        'content-length': payload.length,
      });
      res.end(payload);
    },
  });

  const req = http.get(`${base}/models`, {
    headers: { 'x-api-key': 'client-token' },
  });
  const [response] = await once(req, 'response');
  assert.equal(response.statusCode, 200);
  assert.equal(response.headers['content-encoding'], 'gzip');
  assert.equal(response.headers['content-length'], String(payload.length));
  assert.deepEqual(await buffer(response), payload);
});

test('closes the upstream stream when the client cancels', async (t) => {
  let resolveUpstreamClosed;
  const upstreamClosed = new Promise((resolve) => {
    resolveUpstreamClosed = resolve;
  });
  const { base } = await startProxy(t, {
    handler: (_req, res) => {
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      res.write('event: message_start\ndata: {}\n\n');
      const timer = setTimeout(() => res.end(), 2000);
      res.once('close', () => {
        clearTimeout(timer);
        resolveUpstreamClosed(res.writableFinished);
      });
    },
  });

  const req = http.request(`${base}/anthropic/v1/messages`, {
    method: 'POST',
    agent: false,
    headers: { 'x-api-key': 'client-token' },
  });
  const responsePromise = once(req, 'response');
  req.end('{}');
  const [response] = await responsePromise;
  assert.equal(response.statusCode, 200);
  req.destroy();
  assert.equal(await upstreamClosed, false);
});

test('answers CORS preflight requests', async (t) => {
  const { base } = await startProxy(t);
  const response = await fetch(`${base}/models`, {
    method: 'OPTIONS',
    headers: {
      Origin: 'https://app.example.com',
      'Access-Control-Request-Method': 'POST',
      'Access-Control-Request-Headers': 'x-api-key, content-type',
    },
  });
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('access-control-allow-origin'), '*');
  assert.match(
    response.headers.get('access-control-allow-headers'),
    /x-api-key/,
  );
});

test('only allows the DeepSeek-compatible path allowlist', async (t) => {
  const { base } = await startProxy(t);
  const response = await fetch(`${base}/openai/v1/chat/completions`, {
    headers: { 'x-api-key': 'client-token' },
  });
  assert.equal(response.status, 404);
});

test('rejects bodies over the configured limit', async (t) => {
  const { base, upstream } = await startProxy(t, {
    proxy: { maxBodyBytes: 16 },
  });
  const response = await fetch(`${base}/anthropic/v1/messages`, {
    method: 'POST',
    headers: {
      'x-api-key': 'client-token',
      'content-type': 'application/json',
    },
    body: JSON.stringify({ message: 'this body is definitely too large' }),
  });
  assert.equal(response.status, 413);
  assert.equal(upstream.requests.length, 0);
});

test('returns 413 for a chunked body over the configured limit', async (t) => {
  const { base, upstream } = await startProxy(t, {
    proxy: { maxBodyBytes: 16 },
  });
  const req = http.request(`${base}/anthropic/v1/files`, {
    method: 'POST',
    headers: { 'x-api-key': 'client-token' },
  });
  const responsePromise = once(req, 'response');
  req.write('first chunk');
  req.end('second chunk');
  const [response] = await responsePromise;

  assert.equal(response.statusCode, 413);
  assert.equal((await json(response)).error.type, 'proxy_error');
  assert.equal(upstream.requests.length, 0);
});

test('relays multipart uploads', async (t) => {
  const { base, upstream } = await startProxy(t);
  const payload = Buffer.alloc(160 * 1024, 0xa5);
  const form = new FormData();
  form.append('purpose', 'user_data');
  form.append('file', new Blob([payload], { type: 'application/octet-stream' }), 'sample.bin');
  const response = await fetch(`${base}/anthropic/v1/files`, {
    method: 'POST',
    headers: { 'x-api-key': 'client-token' },
    body: form,
  });
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.equal(body.id, 'file_123');

  const record = upstream.requests[0];
  assert.match(record.headers['content-type'], /multipart\/form-data; boundary=/);
  assert.equal(record.headers['x-api-key'], 'server-deepseek-key');
  assert.equal(record.body.includes(payload), true);
});

test('honors an origin allowlist', async (t) => {
  const { base } = await startProxy(t, {
    proxy: { allowedOrigins: 'https://app.example.com' },
  });
  const allowed = await fetch(`${base}/models`, {
    method: 'OPTIONS',
    headers: {
      Origin: 'https://app.example.com',
      'Access-Control-Request-Method': 'POST',
    },
  });
  assert.equal(allowed.headers.get('access-control-allow-origin'), 'https://app.example.com');
  assert.equal(allowed.headers.get('vary'), 'Origin');

  const denied = await fetch(`${base}/models`, {
    method: 'OPTIONS',
    headers: {
      Origin: 'https://other.example.com',
      'Access-Control-Request-Method': 'POST',
    },
  });
  assert.equal(denied.headers.get('access-control-allow-origin'), null);
  assert.equal(denied.headers.get('vary'), 'Origin');
});
