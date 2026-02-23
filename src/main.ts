/**
 * Unified entry point.
 *
 * Controls which components start via env vars:
 *   DISCOCLAW_DISCORD_ENABLED=1   (default: 1) — Discord bot
 *   DISCOCLAW_SERVER_ENABLED=1    (default: 0) — native client server
 *
 * At least one must be enabled.
 */
import 'dotenv/config';
import pino from 'pino';

const log = pino({ level: process.env.LOG_LEVEL ?? 'info' });

function boolEnv(key: string, fallback: boolean): boolean {
  const v = process.env[key]?.trim().toLowerCase();
  if (!v) return fallback;
  if (v === '1' || v === 'true') return true;
  if (v === '0' || v === 'false') return false;
  log.error(`${key} must be 0/1 or true/false, got "${process.env[key]}"`);
  process.exit(1);
}

const discordEnabled = boolEnv('DISCOCLAW_DISCORD_ENABLED', true);
const serverEnabled  = boolEnv('DISCOCLAW_SERVER_ENABLED',  false);

if (!discordEnabled && !serverEnabled) {
  log.error(
    'Nothing to start — set DISCOCLAW_DISCORD_ENABLED=1 and/or DISCOCLAW_SERVER_ENABLED=1',
  );
  process.exit(1);
}

const starts: Promise<unknown>[] = [];

if (discordEnabled) {
  log.info('component:discord starting');
  starts.push(import('./index.js'));
}

if (serverEnabled) {
  log.info('component:server starting');
  starts.push(import('./server/index.js'));
}

await Promise.all(starts);
