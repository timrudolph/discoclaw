import 'dotenv/config';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import Fastify, { type FastifyInstance } from 'fastify';
import websocketPlugin from '@fastify/websocket';
import sensible from '@fastify/sensible';
import pino from 'pino';

import { parseServerConfig } from './config.js';
import { openDb } from './db.js';
import { makeAuthHook, generateToken, hashToken } from './auth.js';
import { WsHub } from './ws.js';
import { registerConversationRoutes } from './conversations.js';
import { registerMessageRoutes } from './messages.js';
import { registerSyncRoutes } from './sync.js';
import { createClaudeCliRuntime } from '../runtime/claude-code-cli.js';
import type { DeviceRow, UserRow, MemoryItemRow } from './db.js';

const PROTECTED_CONVERSATIONS: Record<string, string> = {
  general: 'General',
  tasks:   'Tasks',
  journal: 'Journal',
};

/** Idempotently create a protected conversation of a given kind for a user. */
function ensureProtectedConversation(userId: string, kind: string): void {
  const exists = db
    .prepare('SELECT id FROM conversations WHERE user_id = ? AND kind = ?')
    .get(userId, kind);
  if (exists) return;
  const title = PROTECTED_CONVERSATIONS[kind] ?? kind;
  const now = Date.now();
  db.prepare(`
    INSERT INTO conversations (id, user_id, title, created_at, updated_at, is_protected, kind)
    VALUES (?, ?, ?, ?, ?, 1, ?)
  `).run(crypto.randomUUID(), userId, title, now, now, kind);
  log.info({ userId, kind }, 'server:protected-conversation:created');
}

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const log = pino({ level: process.env.LOG_LEVEL ?? 'info' });

// ─── Config + DB ──────────────────────────────────────────────────────────────

let config;
try {
  config = parseServerConfig(process.env);
} catch (err) {
  log.error({ err }, 'Invalid server configuration');
  process.exit(1);
}

const db = openDb(config.dbPath);
log.info({ dbPath: config.dbPath }, 'database opened');

// ─── Runtime ──────────────────────────────────────────────────────────────────

const runtime = createClaudeCliRuntime({
  claudeBin: config.claudeBin,
  dangerouslySkipPermissions: config.dangerouslySkipPermissions,
  outputFormat: config.outputFormat,
  echoStdio: false,
  verbose: false,
  debugFile: null,
  strictMcpConfig: true,
  fallbackModel: undefined,
  maxBudgetUsd: undefined,
  appendSystemPrompt: undefined,
  sessionScanning: false,
  log,
  multiTurn: false,
  multiTurnHangTimeoutMs: 60_000,
  multiTurnIdleTimeoutMs: 300_000,
  multiTurnMaxProcesses: 5,
  streamStallTimeoutMs: 120_000,
});

// ─── WebSocket hub ────────────────────────────────────────────────────────────

const hub = new WsHub();

// ─── Fastify app ──────────────────────────────────────────────────────────────

const httpsOptions = config.tlsCert && config.tlsKey
  ? { key: fs.readFileSync(config.tlsKey, 'utf8'), cert: fs.readFileSync(config.tlsCert, 'utf8') }
  : undefined;

// Fastify's TypeScript overloads tie the server type to http vs https; cast to
// the common interface so the rest of the file is typed uniformly.
const app: FastifyInstance = httpsOptions
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  ? (Fastify({ logger: false, https: httpsOptions }) as any)
  : Fastify({ logger: false });

await app.register(sensible);
await app.register(websocketPlugin);

const authHook = makeAuthHook(db);

// ─── Health (no auth) ─────────────────────────────────────────────────────────

app.get('/health', async () => ({
  ok: true,
  uptime: Math.floor(process.uptime()),
  connections: hub.connectionCount(),
}));

// ─── Auth routes (no auth hook) ───────────────────────────────────────────────

