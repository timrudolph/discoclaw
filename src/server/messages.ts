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

    // Handle @BotName cross-conv mentions
    const mentionAssistantId = await handleMentionCommand(db, hub, runtime, config, conv, trimmed);
    if (mentionAssistantId !== null) {
      reply.status(201).send({
        id: userMsgId,
        seq: userSeq,
        clientId: clientId ?? null,
        status: 'complete',
        assistantMessageId: mentionAssistantId,
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

// ─── Cross-conv @mention handler ─────────────────────────────────────────────

function findOrCreateShadow(
  db: Db,
  botConv: ConversationRow,
  originConv: ConversationRow,
): ConversationRow {
  const existing = db
    .prepare('SELECT * FROM conversations WHERE shadow_for = ? AND shadow_origin = ?')
    .get(botConv.id, originConv.id) as ConversationRow | undefined;
  if (existing) return existing;

  const shadowId = crypto.randomUUID();
  const now = Date.now();
  db.prepare(`
    INSERT INTO conversations
      (id, user_id, title, assistant_name, accent_color, model_override, workspace_path,
       context_modules, kind, shadow_for, shadow_origin, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'shadow', ?, ?, ?, ?)
  `).run(
    shadowId, botConv.user_id,
    `${botConv.assistant_name ?? 'Bot'} (cross-chat)`,
    botConv.assistant_name, botConv.accent_color, botConv.model_override,
    botConv.workspace_path, botConv.context_modules,
    botConv.id, originConv.id, now, now,
  );
  return db.prepare('SELECT * FROM conversations WHERE id = ?').get(shadowId) as ConversationRow;
}

/**
 * Handles `@BotName message` cross-conversation mentions.
 * Resolves the bot by assistantName, finds/creates a shadow conversation,
 * invokes the bot's runtime using shadow context, and routes the response
 * back into the originating conversation. Returns the assistant message ID,
 * or null if no matching bot was found (message passes through to Claude).
 */
async function handleMentionCommand(
  db: Db,
  hub: WsHub,
  runtime: RuntimeAdapter,
  config: ServerConfig,
  originConv: ConversationRow,
  content: string,
): Promise<string | null> {
  const match = content.match(/^@(\S+)\s*([\s\S]*)/);
  if (!match) return null;

  const [, mentionName, restContent] = match;

  const botConv = db
    .prepare("SELECT * FROM conversations WHERE user_id = ? AND LOWER(assistant_name) = LOWER(?)")
    .get(originConv.user_id, mentionName) as ConversationRow | undefined;

  // No matching bot — let the message pass through to the current conversation's Claude.
  if (!botConv) return null;

  // Prevent self-mentions and mentioning the current conversation.
  if (botConv.id === originConv.id) return null;

  const shadowConv = findOrCreateShadow(db, botConv, originConv);
  const messageContent = restContent.trim() || mentionName;

  const assistantId = crypto.randomUUID();
  const assistantSeq = nextSeq();
  const now = Date.now();

  // Pre-create the pending assistant message in the origin conv, attributed to the bot.
  db.prepare(`
    INSERT INTO messages (id, conversation_id, role, content, status, seq, created_at, source_conversation_id)
    VALUES (?, ?, 'assistant', '', 'pending', ?, ?, ?)
  `).run(assistantId, originConv.id, assistantSeq, now, botConv.id);

  // Also save the user message in the shadow conv (with attribution) so the bot
  // has context for this cross-conv thread.
  const shadowUserSeq = nextSeq();
  db.prepare(`
    INSERT INTO messages (id, conversation_id, role, content, status, seq, created_at, completed_at)
    VALUES (?, ?, 'user', ?, 'complete', ?, ?, ?)
  `).run(
    crypto.randomUUID(), shadowConv.id,
    `[Cross-chat from "${originConv.title ?? 'another conversation'}"]: ${messageContent}`,
    shadowUserSeq, now, now,
  );

  // Invoke the bot's runtime via the shadow conv context, routing output to origin conv.
  void invokeRuntime({
    db, hub, runtime, config,
    conversation: shadowConv,
    userMessageContent: messageContent,
    responseConversationId: originConv.id,
    responseAssistantMessageId: assistantId,
    responseAssistantSeq: assistantSeq,
  });

  return assistantId;
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
      if (!config.geminiApiKey) throw new Error('GEMINI_API_KEY is not configured');

      const workspacePath = conv.workspace_path ?? config.workspaceCwd;
      let identity = '';
      try {
        const raw = await fs.promises.readFile(path.join(workspacePath, 'IDENTITY.md'), 'utf8');
        identity = raw.trim();
      } catch { /* no IDENTITY.md */ }

      const promptParts = [
        'Pixar-style animated character portrait.',
        identity ? `Character description:\n${identity}` : 'A friendly AI assistant.',
        extraPrompt ? `Additional details: ${extraPrompt}` : '',
        'Subsurface scattering skin glow, expressive oversized eyes, smooth volumetric lighting, warm and likeable. No text or labels. Square crop, face fills the frame.',
      ].filter(Boolean);

      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:generateContent?key=${config.geminiApiKey}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            contents: [{ parts: [{ text: promptParts.join(' ') }] }],
            generationConfig: { responseModalities: ['IMAGE'] },
          }),
        },
      );

      if (!response.ok) {
        const err = await response.text();
        throw new Error(`Gemini API error ${response.status}: ${err}`);
      }

      type GeminiPart = { text?: string; inlineData?: { mimeType: string; data: string } };
      type GeminiResponse = { candidates: Array<{ content: { parts: GeminiPart[] } }> };
      const data = await response.json() as GeminiResponse;
      const imagePart = data.candidates[0]?.content.parts.find((p) => p.inlineData);
      if (!imagePart?.inlineData) throw new Error('No image in Gemini response');

      const png = await sharp(Buffer.from(imagePart.inlineData.data, 'base64'))
        .resize(512, 512)
        .png()
        .toBuffer();

      await fs.promises.writeFile(path.join(config.avatarsDir, `conv-${conv.id}.png`), png);

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
 * Gemini image generation in the background, and returns the assistant
 * message ID (signals "handled"). Returns null if not an `!avatar` command.
 */
function handleAvatarCommand(
  db: Db,
  hub: WsHub,
  config: ServerConfig,
  conv: ConversationRow,
  content: string,
): string | null {
  if (!content.startsWith('!avatar')) return null;

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
