import type { FastifyInstance } from 'fastify';
import type { Db, ConversationRow, MessageRow } from './db.js';

export function registerSyncRoutes(app: FastifyInstance, db: Db): void {
  // GET /sync?since=<seq>
  // Returns all conversations and messages modified after `since`.
  // The client stores the returned `cursor` and passes it on the next call.
  app.get('/sync', async (req) => {
    const { since = '0' } = req.query as { since?: string };
    const sinceSeq = parseInt(since, 10) || 0;

    const conversations = db
      .prepare(`
        SELECT * FROM conversations
        WHERE user_id = ? AND updated_at > ?
        ORDER BY updated_at ASC
      `)
      .all(req.user.id, sinceSeq) as ConversationRow[];

    // Fetch messages for those conversations (or any message with seq > since)
    const messages = db
      .prepare(`
        SELECT m.* FROM messages m
        JOIN conversations c ON c.id = m.conversation_id
        WHERE c.user_id = ? AND m.seq > ?
        ORDER BY m.seq ASC
      `)
      .all(req.user.id, sinceSeq) as MessageRow[];

    // Advance the device's stored cursor
    const cursor =
      messages.length > 0
        ? messages[messages.length - 1].seq
        : conversations.length > 0
          ? Math.max(...conversations.map((c) => c.updated_at))
          : sinceSeq;

    db.prepare(`
      INSERT INTO sync_cursors (device_id, last_seq, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(device_id) DO UPDATE SET last_seq = excluded.last_seq, updated_at = excluded.updated_at
    `).run(req.device.id, cursor, Date.now());

    return {
      conversations: conversations.map((c) => ({
        id: c.id,
        title: c.title,
        isProtected: c.is_protected === 1,
        kind: c.kind ?? undefined,
        modelOverride: c.model_override ?? undefined,
        assistantName: c.assistant_name ?? undefined,
        accentColor: c.accent_color ?? undefined,
        claudeSessionId: c.claude_session_id ?? undefined,
        updatedAt: c.updated_at,
        createdAt: c.created_at,
        archivedAt: c.archived_at ?? undefined,
      })),
      messages: messages.map((m) => ({
        id: m.id,
        clientId: m.client_id ?? undefined,
        conversationId: m.conversation_id,
        role: m.role,
        content: m.content,
        status: m.status,
        error: m.error ?? undefined,
        seq: m.seq,
        createdAt: m.created_at,
        completedAt: m.completed_at ?? undefined,
        sourceConversationId: m.source_conversation_id ?? undefined,
      })),
      cursor,
    };
  });
}
