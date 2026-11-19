'use strict';

const { createApp } = require('./app');

(async () => {
  const app = await createApp();
  console.log(`Cholk account server listening on ${app.address}`);
  console.log(`Registration: ${app.config.allowRegistration ? 'enabled' : 'disabled'}`);
  const shutdown = () => app.close().then(() => process.exit(0), () => process.exit(1));
  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
})().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
