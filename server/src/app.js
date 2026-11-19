'use strict';

const http = require('node:http');
const path = require('node:path');
const { Readable, Transform } = require('node:stream');
const { pipeline } = require('node:stream/promises');
const { Accounts, isUniqueViolation } = require('./accounts');

const CHAT_FIELDS = [
  'model', 'messages', 'temperature', 'top_p', 'max_tokens',
  'max_completion_tokens', 'stop', 'presence_penalty', 'frequency_penalty',
  'logit_bias', 'logprobs', 'top_logprobs', 'n', 'seed', 'user',
  'response_format', 'tools', 'tool_choice', 'parallel_tool_calls',
  'reasoning_effort', 'service_tier', 'stream_options',
];

function parseInteger(value, fallback, { min = 1, max = 2147483647 } = {}) {
  if (value === undefined) return fallback;
  if (!/^[0-9]+$/.test(value)) throw new Error('Invalid integer configuration');
  const number = Number(value);
  if (number < min || number > max) throw new Error('Configuration is out of range');
  return number;
}

function loadConfig(env = process.env) {
  if (!env.OPENAI_API_KEY) throw new Error('OPENAI_API_KEY is required');
  const baseUrl = new URL(env.OPENAI_BASE_URL || 'https://api.openai.com/v1');
  if (!['http:', 'https:'].includes(baseUrl.protocol) ||
      baseUrl.username || baseUrl.password || baseUrl.search || baseUrl.hash ||
      !/(^|\/)v1\/?$/.test(baseUrl.pathname)) {
    throw new Error('OPENAI_BASE_URL must be an HTTP(S) URL ending in /v1, without credentials or query');
  }
  if (!['true', 'false', undefined].includes(env.ALLOW_REGISTRATION)) {
    throw new Error('ALLOW_REGISTRATION must be true or false');
  }
  const origins = (env.CORS_ORIGINS || '').split(',').map((origin) => origin.trim()).filter(Boolean);
  for (const origin of origins) {
    const parsed = new URL(origin);
    if (!['http:', 'https:'].includes(parsed.protocol) || parsed.origin !== origin || origin === 'null') {
      throw new Error('CORS_ORIGINS must contain exact HTTP(S) origins');
    }
  }
  return {
    host: env.HOST || '127.0.0.1',
    port: parseInteger(env.PORT, 3000, { min: 0, max: 65535 }),
    databasePath: env.DATABASE_PATH || path.join(__dirname, '..', 'data', 'accounts.db'),
    openaiApiKey: env.OPENAI_API_KEY,
    openaiBaseUrl: baseUrl,
    allowRegistration: env.ALLOW_REGISTRATION === 'true',
    corsOrigins: new Set(origins),
    tokenTtlMs: parseInteger(env.TOKEN_TTL_SECONDS, 2592000) * 1000,
    authRateLimit: parseInteger(env.AUTH_RATE_LIMIT, 10),
    authRateWindowMs: parseInteger(env.AUTH_RATE_WINDOW_MS, 60000),
    upstreamFirstByteTimeoutMs: parseInteger(env.UPSTREAM_TIMEOUT_MS, 30000),
    sseHeartbeatMs: 15000,
    maxBodyBytes: parseInteger(env.MAX_BODY_BYTES, 1048576),
    scryptCost: parseInteger(env.SCRYPT_COST, 16384),
  };
}

class RateLimiter {
  constructor(limit, windowMs) {
    this.limit = limit;
    this.windowMs = windowMs;
    this.buckets = new Map();
    this.nextCleanup = 0;
  }

  check(key, now = Date.now()) {
    if (now >= this.nextCleanup) {
      for (const [bucket, value] of this.buckets) {
        if (value.resetAt <= now) this.buckets.delete(bucket);
      }
      this.nextCleanup = now + this.windowMs;
    }
    const current = this.buckets.get(key);
    if (!current || current.resetAt <= now) {
      this.buckets.set(key, { count: 1, resetAt: now + this.windowMs });
      return true;
    }
    current.count += 1;
    return current.count <= this.limit;
  }
}

class HttpError extends Error {
  constructor(status, code) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

function sendJson(res, status, body) {
  const data = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(data),
    'Cache-Control': 'no-store',
  });
  res.end(data);
}

function sendError(res, error) {
  const status = error instanceof HttpError ? error.status : 500;
  const code = error instanceof HttpError ? error.code : 'internal_error';
  const type = status === 429 ? 'rate_limit_error' : status === 502 ? 'api_error' : 'invalid_request_error';
  sendJson(res, status, { error: { message: code, type, code } });
}

