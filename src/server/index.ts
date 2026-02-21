import 'dotenv/config';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { Buffer } from 'node:buffer';
import { fileURLToPath } from 'node:url';
import Fastify, { type FastifyInstance } from 'fastify';
import websocketPlugin from '@fastify/websocket';
import sensible from '@fastify/sensible';
import pino from 'pino';

import { parseServerConfig } from './config.js';
import type { ServerConfig } from './config.js';
import { openDb } from './db.js';
import { makeAuthHook, generateToken, hashToken } from './auth.js';
import { WsHub } from './ws.js';
import { registerConversationRoutes } from './conversations.js';
import { registerMessageRoutes } from './messages.js';
import { registerSyncRoutes } from './sync.js';
import { registerBeadsRoutes } from './beads.js';
import { registerCronRoutes } from './crons.js';
import { ServerCronScheduler } from './cron-scheduler.js';
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

let config: ServerConfig;
try {
  config = parseServerConfig(process.env);
} catch (err) {
  log.error({ err }, 'Invalid server configuration');
  process.exit(1);
}

const db = openDb(config.dbPath);
log.info({ dbPath: config.dbPath }, 'database opened');

// Create avatars directory (idempotent)
fs.mkdirSync(config.avatarsDir, { recursive: true });

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

// ─── Cron scheduler ───────────────────────────────────────────────────────────
// Instantiated here (before routes); .start() called after server binds.

const cronScheduler = new ServerCronScheduler(db, hub, runtime, config);

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

// Raw binary parser for avatar image uploads (image/jpeg)
app.addContentTypeParser('image/jpeg', { parseAs: 'buffer' }, (_req, body, done) => {
  done(null, body);
});

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

// PATCH /auth/me — update the authenticated user's profile (name)
app.patch('/auth/me', { preHandler: authHook }, async (req) => {
  const { name } = req.body as { name?: string | null };
  if (name !== undefined) {
    db.prepare('UPDATE users SET name = ? WHERE id = ?').run(name ?? null, req.user.id);
  }
  const user = db.prepare('SELECT id, name FROM users WHERE id = ?').get(req.user.id) as UserRow;
  return { user: { id: user.id, name: user.name } };
});

// ─── Avatar endpoints (authenticated) ─────────────────────────────────────────

const MAX_AVATAR_BYTES = 2 * 1024 * 1024; // 2 MB

// PUT /auth/avatar — upload the user's JPEG avatar
app.put('/auth/avatar', { preHandler: authHook, bodyLimit: MAX_AVATAR_BYTES }, async (req, reply) => {
  const ct = req.headers['content-type'];
  if (!ct?.startsWith('image/jpeg')) return reply.status(415).send({ error: 'Content-Type must be image/jpeg' });
  const body = req.body as Buffer;
  if (body.length > MAX_AVATAR_BYTES) return reply.status(413).send({ error: 'Image too large (max 2 MB)' });
  const filePath = path.join(config.avatarsDir, `user-${req.user.id}.jpg`);
  await fs.promises.writeFile(filePath, body);
  reply.status(204).send();
});

// GET /auth/avatar — serve the user's JPEG avatar
app.get('/auth/avatar', { preHandler: authHook }, async (req, reply) => {
  const filePath = path.join(config.avatarsDir, `user-${req.user.id}.jpg`);
  try {
    const stat = await fs.promises.stat(filePath);
    reply.header('Content-Type', 'image/jpeg');
    reply.header('Content-Length', String(stat.size));
    reply.header('Cache-Control', 'max-age=86400');
    return reply.send(fs.createReadStream(filePath));
  } catch {
    return reply.status(404).send();
  }
});

