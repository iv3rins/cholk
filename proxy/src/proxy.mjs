import http from 'node:http';
import https from 'node:https';
import { timingSafeEqual } from 'node:crypto';
import { pipeline } from 'node:stream/promises';

const DEFAULT_UPSTREAM = 'https://api.deepseek.com';
const UPSTREAM_IDLE_TIMEOUT_MS = 300_000;

// Only these upstream paths are reachable. The proxy is not a general-purpose
// open proxy, so a leaked URL cannot be used to call arbitrary services.
const ALLOWED_PREFIXES = ['/anthropic/v1/', '/v1/tools/'];

const PASS_RESPONSE_HEADERS = [
  'content-type',
  'content-length',
  'content-encoding',
  'cache-control',
  'etag',
  'last-modified',
  'location',
  'retry-after',
  'x-ds-request-id',
  'x-request-id',
  'anthropic-ratelimit-requests-limit',
  'anthropic-ratelimit-requests-remaining',
  'anthropic-ratelimit-requests-reset',
];

const CORS_ALLOW_HEADERS = [
  'Authorization',
  'Content-Type',
  'Accept',
  'x-api-key',
  'x-proxy-token',
  'anthropic-beta',
  'anthropic-version',
];

const CORS_EXPOSE_HEADERS = [
  'x-ds-request-id',
  'x-request-id',
  'retry-after',
];

export class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.name = 'HttpError';
    this.status = status;
  }
}

export function createProxyServer({
  upstream = DEFAULT_UPSTREAM,
  apiKey,
  proxyToken = '',
  maxBodyBytes = 80 * 1024 * 1024,
  allowedOrigins = '*',
  logger = console,
} = {}) {
  if (!apiKey || !String(apiKey).trim()) {
    throw new Error('apiKey is required');
  }
  const upstreamOrigin = normalizeUpstream(upstream);
  const options = {
    upstreamOrigin,
    requestUpstream: upstreamOrigin.startsWith('https:') ? https.request : http.request,
    apiKey: String(apiKey).trim(),
    proxyToken: String(proxyToken).trim(),
    maxBodyBytes,
    origins: parseOrigins(allowedOrigins),
    logger,
  };

  const server = http.createServer((req, res) => {
    void handleRequest(req, res, options);
  });

  server.keepAliveTimeout = 72_000;
  server.headersTimeout = 75_000;
  server.on('clientError', (error, socket) => {
    if (error.code === 'ECONNRESET' || !socket.writable) return;
    socket.end('HTTP/1.1 400 Bad Request\r\n\r\n');
  });

  return server;
}

async function handleRequest(req, res, options) {
  const startedAt = Date.now();
  let url;
  let failed = false;

  try {
    applyCors(req, res, options.origins);
    try {
      url = new URL(req.url ?? '/', 'http://proxy.local');
    } catch {
      throw new HttpError(400, 'Invalid request URL');
    }

    if (req.method === 'OPTIONS') {
      res.statusCode = 204;
      res.end();
      return;
    }

    if (req.method === 'GET' && url.pathname === '/healthz') {
      sendJson(res, 200, {
        ok: true,
        service: 'deepseek-proxy',
        upstream: options.upstreamOrigin,
        auth: options.proxyToken ? 'token' : 'none',
        maxBodyBytes: options.maxBodyBytes,
      });
      return;
    }

    if (!isAllowedPath(url.pathname)) {
      throw new HttpError(404, 'Not found');
    }

    if (!isAuthorized(req, options.proxyToken)) {
      throw new HttpError(401, 'Invalid proxy token');
    }

    await relay(req, res, url, options);
  } catch (error) {
    failed = true;
    const status = error instanceof HttpError ? error.status : 502;
    const message =
      error instanceof HttpError ? error.message : 'Upstream request failed';

    if (status >= 500) {
      options.logger.error?.(
        `[proxy] ${req.method} ${url?.pathname ?? '-'} failed: ${error.message}`,
      );
    }
    if (res.headersSent) {
      res.destroy();
    } else {
      if (status === 413) res.setHeader('Connection', 'close');
      try {
        sendJson(res, status, { error: { type: 'proxy_error', message } });
      } catch {
        res.destroy();
      }
    }
  } finally {
    const elapsed = Date.now() - startedAt;
    options.logger.info?.(
      `[proxy] ${req.method} ${url?.pathname ?? '-'} ${failed ? 'ERR' : res.statusCode} ${elapsed}ms`,
    );
  }
}

