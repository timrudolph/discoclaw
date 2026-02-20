import crypto from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { RuntimeAdapter } from '../runtime/types.js';
import type { Db, ConversationRow, MessageRow, MemoryItemRow } from './db.js';
import { nextSeq } from './db.js';
import type { WsHub } from './ws.js';
import type { ServerConfig } from './config.js';
import { invokeRuntime } from './runtime-bridge.js';

export function registerMessageRoutes(
  app: FastifyInstance,
  db: Db,
  hub: WsHub,
  runtime: RuntimeAdapter,
  config: ServerConfig,
): void {
  // GET /conversations/:id/messages
  app.get<{ Params: { id: string } }>('/conversations/:id/messages', async (req, reply) => {
    const conv = db
      .prepare('SELECT * FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as ConversationRow | undefined;

    if (!conv) return reply.notFound();

    const { limit = '50', before } = req.query as { limit?: string; before?: string };
    const limitN = Math.min(Math.max(1, parseInt(limit, 10) || 50), 200);

    let rows: MessageRow[];
    if (before) {
      rows = db
        .prepare(`
          SELECT * FROM messages
          WHERE conversation_id = ? AND seq < ?
          ORDER BY seq ASC
          LIMIT ?
        `)
        .all(conv.id, parseInt(before, 10), limitN) as MessageRow[];
    } else {
      rows = db
        .prepare(`
          SELECT * FROM messages
          WHERE conversation_id = ?
          ORDER BY seq ASC
          LIMIT ?
        `)
        .all(conv.id, limitN) as MessageRow[];
    }

    const total = (db
      .prepare('SELECT COUNT(*) FROM messages WHERE conversation_id = ?')
      .pluck()
      .get(conv.id) as number);

    return {
      messages: rows.map(formatMessage),
      hasMore: rows.length === limitN && total > limitN,
    };
  });

  // POST /conversations/:id/messages
  // Creates the user message, triggers Claude invocation, returns immediately.
  app.post<{ Params: { id: string } }>('/conversations/:id/messages', async (req, reply) => {
    const conv = db
      .prepare('SELECT * FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as ConversationRow | undefined;

    if (!conv) return reply.notFound();

    const { content, clientId } = req.body as { content: string; clientId?: string };
    if (!content?.trim()) return reply.badRequest('content is required');

    const trimmed = content.trim();
    const userMsgId = crypto.randomUUID();
    const userSeq = nextSeq();
    const now = Date.now();

    db.prepare(`
      INSERT INTO messages (id, client_id, conversation_id, role, content, status, seq, created_at, completed_at)
      VALUES (?, ?, ?, 'user', ?, 'complete', ?, ?, ?)
    `).run(userMsgId, clientId ?? null, conv.id, trimmed, userSeq, now, now);

    db.prepare('UPDATE conversations SET updated_at = ? WHERE id = ?').run(now, conv.id);

    // Handle !memory commands locally — no Claude invocation needed
    const memoryResponse = handleMemoryCommand(db, req.user.id, trimmed);
    if (memoryResponse !== null) {
      const assistantId = insertAssistantMessage(db, conv.id, memoryResponse);
      hub.broadcast(req.user.id, {
        type: 'message.complete',
        messageId: assistantId.id,
        conversationId: conv.id,
        content: memoryResponse,
        seq: assistantId.seq,
      });
      reply.status(201).send({
        id: userMsgId,
        seq: userSeq,
        clientId: clientId ?? null,
        status: 'complete',
        assistantMessageId: assistantId.id,
      });
      return;
    }

    // Kick off Claude invocation (non-blocking)
    const assistantId = await invokeRuntime({
      db, hub, runtime, config,
      conversation: conv,
      userMessageContent: trimmed,
    });

    reply.status(201).send({
      id: userMsgId,
      seq: userSeq,
      clientId: clientId ?? null,
      status: 'complete',
      assistantMessageId: assistantId,
    });
  });
}

// ─── Memory command handler ───────────────────────────────────────────────────

/**
 * Handles `!memory` commands. Returns the response string to send as an
 * assistant message, or null if this is not a memory command.
 */
function handleMemoryCommand(db: Db, userId: string, content: string): string | null {
  if (!content.startsWith('!memory')) return null;

  const rest = content.slice('!memory'.length).trim();

  if (rest.startsWith('remember ')) {
    const text = rest.slice('remember '.length).trim();
    if (!text) return 'Nothing to remember — try: `!memory remember <text>`';
    db.prepare(
      'INSERT INTO memory_items (id, user_id, content, created_at) VALUES (?, ?, ?, ?)',
    ).run(crypto.randomUUID(), userId, text, Date.now());
    return `Remembered: "${text}"`;
  }

  if (rest.startsWith('forget ')) {
    const substr = rest.slice('forget '.length).trim().toLowerCase();
    if (!substr) return 'Nothing to forget — try: `!memory forget <substring>`';
    const items = db
      .prepare('SELECT * FROM memory_items WHERE user_id = ? AND deprecated_at IS NULL')
      .all(userId) as MemoryItemRow[];
    const matches = items.filter((i) => i.content.toLowerCase().includes(substr));
    if (matches.length === 0) return `No active memory items match "${substr}"`;
    const now = Date.now();
    for (const m of matches) {
      db.prepare('UPDATE memory_items SET deprecated_at = ? WHERE id = ?').run(now, m.id);
    }
    return `Forgot ${matches.length} item${matches.length === 1 ? '' : 's'} matching "${substr}"`;
  }

  if (rest === 'show' || rest === '') {
    const items = db
      .prepare('SELECT * FROM memory_items WHERE user_id = ? AND deprecated_at IS NULL ORDER BY created_at ASC')
      .all(userId) as MemoryItemRow[];
    if (items.length === 0) return 'No memory items yet. Use `!memory remember <text>` to add one.';
    const lines = items.map((i, idx) => `${idx + 1}. ${i.content}`);
    return `**Memory (${items.length} item${items.length === 1 ? '' : 's'})**\n\n${lines.join('\n')}`;
  }

  return [
    '**Memory commands:**',
    '- `!memory remember <text>` — save a fact',
    '- `!memory forget <substring>` — remove matching items',
    '- `!memory show` — list all items',
  ].join('\n');
}

function insertAssistantMessage(db: Db, conversationId: string, content: string): { id: string; seq: number } {
  const id = crypto.randomUUID();
  const seq = nextSeq();
  const now = Date.now();
  db.prepare(`
    INSERT INTO messages (id, conversation_id, role, content, status, seq, created_at, completed_at)
    VALUES (?, ?, 'assistant', ?, 'complete', ?, ?, ?)
  `).run(id, conversationId, content, seq, now, now);
  return { id, seq };
}

function formatMessage(r: MessageRow) {
  return {
    id: r.id,
    clientId: r.client_id ?? undefined,
    conversationId: r.conversation_id,
    role: r.role,
    content: r.content,
    status: r.status,
    error: r.error ?? undefined,
    seq: r.seq,
    createdAt: r.created_at,
    completedAt: r.completed_at ?? undefined,
  };
}