async function readJson(req, maxBytes) {
  const contentType = req.headers['content-type']?.split(';', 1)[0].trim().toLowerCase();
  if (contentType !== 'application/json') throw new HttpError(415, 'content_type_json_required');
  const chunks = [];
  let length = 0;
  for await (const chunk of req.iterator({ destroyOnReturn: false })) {
    length += chunk.length;
    if (length > maxBytes) throw new HttpError(413, 'request_too_large');
    chunks.push(chunk);
  }
  let body;
  try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
  catch { throw new HttpError(400, 'invalid_json'); }
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw new HttpError(400, 'json_object_required');
  return body;
}

function validateCredentials(body) {
  if (typeof body.username !== 'string' || typeof body.password !== 'string') {
    throw new HttpError(400, 'invalid_credentials');
  }
  const username = body.username.trim();
  const password = body.password;
  if (username.length < 1 || username.length > 64 || !/^[A-Za-z0-9_.@-]+$/.test(username) ||
      Buffer.byteLength(username) > 64 || password.length < 8 || password.length > 256) {
    throw new HttpError(400, 'invalid_credentials');
  }
  return { username, password };
}

function bearerToken(req) {
  const value = req.headers.authorization;
  if (typeof value !== 'string') throw new HttpError(401, 'authentication_required');
  const match = /^Bearer ([A-Za-z0-9_-]{43})$/.exec(value);
  if (!match) throw new HttpError(401, 'authentication_required');
  return match[1];
}

function chatPayload(body) {
  if (body.stream !== true) throw new HttpError(400, 'stream_true_required');
  if (typeof body.model !== 'string' || !body.model || body.model.length > 200 || !Array.isArray(body.messages)) {
    throw new HttpError(400, 'invalid_chat_request');
  }
  const payload = { stream: true };
  for (const field of CHAT_FIELDS) {
    if (Object.hasOwn(body, field)) payload[field] = body[field];
  }
  return JSON.stringify(payload);
}

function upstreamUrl(base, suffix) {
  const url = new URL(base);
  url.pathname = `${url.pathname.replace(/\/$/, '')}${suffix}`;
  return url;
}

async function proxyUpstream(config, shutdownSignal, res, endpoint, { streaming = false, body } = {}) {
  if (res.destroyed) return;
  const controller = new AbortController();
  const signal = AbortSignal.any([controller.signal, shutdownSignal]);
  const onClose = () => {
    if (!res.writableFinished) controller.abort();
  };
  res.once('close', onClose);
  // For SSE the first-byte timeout ends at upstream response headers.
  let heartbeat;
  const timeout = setTimeout(() => controller.abort(), config.upstreamFirstByteTimeoutMs);
  try {
    const contentType = streaming ? 'text/event-stream' : 'application/json';
    const headers = {
      Authorization: `Bearer ${config.openaiApiKey}`,
      Accept: contentType,
    };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const upstream = await fetch(upstreamUrl(config.openaiBaseUrl, endpoint), {
      method: body === undefined ? 'GET' : 'POST',
      headers,
      body,
      signal,
    });
    if (streaming) clearTimeout(timeout);
    if (!upstream.ok) {
      await upstream.body?.cancel();
      throw new HttpError(502, 'upstream_unavailable');
    }

    res.writeHead(200, {
      'Content-Type': upstream.headers.get('content-type') || `${contentType}; charset=utf-8`,
      'Cache-Control': streaming ? 'no-cache, no-transform' : 'no-store',
      ...(streaming ? { 'X-Accel-Buffering': 'no' } : {}),
    });
    if (streaming) res.flushHeaders();
    if (streaming && upstream.body) {
      let lastByte;
      let penultimateByte;
      const passthrough = new Transform({
        transform(chunk, _encoding, callback) {
          penultimateByte = chunk.length > 1 ? chunk[chunk.length - 2] : lastByte;
          lastByte = chunk[chunk.length - 1];
          heartbeat.refresh();
          callback(null, chunk);
        },
        flush(callback) {
          clearInterval(heartbeat);
          callback();
        },
      });
      heartbeat = setInterval(() => {
        // Push through the same stream so the comment follows queued bytes.
        if (lastByte === undefined || (penultimateByte === 10 && lastByte === 10)) {
          passthrough.push(': ping\n\n');
        }
      }, config.sseHeartbeatMs);
      await pipeline(Readable.fromWeb(upstream.body), passthrough, res, { signal });
    } else if (upstream.body) {
      await pipeline(Readable.fromWeb(upstream.body), res, { signal });
    } else {
      res.end();
    }
  } catch {
    if (!res.destroyed) throw new HttpError(502, 'upstream_unavailable');
  } finally {
    clearInterval(heartbeat);
    clearTimeout(timeout);
    res.off('close', onClose);
  }
}