// POST /auth/register — register a device.
// Single-user: always attaches to the one existing user; creates it on first run.
// Requires SETUP_TOKEN in the request body (set SETUP_TOKEN in .env).
app.post('/auth/register', async (req, reply) => {
  if (!config.setupToken) {
    return reply.status(403).send({ error: 'Registration is disabled. Set SETUP_TOKEN in .env to enable.' });
  }
  const { name, platform, setupToken } = req.body as { name?: string; platform?: string; setupToken?: string };
  if (!setupToken || setupToken !== config.setupToken) {
    log.warn({ ip: req.ip }, 'auth:register:invalid-token');
    return reply.status(401).send({ error: 'Invalid setup token' });
  }

  const token = generateToken();
  const tokenHash = hashToken(token);
  const deviceId = crypto.randomUUID();
  const now = Date.now();

  // Single-user: reuse the existing user row, or create one on first run.
  const existingUser = db.prepare('SELECT id FROM users LIMIT 1').get() as { id: string } | undefined;
  const userId = existingUser?.id ?? crypto.randomUUID();

  db.transaction(() => {
    if (!existingUser) {
      db.prepare('INSERT INTO users (id, name, created_at) VALUES (?, ?, ?)').run(userId, name ?? null, now);
    }
    db.prepare(`
      INSERT INTO devices (id, user_id, name, platform, token_hash, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(deviceId, userId, name ?? null, platform ?? null, tokenHash, now);
  })();

  if (config.generalConversationEnabled) ensureProtectedConversation(userId, 'general');
  if (config.tasksConversationEnabled)   ensureProtectedConversation(userId, 'tasks');
  if (config.journalConversationEnabled) ensureProtectedConversation(userId, 'journal');
  log.info({ userId, deviceId, platform, firstRun: !existingUser }, 'auth:registered');

  // Token is returned once and never stored in plaintext.
  reply.status(201).send({ userId, deviceId, token });
});


// GET /auth/me
app.get('/auth/me', { preHandler: authHook }, async (req) => ({
  user: { id: req.user.id, name: req.user.name },
  device: { id: req.device.id, name: req.device.name, platform: req.device.platform },
}));

// GET /auth/devices — list all registered devices for this user
app.get('/auth/devices', { preHandler: authHook }, async (req) => {
  const devices = db
    .prepare('SELECT id, name, platform, last_seen, created_at FROM devices WHERE user_id = ? ORDER BY created_at ASC')
    .all(req.user.id) as Array<{ id: string; name: string | null; platform: string | null; last_seen: number | null; created_at: number }>;
  return { devices: devices.map(d => ({
    id: d.id,
    name: d.name,
    platform: d.platform,
    lastSeen: d.last_seen,
    createdAt: d.created_at,
    isCurrent: d.id === req.device.id,
  })) };
});

// DELETE /auth/devices/:deviceId
app.delete<{ Params: { deviceId: string } }>(
  '/auth/devices/:deviceId',
  { preHandler: authHook },
  async (req, reply) => {
    const row = db
      .prepare('SELECT id FROM devices WHERE id = ? AND user_id = ?')
      .get(req.params.deviceId, req.user.id) as { id: string } | undefined;

    if (!row) return reply.notFound();

    db.prepare('DELETE FROM devices WHERE id = ?').run(row.id);
    reply.status(204).send();
  },
);

// ─── Memory REST endpoints (authenticated) ────────────────────────────────────

// GET /memory
app.get('/memory', { preHandler: authHook }, async (req) => {
  const items = db
    .prepare('SELECT * FROM memory_items WHERE user_id = ? AND deprecated_at IS NULL ORDER BY created_at ASC')
    .all(req.user.id) as MemoryItemRow[];
  return { items: items.map(m => ({ id: m.id, content: m.content, createdAt: m.created_at })) };
});

// POST /memory
app.post('/memory', { preHandler: authHook }, async (req, reply) => {
  const { content } = req.body as { content?: string };
  if (!content?.trim()) return reply.badRequest('content is required');
  const id = crypto.randomUUID();
  db.prepare('INSERT INTO memory_items (id, user_id, content, created_at) VALUES (?, ?, ?, ?)')
    .run(id, req.user.id, content.trim(), Date.now());
  reply.status(201).send({ id, content: content.trim() });
});

// DELETE /memory/:id
app.delete<{ Params: { id: string } }>('/memory/:id', { preHandler: authHook }, async (req, reply) => {
  const row = db
    .prepare('SELECT id FROM memory_items WHERE id = ? AND user_id = ? AND deprecated_at IS NULL')
    .get(req.params.id, req.user.id) as { id: string } | undefined;
  if (!row) return reply.notFound();
  db.prepare('UPDATE memory_items SET deprecated_at = ? WHERE id = ?').run(Date.now(), row.id);
  reply.status(204).send();
});

// ─── Authenticated routes ─────────────────────────────────────────────────────

// Apply auth to all remaining routes via a scoped plugin
await app.register(async (authed) => {
  authed.addHook('preHandler', authHook);

  registerConversationRoutes(authed, db);
  registerMessageRoutes(authed, db, hub, runtime, config);
  registerSyncRoutes(authed, db);

  // WebSocket — receives auth via ?token= query param (iOS URLSessionWebSocketTask
  // doesn't support custom headers on the upgrade request).
  authed.get('/ws', { websocket: true }, (socket, req) => {
    const userId = req.user.id;
    const unregister = hub.register(userId, socket);
    log.info({ userId, total: hub.connectionCount() }, 'ws:connected');

    socket.on('close', () => {
      unregister();
      log.info({ userId, total: hub.connectionCount() }, 'ws:disconnected');
    });

    socket.on('error', (err) => {
      log.warn({ err, userId }, 'ws:error');
      unregister();
    });

    // Push any in-progress streaming messages so the client is immediately current
    const streaming = db
      .prepare(`
        SELECT m.* FROM messages m
        JOIN conversations c ON c.id = m.conversation_id
        WHERE c.user_id = ? AND m.status IN ('pending', 'streaming')
      `)
      .all(userId) as Array<{ id: string; conversation_id: string; content: string; seq: number }>;

    for (const m of streaming) {
      socket.send(
        JSON.stringify({
          type: 'message.delta',
          messageId: m.id,
          conversationId: m.conversation_id,
          delta: m.content,
          seq: m.seq,
        }),
      );
    }
  });
});

// ─── Start ────────────────────────────────────────────────────────────────────

const shutdown = async () => {
  log.info('shutting down');
  await app.close();
  db.close();
  process.exit(0);
};
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

try {
  await app.listen({ port: config.port, host: config.host });
  const scheme = httpsOptions ? 'https' : 'http';
  log.info({ port: config.port, host: config.host, tls: !!httpsOptions, setupToken: !!config.setupToken }, 'server started');
  if (!config.setupToken) log.warn('SETUP_TOKEN not set — registration is disabled');
  if (!httpsOptions) log.warn('TLS not configured — traffic is unencrypted (set TLS_CERT and TLS_KEY)');
  // Ensure protected conversations exist for any already-registered users.
  const users = db.prepare('SELECT id FROM users').all() as { id: string }[];
  for (const u of users) {
    if (config.generalConversationEnabled) ensureProtectedConversation(u.id, 'general');
    if (config.tasksConversationEnabled)   ensureProtectedConversation(u.id, 'tasks');
    if (config.journalConversationEnabled) ensureProtectedConversation(u.id, 'journal');
  }
} catch (err) {
  log.error({ err }, 'failed to start server');
  process.exit(1);
}
