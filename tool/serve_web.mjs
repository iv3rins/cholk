import http from 'node:http';
import { createReadStream } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath } from 'node:url';

const root = path.resolve(process.argv[2] ?? 'build/web');
const port = Number(process.env.PORT ?? 8090);
const host = process.env.HOST ?? '127.0.0.1';
const testApi = process.env.TEST_OPENAI_BASE_URL?.replace(/\/+$/, '');
const testKey = process.env.TEST_OPENAI_API_KEY;
if (testApi && (!testKey || host !== '127.0.0.1')) {
  throw new Error('The test API relay requires an API key and loopback binding');
}
let nextRequestId = 0;
const mobilePreview = fileURLToPath(
  new URL('./mobile-preview.html', import.meta.url),
);

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.otf': 'font/otf',
  '.ttf': 'font/ttf',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.map': 'application/json; charset=utf-8',
};

const server = http.createServer(async (req, res) => {
  let url;
  let pathname;
  try {
    url = new URL(req.url ?? '/', 'http://localhost');
    pathname = decodeURIComponent(url.pathname);
  } catch {
    res.writeHead(400).end('Invalid request path');
    return;
  }
  if (testApi && url.pathname.startsWith('/v1/')) {
    await relayTestApi(req, res, url.pathname);
    return;
  }
  if (url.pathname === '/mobile' || url.pathname === '/mobile/') {
    try {
      const html = await readFile(mobilePreview);
      res.writeHead(200, {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
      });
      res.end(html);
    } catch {
      res.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('Mobile preview template is missing');
    }
    return;
  }
  let filePath = path.join(root, pathname);
  const relativePath = path.relative(root, filePath);
  if (
    relativePath === '..' ||
    relativePath.startsWith(`..${path.sep}`) ||
    path.isAbsolute(relativePath)
  ) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }
  try {
    const info = await stat(filePath);
    if (info.isDirectory()) filePath = path.join(filePath, 'index.html');
    const fileInfo = await stat(filePath);
    if (!fileInfo.isFile()) throw new Error('not a file');
  } catch {
    filePath = path.join(root, 'index.html');
  }
  const ext = path.extname(filePath).toLowerCase();
  const headers = {
    'content-type': MIME[ext] ?? 'application/octet-stream',
    'cache-control': 'no-store',
  };
  try {
    const info = await stat(filePath);
    headers['content-length'] = String(info.size);
    res.writeHead(200, headers);
    await pipeline(createReadStream(filePath), res);
  } catch {
    if (!res.headersSent) {
      res.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      res.end('Not found');
    }
  }
});

server.listen(port, host, () => {
  console.log(`[web] serving ${root}`);
  console.log(`[web] http://${host}:${port}`);
  if (testApi) console.log(`[test-api] ${testApi}`);
});

async function relayTestApi(req, res, pathname) {
  const isChat = req.method === 'POST' && pathname === '/v1/chat/completions';
  if (!isChat && !(req.method === 'GET' && pathname === '/v1/models')) {
    res.writeHead(404).end();
    return;
  }
  if (req.headers.authorization !== 'Bearer local-preview') {
    res.writeHead(401).end();
    return;
  }

  const id = ++nextRequestId;
  const started = Date.now();
  const tag = `[test-api #${id}] ${req.method} ${pathname}`;
  const controller = new AbortController();
  res.once('close', () => {
    if (!res.writableFinished) controller.abort();
  });
  console.info(`${tag} -> upstream`);
  try {
    const upstream = await fetch(`${testApi}${pathname.slice('/v1'.length)}`, {
      method: req.method,
      headers: {
        authorization: `Bearer ${testKey}`,
        accept: isChat ? 'text/event-stream, application/json' : 'application/json',
        ...(isChat ? { 'content-type': 'application/json' } : {}),
      },
      ...(isChat ? { body: req, duplex: 'half' } : {}),
      redirect: 'error',
      signal: controller.signal,
    });
    const contentType = upstream.headers.get('content-type') ?? 'application/octet-stream';
    const requestId = upstream.headers.get('x-request-id');
    console.info(`${tag} <- ${upstream.status} ${Date.now() - started}ms${requestId ? ` request_id=${requestId}` : ''}`);
    res.writeHead(upstream.status, { 'content-type': contentType, 'cache-control': 'no-store' });
    res.flushHeaders();
    if (upstream.body) await pipeline(Readable.fromWeb(upstream.body), res);
    else res.end();
    console.info(`${tag} finished ${Date.now() - started}ms`);
  } catch (error) {
    if (controller.signal.aborted) {
      console.info(`${tag} disconnected ${Date.now() - started}ms`);
      return;
    }
    console.error(`${tag} failed ${Date.now() - started}ms (${error.cause?.code ?? error.name})`);
    if (res.headersSent) res.destroy();
    else res.writeHead(502, { 'content-type': 'application/json' })
      .end(JSON.stringify({ error: { message: 'Test upstream request failed' } }));
  }
}
