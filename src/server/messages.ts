import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import sharp from 'sharp';
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
    const memoryResponse = handleMemoryCommand(db, req.user.id, conv.id, trimmed);
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

    // Handle !avatar command — generates SVG via Claude Haiku, converts to JPEG
    const avatarAssistantId = handleAvatarCommand(db, hub, config, conv, trimmed);
    if (avatarAssistantId !== null) {
      reply.status(201).send({
        id: userMsgId,
        seq: userSeq,
        clientId: clientId ?? null,
        status: 'complete',
        assistantMessageId: avatarAssistantId,
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
 * Memory items are scoped to the conversation (not global).
 */
function handleMemoryCommand(db: Db, userId: string, conversationId: string, content: string): string | null {
  if (!content.startsWith('!memory')) return null;

  const rest = content.slice('!memory'.length).trim();

  if (rest.startsWith('remember ')) {
    const text = rest.slice('remember '.length).trim();
    if (!text) return 'Nothing to remember — try: `!memory remember <text>`';
    db.prepare(
      'INSERT INTO memory_items (id, user_id, conversation_id, content, created_at) VALUES (?, ?, ?, ?, ?)',
    ).run(crypto.randomUUID(), userId, conversationId, text, Date.now());
    return `Remembered: "${text}"`;
  }

  if (rest.startsWith('forget ')) {
    const substr = rest.slice('forget '.length).trim().toLowerCase();
    if (!substr) return 'Nothing to forget — try: `!memory forget <substring>`';
    const items = db
      .prepare('SELECT * FROM memory_items WHERE conversation_id = ? AND deprecated_at IS NULL')
      .all(conversationId) as MemoryItemRow[];
    const matches = items.filter((i) => i.content.toLowerCase().includes(substr));
    if (matches.length === 0) return `No chat memory items match "${substr}"`;
    const now = Date.now();
    for (const m of matches) {
      db.prepare('UPDATE memory_items SET deprecated_at = ? WHERE id = ?').run(now, m.id);
    }
    return `Forgot ${matches.length} item${matches.length === 1 ? '' : 's'} matching "${substr}"`;
  }

  if (rest === 'show' || rest === '') {
    const items = db
      .prepare('SELECT * FROM memory_items WHERE conversation_id = ? AND deprecated_at IS NULL ORDER BY created_at ASC')
      .all(conversationId) as MemoryItemRow[];
    if (items.length === 0) return 'No chat memory yet. Use `!memory remember <text>` to add one.';
    const lines = items.map((i, idx) => `${idx + 1}. ${i.content}`);
    return `**Chat Memory (${items.length} item${items.length === 1 ? '' : 's'})**\n\n${lines.join('\n')}`;
  }

  return [
    '**Memory commands:**',
    '- `!memory remember <text>` — save a fact to this chat',
    '- `!memory forget <substring>` — remove matching items',
    '- `!memory show` — list all items',
  ].join('\n');
}

// ─── Avatar command handler ───────────────────────────────────────────────────

function generateAvatarInBackground(
  db: Db,
  hub: WsHub,
  config: ServerConfig,
  conv: ConversationRow,
  assistantId: string,
  assistantSeq: number,
  extraPrompt: string,
): void {
  void (async () => {
    try {
      const workspacePath = conv.workspace_path ?? config.workspaceCwd;
      let identity = '';
      try {
        const raw = await fs.promises.readFile(path.join(workspacePath, 'IDENTITY.md'), 'utf8');
        identity = raw.trim();
      } catch { /* no identity — generate generic avatar */ }

      const characterDesc = identity
        ? `Character description from IDENTITY.md:\n\n${identity}`
        : 'A friendly AI assistant.';

      const userPrompt = [
        'Generate a square SVG avatar (viewBox="0 0 512 512") for an AI assistant character.',
        characterDesc,
        extraPrompt ? `Additional notes: ${extraPrompt}` : '',
        'Requirements:',
        '- Output ONLY the SVG code. Start with <svg and end with </svg>. No markdown, no explanation.',
        '- Use vibrant colors and simple bold shapes suitable for a profile picture.',
        '- No external images or fonts. No text or labels.',
        '- Keep it simple — flat or lightly shaded illustration style.',
      ].filter(Boolean).join('\n');

      const response = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'x-api-key': config.anthropicApiKey!,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        body: JSON.stringify({
          model: 'claude-haiku-4-5-20251001',
          max_tokens: 4096,
          messages: [{ role: 'user', content: userPrompt }],
        }),
      });

      if (!response.ok) throw new Error(`Anthropic API error: ${response.status}`);
      const data = await response.json() as { content: Array<{ type: string; text: string }> };
      const text = data.content.find((b) => b.type === 'text')?.text ?? '';

      const svgMatch = text.match(/<svg[\s\S]*<\/svg>/i);
      if (!svgMatch) throw new Error('No SVG found in Claude response');
      const svg = svgMatch[0];

      const jpeg = await sharp(Buffer.from(svg))
        .resize(512, 512)
        .jpeg({ quality: 90 })
        .toBuffer();

      await fs.promises.writeFile(path.join(config.avatarsDir, `conv-${conv.id}.jpg`), jpeg);

      const completedAt = Date.now();
      db.prepare("UPDATE messages SET status = 'complete', content = ?, completed_at = ? WHERE id = ?")
        .run('Avatar generated ✓', completedAt, assistantId);

      hub.broadcast(conv.user_id, {
        type: 'message.complete',
        messageId: assistantId,
        conversationId: conv.id,
        content: 'Avatar generated ✓',
        seq: assistantSeq,
      });
      hub.broadcast(conv.user_id, {
        type: 'conversation.updated',
        conversationId: conv.id,
      });
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      db.prepare("UPDATE messages SET status = 'error', error = ? WHERE id = ?").run(msg, assistantId);
      hub.broadcast(conv.user_id, {
        type: 'message.error',
        messageId: assistantId,
        conversationId: conv.id,
        error: msg,
      });
    }
  })();
}

/**
 * Handles `!avatar` command. Inserts a pending assistant message, fires
 * SVG generation in the background, and returns the assistant message ID
 * (signals "handled"). Returns null if this is not an `!avatar` command.
 * Returns an error message string when ANTHROPIC_API_KEY is missing.
 */
function handleAvatarCommand(
  db: Db,
  hub: WsHub,
  config: ServerConfig,
  conv: ConversationRow,
  content: string,
): string | null {
  if (!content.startsWith('!avatar')) return null;

  if (!config.anthropicApiKey) {
    const { id } = insertAssistantMessage(
      db,
      conv.id,
      'Avatar generation requires `ANTHROPIC_API_KEY` to be configured on the server.',
    );
    return id;
  }

  const extraPrompt = content.slice('!avatar'.length).trim();
  const assistantId = crypto.randomUUID();
  const assistantSeq = nextSeq();
  const now = Date.now();

  db.prepare(`
    INSERT INTO messages (id, conversation_id, role, content, status, seq, created_at)
    VALUES (?, ?, 'assistant', 'Generating avatar…', 'pending', ?, ?)
  `).run(assistantId, conv.id, assistantSeq, now);

  generateAvatarInBackground(db, hub, config, conv, assistantId, assistantSeq, extraPrompt);

  return assistantId;
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
