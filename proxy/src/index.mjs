import { createProxyServer } from './proxy.mjs';

const port = Number(process.env.PORT ?? 8787);
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  console.error('PORT must be an integer between 1 and 65535');
  process.exit(1);
}

const apiKey = process.env.DEEPSEEK_API_KEY ?? '';
if (!apiKey.trim()) {
  console.error('DEEPSEEK_API_KEY is required');
  process.exit(1);
}

const proxyToken = process.env.PROXY_TOKEN ?? '';
if (!proxyToken.trim()) {
  console.warn(
    '[warn] PROXY_TOKEN is empty. The proxy is unauthenticated; use it only on a trusted local network.',
  );
}

const maxBodyMb = Number(process.env.MAX_BODY_MB ?? 80);
if (!Number.isFinite(maxBodyMb) || maxBodyMb <= 0) {
  console.error('MAX_BODY_MB must be a positive number');
  process.exit(1);
}

const server = createProxyServer({
  upstream: process.env.DEEPSEEK_API_ORIGIN ?? 'https://api.deepseek.com',
  apiKey,
  proxyToken,
  maxBodyBytes: Math.floor(maxBodyMb * 1024 * 1024),
  allowedOrigins: process.env.ALLOWED_ORIGINS ?? '*',
});

server.listen(port, () => {
  const address = server.address();
  const actualPort = typeof address === 'object' && address ? address.port : port;
  console.log(
    `[proxy] listening on http://0.0.0.0:${actualPort} -> ${process.env.DEEPSEEK_API_ORIGIN ?? 'https://api.deepseek.com'}`,
  );
  console.log(
    `[proxy] client auth: ${proxyToken.trim() ? 'PROXY_TOKEN required' : 'disabled'}`,
  );
});

function shutdown(signal) {
  console.log(`[proxy] ${signal} received, shutting down`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(0), 5000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