async function relay(req, res, url, options) {
  const hasBody = req.method !== 'GET' && req.method !== 'HEAD';
  const declaredLength = Number(req.headers['content-length']);
  if (
    Number.isFinite(declaredLength) &&
    declaredLength > options.maxBodyBytes
  ) {
    throw new HttpError(413, 'Request body too large');
  }

  const body = hasBody
    ? await readBody(req, options.maxBodyBytes)
    : undefined;
  if (res.destroyed) return;

  const headers = {
    accept: firstHeader(req.headers.accept) ?? '*/*',
    // Never ask for compressed SSE payloads; streaming must stay incremental.
    'accept-encoding': 'identity',
    'user-agent': 'deepseek-proxy/0.1',
  };

  const contentType = firstHeader(req.headers['content-type']);
  if (contentType) headers['content-type'] = contentType;
  const acceptLanguage = firstHeader(req.headers['accept-language']);
  if (acceptLanguage) headers['accept-language'] = acceptLanguage;
  const anthropicBeta = firstHeader(req.headers['anthropic-beta']);
  if (anthropicBeta) headers['anthropic-beta'] = anthropicBeta;
  const anthropicVersion = firstHeader(req.headers['anthropic-version']);
  if (anthropicVersion) headers['anthropic-version'] = anthropicVersion;
  if (body?.size) headers['content-length'] = String(body.size);

  // The client credential is only a proxy token or a locally typed key. It is
  // never forwarded: the server-side DeepSeek key always replaces it.
  headers['x-api-key'] = options.apiKey;
  headers['authorization'] = `Bearer ${options.apiKey}`;

  const controller = new AbortController();
  const onResponseClose = () => {
    if (!res.writableFinished) controller.abort();
  };
  res.once('close', onResponseClose);

  try {
    // Use the native HTTP stream so the response bytes and headers stay in sync.
    const upstreamResponse = await new Promise((resolve, reject) => {
      const request = options.requestUpstream(
        `${options.upstreamOrigin}${url.pathname}${url.search}`,
        {
          method: req.method,
          headers,
          signal: controller.signal,
          timeout: UPSTREAM_IDLE_TIMEOUT_MS,
        },
        resolve,
      );
      request.once('error', reject);
      request.once('close', () => {
        reject(new Error('Upstream connection closed without a response'));
      });
      request.once('timeout', () => {
        request.destroy(new Error('Upstream request timed out'));
      });
      if (body) {
        for (const chunk of body.chunks) request.write(chunk);
      }
      request.end();
    });

    res.statusCode = upstreamResponse.statusCode;
    for (const name of PASS_RESPONSE_HEADERS) {
      const value = upstreamResponse.headers[name];
      if (value !== undefined) res.setHeader(name, value);
    }

    const responseType = upstreamResponse.headers['content-type'] ?? '';
    if (responseType.includes('text/event-stream')) {
      res.setHeader('Cache-Control', 'no-cache, no-transform');
      res.setHeader('X-Accel-Buffering', 'no');
      res.setHeader('Connection', 'keep-alive');
      res.flushHeaders();
    }

    await pipeline(upstreamResponse, res);
  } catch (error) {
    if (!controller.signal.aborted) throw error;
  } finally {
    res.off('close', onResponseClose);
  }
}

async function readBody(req, limit) {
  const chunks = [];
  let size = 0;
  // Keep the client socket writable long enough to send a 413 on overflow.
  for await (const chunk of req.iterator({ destroyOnReturn: false })) {
    size += chunk.length;
    if (size > limit) {
      throw new HttpError(413, 'Request body too large');
    }
    chunks.push(chunk);
  }
  return { chunks, size };
}

function isAllowedPath(pathname) {
  if (pathname === '/models' || pathname === '/models/') return true;
  return ALLOWED_PREFIXES.some((prefix) => pathname.startsWith(prefix));
}

function isAuthorized(req, proxyToken) {
  if (!proxyToken) return true;
  const provided =
    firstHeader(req.headers['x-proxy-token']) ??
    firstHeader(req.headers['x-api-key']) ??
    bearerToken(firstHeader(req.headers.authorization));
  return typeof provided === 'string' && secureEqual(provided.trim(), proxyToken);
}

function secureEqual(a, b) {
  const left = Buffer.from(a, 'utf8');
  const right = Buffer.from(b, 'utf8');
  return left.length === right.length && timingSafeEqual(left, right);
}

function bearerToken(value) {
  if (typeof value !== 'string') return '';
  const match = /^Bearer\s+(.+)$/i.exec(value.trim());
  return match ? match[1].trim() : '';
}

function firstHeader(value) {
  if (Array.isArray(value)) return value[0];
  return typeof value === 'string' ? value : undefined;
}

function parseOrigins(value) {
  const text = String(value ?? '').trim();
  if (!text || text === '*') return '*';
  return new Set(
    text
      .split(',')
      .map((item) => item.trim())
      .filter(Boolean),
  );
}

function applyCors(req, res, origins) {
  const requestOrigin = firstHeader(req.headers.origin);
  let allowedOrigin = null;
  if (origins === '*') {
    allowedOrigin = '*';
  } else {
    res.setHeader('Vary', 'Origin');
    if (requestOrigin && origins.has(requestOrigin)) allowedOrigin = requestOrigin;
  }
  if (!allowedOrigin) return;

  res.setHeader('Access-Control-Allow-Origin', allowedOrigin);
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', CORS_ALLOW_HEADERS.join(', '));
  res.setHeader(
    'Access-Control-Expose-Headers',
    CORS_EXPOSE_HEADERS.join(', '),
  );
  res.setHeader('Access-Control-Max-Age', '86400');
}

function normalizeUpstream(value) {
  const text = String(value ?? DEFAULT_UPSTREAM).trim();
  const parsed = new URL(text);
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new Error('DEEPSEEK_API_ORIGIN must use http or https');
  }
  return `${parsed.origin}${parsed.pathname}`.replace(/\/+$/, '');
}

function sendJson(res, status, payload) {
  const body = Buffer.from(JSON.stringify(payload));
  res.statusCode = status;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Content-Length', String(body.length));
  res.end(body);
}