// PUT /conversations/:id/avatar — upload the assistant's JPEG avatar for a conversation
app.put<{ Params: { id: string } }>(
  '/conversations/:id/avatar',
  { preHandler: authHook, bodyLimit: MAX_AVATAR_BYTES },
  async (req, reply) => {
    const conv = db
      .prepare('SELECT id FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as { id: string } | undefined;
    if (!conv) return reply.notFound();

    const ct = req.headers['content-type'];
    if (!ct?.startsWith('image/jpeg')) return reply.status(415).send({ error: 'Content-Type must be image/jpeg' });
    const body = req.body as Buffer;
    if (body.length > MAX_AVATAR_BYTES) return reply.status(413).send({ error: 'Image too large (max 2 MB)' });
    const filePath = path.join(config.avatarsDir, `conv-${conv.id}.jpg`);
    await fs.promises.writeFile(filePath, body);
    reply.status(204).send();
  },
);

// GET /conversations/:id/avatar — serve the assistant's JPEG avatar for a conversation
app.get<{ Params: { id: string } }>(
  '/conversations/:id/avatar',
  { preHandler: authHook },
  async (req, reply) => {
    const conv = db
      .prepare('SELECT id FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as { id: string } | undefined;
    if (!conv) return reply.notFound();

    const filePath = path.join(config.avatarsDir, `conv-${conv.id}.jpg`);
    try {
      const stat = await fs.promises.stat(filePath);
      reply.header('Content-Type', 'image/jpeg');
      reply.header('Content-Length', String(stat.size));
      reply.header('Cache-Control', 'max-age=86400');
      return reply.send(fs.createReadStream(filePath));
    } catch {
      return reply.status(404).send();
    }
  },
);

// ─── Workspace file endpoints (authenticated) ─────────────────────────────────

const WORKSPACE_ALLOWED = new Set(['SOUL.md', 'IDENTITY.md', 'USER.md', 'AGENTS.md', 'MEMORY.md', 'TOOLS.md']);

function workspaceFilePath(filename: string): string | null {
  if (!WORKSPACE_ALLOWED.has(filename)) return null;
  return path.join(config.workspaceCwd, filename);
}

// GET /workspace/files — list workspace files with preview
app.get('/workspace/files', { preHandler: authHook }, async () => {
  const files = await Promise.all(
    [...WORKSPACE_ALLOWED].map(async (name) => {
      const filePath = path.join(config.workspaceCwd, name);
      try {
        const content = await fs.promises.readFile(filePath, 'utf8');
        const preview = content.split('\n').find(l => l.trim())?.slice(0, 120) ?? '';
        return { name, exists: true, preview };
      } catch {
        return { name, exists: false, preview: '' };
      }
    }),
  );
  return { files };
});

// GET /workspace/files/:name — get file content
app.get<{ Params: { name: string } }>('/workspace/files/:name', { preHandler: authHook }, async (req, reply) => {
  const filePath = workspaceFilePath(req.params.name);
  if (!filePath) return reply.forbidden('File not in allowed list');
  try {
    const content = await fs.promises.readFile(filePath, 'utf8');
    return { name: req.params.name, content };
  } catch {
    return { name: req.params.name, content: '' };
  }
});

// PUT /workspace/files/:name — write file content
app.put<{ Params: { name: string } }>('/workspace/files/:name', { preHandler: authHook }, async (req, reply) => {
  const filePath = workspaceFilePath(req.params.name);
  if (!filePath) return reply.forbidden('File not in allowed list');
  const { content } = req.body as { content?: string };
  if (content === undefined) return reply.badRequest('content is required');
  await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
  await fs.promises.writeFile(filePath, content, 'utf8');
  reply.status(204).send();
});

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

// ─── Available models (Claude Code model aliases) ─────────────────────────────

const AVAILABLE_MODELS = [
  { id: 'opus',   label: 'Claude Opus',   description: 'Most capable' },
  { id: 'sonnet', label: 'Claude Sonnet', description: 'Balanced' },
  { id: 'haiku',  label: 'Claude Haiku',  description: 'Fast & efficient' },
] as const;

app.get('/models', { preHandler: authHook }, async () => ({
  models: AVAILABLE_MODELS,
  default: config.runtimeModel,
}));

// ─── Context modules ──────────────────────────────────────────────────────────

// Only the README is excluded — it's documentation, not context.
// All other .md files (including ops, discord, runtime, etc.) can be attached by the user.
const CONTEXT_MODULE_BLOCKLIST = new Set(['README.md']);

// GET /context-modules — list available (non-blocked) context modules
app.get('/context-modules', { preHandler: authHook }, async () => {
  let files: string[];
  try {
    files = await fs.promises.readdir(config.contextDir);
  } catch {
    return { modules: [] };
  }
  const mdFiles = files
    .filter((f) => f.endsWith('.md') && !CONTEXT_MODULE_BLOCKLIST.has(f))
    .sort();
  const modules = await Promise.all(
    mdFiles.map(async (name) => {
      const filePath = path.join(config.contextDir, name);
      try {
        const content = await fs.promises.readFile(filePath, 'utf8');
        const firstHeading = content.split('\n').find((l) => l.startsWith('#'))?.replace(/^#+\s*/, '') ?? name;
        return { name, label: firstHeading };
      } catch {
        return { name, label: name };
      }
    }),
  );
  return { modules };
});

// GET /conversations/:id/context-modules
app.get<{ Params: { id: string } }>(
  '/conversations/:id/context-modules',
  { preHandler: authHook },
  async (req, reply) => {
    const conv = db
      .prepare('SELECT context_modules FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as { context_modules: string | null } | undefined;
    if (!conv) return reply.notFound();
    return { modules: conv.context_modules ? JSON.parse(conv.context_modules) as string[] : [] };
  },
);

// PUT /conversations/:id/context-modules
app.put<{ Params: { id: string } }>(
  '/conversations/:id/context-modules',
  { preHandler: authHook },
  async (req, reply) => {
    const { modules } = req.body as { modules?: unknown };
    if (!Array.isArray(modules)) return reply.badRequest('modules must be an array');
    const conv = db
      .prepare('SELECT id FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as { id: string } | undefined;
    if (!conv) return reply.notFound();
    db.prepare('UPDATE conversations SET context_modules = ? WHERE id = ?')
      .run(JSON.stringify(modules), conv.id);
    reply.status(204).send();
  },
);

// POST /context-modules — create a new context module file
app.post('/context-modules', { preHandler: authHook }, async (req, reply) => {
  const { name, content } = req.body as { name?: unknown; content?: unknown };
  if (typeof name !== 'string' || !name.trim()) return reply.badRequest('name is required');
  if (typeof content !== 'string') return reply.badRequest('content is required');

  // Sanitize: allow alphanumeric, hyphens, underscores, dots; force .md extension
  const baseName = name.trim().replace(/\.md$/i, '');
  const safeName = baseName.replace(/[^a-zA-Z0-9._-]/g, '-') + '.md';

  if (CONTEXT_MODULE_BLOCKLIST.has(safeName)) return reply.forbidden('reserved name');

  const filePath = path.join(config.contextDir, safeName);
  try {
    await fs.promises.access(filePath);
    return reply.conflict('a module with that name already exists');
  } catch {
    // file doesn't exist — proceed
  }

  await fs.promises.mkdir(config.contextDir, { recursive: true });
  await fs.promises.writeFile(filePath, content, 'utf8');
  const firstHeading =
    content
      .split('\n')
      .find((l: string) => l.startsWith('#'))
      ?.replace(/^#+\s*/, '') ?? safeName;
  return reply.status(201).send({ name: safeName, label: firstHeading });
});

// DELETE /context-modules/:name — delete a custom context module file
app.delete<{ Params: { name: string } }>(
  '/context-modules/:name',
  { preHandler: authHook },
  async (req, reply) => {
    const { name } = req.params;
    if (!name.endsWith('.md')) return reply.badRequest('name must end with .md');
    if (CONTEXT_MODULE_BLOCKLIST.has(name)) return reply.forbidden('reserved name');

    // Sanitize: reject any path traversal
    if (name.includes('/') || name.includes('\\') || name.startsWith('.')) {
      return reply.badRequest('invalid name');
    }

    const filePath = path.join(config.contextDir, name);
    try {
      await fs.promises.unlink(filePath);
    } catch (err: unknown) {
      if ((err as NodeJS.ErrnoException).code === 'ENOENT') return reply.notFound();
      throw err;
    }
    return reply.status(204).send();
  },
);

// ─── Authenticated routes ─────────────────────────────────────────────────────

// Apply auth to all remaining routes via a scoped plugin
await app.register(async (authed) => {
  authed.addHook('preHandler', authHook);

  registerConversationRoutes(authed, db);
  registerMessageRoutes(authed, db, hub, runtime, config);
  registerSyncRoutes(authed, db);
  registerBeadsRoutes(authed, db, hub);
  registerCronRoutes(authed, db, cronScheduler);

  // GET /search?q=<text>&limit=20 — full-text search across message content
  authed.get('/search', async (req) => {
    const { q, limit = '20' } = req.query as { q?: string; limit?: string };
    const query = q?.trim() ?? '';
    if (!query) return { results: [] };

    const maxRows = Math.min(Math.max(1, parseInt(limit, 10) || 20), 100);
    const pattern = `%${query}%`;

    const rows = db.prepare(`
      SELECT m.id, m.conversation_id, m.content, m.role, m.seq, m.created_at,
             c.title AS conversation_title
        FROM messages m
        JOIN conversations c ON c.id = m.conversation_id
       WHERE c.user_id = ?
         AND m.status = 'complete'
         AND m.content LIKE ?
       ORDER BY m.created_at DESC
       LIMIT ?
    `).all(req.user.id, pattern, maxRows) as Array<{
      id: string;
      conversation_id: string;
      content: string;
      role: string;
      seq: number;
      created_at: number;
      conversation_title: string | null;
    }>;

    return {
      results: rows.map((r) => ({
        messageId: r.id,
        conversationId: r.conversation_id,
        conversationTitle: r.conversation_title ?? 'Untitled',
        role: r.role,
        snippet: r.content.slice(0, 200),
        createdAt: r.created_at,
      })),
    };
  });

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
  cronScheduler.stop();
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
  cronScheduler.start();
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