async function createApp(options = {}) {
  const config = { ...loadConfig({
    ...(options.env || process.env),
    OPENAI_API_KEY: options.openaiApiKey || options.env?.OPENAI_API_KEY || process.env.OPENAI_API_KEY,
    OPENAI_BASE_URL: options.openaiBaseUrl?.toString() || options.env?.OPENAI_BASE_URL || process.env.OPENAI_BASE_URL,
  }), ...options };
  if (!(config.openaiBaseUrl instanceof URL)) config.openaiBaseUrl = new URL(config.openaiBaseUrl);
  if (!(config.corsOrigins instanceof Set)) config.corsOrigins = new Set(config.corsOrigins || []);
  const accounts = new Accounts(config.databasePath, config.tokenTtlMs, config.scryptCost);
  const limiter = new RateLimiter(config.authRateLimit, config.authRateWindowMs);
  const shutdown = new AbortController();

  const server = http.createServer(async (req, res) => {
    const origin = req.headers.origin;
    if (origin && config.corsOrigins.has(origin)) {
      res.setHeader('Access-Control-Allow-Origin', origin);
      res.setHeader('Vary', 'Origin');
      res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      res.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
      res.setHeader('Access-Control-Max-Age', '600');
    }
    try {
      if (req.method === 'OPTIONS') {
        if (!origin || !config.corsOrigins.has(origin) || req.headers['access-control-request-method'] === undefined) {
          throw new HttpError(403, 'cors_origin_denied');
        }
        res.writeHead(204).end();
        return;
      }
      const url = new URL(req.url, 'http://localhost');
      if (url.search) throw new HttpError(404, 'not_found');
      if (url.pathname === '/auth/register' && req.method === 'POST') {
        if (!config.allowRegistration) throw new HttpError(403, 'registration_disabled');
        const clientIp = req.socket.remoteAddress || 'unknown';
        if (!limiter.check(`${clientIp}:register`)) throw new HttpError(429, 'rate_limit_exceeded');
        const credentials = validateCredentials(await readJson(req, config.maxBodyBytes));
        let session;
        try {
          session = await accounts.register(credentials.username, credentials.password);
        } catch (error) {
          if (isUniqueViolation(error)) throw new HttpError(409, 'username_taken');
          throw error;
        }
        sendJson(res, 200, session);
      } else if (url.pathname === '/auth/login' && req.method === 'POST') {
        const clientIp = req.socket.remoteAddress || 'unknown';
        if (!limiter.check(`${clientIp}:login`)) throw new HttpError(429, 'rate_limit_exceeded');
        const credentials = validateCredentials(await readJson(req, config.maxBodyBytes));
        const session = await accounts.login(credentials.username, credentials.password);
        if (!session) throw new HttpError(401, 'invalid_credentials');
        sendJson(res, 200, session);
      } else if (url.pathname === '/auth/logout' && req.method === 'POST') {
        const token = bearerToken(req);
        if (!accounts.authenticate(token)) throw new HttpError(401, 'authentication_required');
        accounts.revoke(token);
        res.setHeader('Cache-Control', 'no-store');
        res.writeHead(204).end();
      } else if (url.pathname === '/v1/models' && req.method === 'GET') {
        if (!accounts.authenticate(bearerToken(req))) throw new HttpError(401, 'authentication_required');
        await proxyUpstream(config, shutdown.signal, res, '/models');
      } else if (url.pathname === '/v1/chat/completions' && req.method === 'POST') {
        if (!accounts.authenticate(bearerToken(req))) throw new HttpError(401, 'authentication_required');
        const body = chatPayload(await readJson(req, config.maxBodyBytes));
        await proxyUpstream(config, shutdown.signal, res, '/chat/completions', { streaming: true, body });
      } else {
        throw new HttpError(404, 'not_found');
      }
    } catch (error) {
      if (res.destroyed) return;
      if (res.headersSent) {
        res.destroy();
      } else {
        if (error instanceof HttpError && error.status === 413) res.setHeader('Connection', 'close');
        sendError(res, error);
      }
    }
  });
  server.requestTimeout = 30000;
  server.headersTimeout = 10000;
  server.keepAliveTimeout = 5000;
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(config.port, config.host, resolve);
  });
  let closeTask;
  const close = () => closeTask ??= new Promise((resolve, reject) => {
    shutdown.abort();
    server.close((error) => {
      try {
        accounts.close();
      } catch (closeError) {
        reject(closeError);
        return;
      }
      if (error) reject(error);
      else resolve();
    });
  });
  return {
    server,
    config,
    accounts,
    address: `http://${config.host.includes(':') ? `[${config.host}]` : config.host}:${server.address().port}`,
    close,
  };
}

module.exports = { createApp, loadConfig };
