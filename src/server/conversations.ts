import crypto from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { Db, ConversationRow } from './db.js';
import { nextSeq } from './db.js';

export function registerConversationRoutes(app: FastifyInstance, db: Db): void {
  // GET /conversations
  app.get('/conversations', async (req) => {
    const { archived } = req.query as { archived?: string };
    const includeArchived = archived === 'true' || archived === '1';

    const rows = db
      .prepare(`
        SELECT c.*,
               m.role        AS last_role,
               m.content     AS last_content,
               m.created_at  AS last_created_at
        FROM conversations c
        LEFT JOIN messages m ON m.id = (
          SELECT id FROM messages
          WHERE conversation_id = c.id
          ORDER BY seq DESC LIMIT 1
        )
        WHERE c.user_id = ?
          ${includeArchived ? '' : 'AND c.archived_at IS NULL'}
        ORDER BY c.updated_at DESC
      `)
      .all(req.user.id) as Array<ConversationRow & {
      last_role: string | null;
      last_content: string | null;
      last_created_at: number | null;
    }>;

    return rows.map((r) => ({
      id: r.id,
      title: r.title,
      isProtected: r.is_protected === 1,
      kind: r.kind ?? undefined,
      modelOverride: r.model_override ?? undefined,
      assistantName: r.assistant_name ?? undefined,
      accentColor: r.accent_color ?? undefined,
      updatedAt: r.updated_at,
      createdAt: r.created_at,
      archivedAt: r.archived_at ?? undefined,
      lastMessage: r.last_role
        ? { role: r.last_role, content: r.last_content ?? '', createdAt: r.last_created_at }
        : undefined,
    }));
  });

  // POST /conversations
  app.post('/conversations', async (req, reply) => {
    const { title } = req.body as { title?: string };
    const id = crypto.randomUUID();
    const now = Date.now();

    db.prepare(`
      INSERT INTO conversations (id, user_id, title, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?)
    `).run(id, req.user.id, title ?? null, now, now);

    const row = db
      .prepare('SELECT * FROM conversations WHERE id = ?')
      .get(id) as ConversationRow;

    reply.status(201).send({
      id: row.id,
      title: row.title,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    });
  });

  // GET /conversations/:id
  app.get<{ Params: { id: string } }>('/conversations/:id', async (req, reply) => {
    const row = db
      .prepare('SELECT * FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as ConversationRow | undefined;

    if (!row) return reply.notFound();

    return {
      id: row.id,
      title: row.title,
      isProtected: row.is_protected === 1,
      kind: row.kind ?? undefined,
      modelOverride: row.model_override ?? undefined,
      assistantName: row.assistant_name ?? undefined,
      accentColor: row.accent_color ?? undefined,
      claudeSessionId: row.claude_session_id,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      archivedAt: row.archived_at ?? undefined,
    };
  });

  // PATCH /conversations/:id
  app.patch<{ Params: { id: string } }>('/conversations/:id', async (req, reply) => {
    const row = db
      .prepare('SELECT * FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as ConversationRow | undefined;

    if (!row) return reply.notFound();

    if (row.is_protected && req.body && (req.body as { archived?: boolean }).archived) {
      return reply.status(403).send({ error: 'Cannot archive a protected conversation.' });
    }

    const { title, archived, modelOverride, assistantName, accentColor } = req.body as {
      title?: string;
      archived?: boolean;
      modelOverride?: string | null;
      assistantName?: string | null;
      accentColor?: string | null;
    };
    const now = Date.now();

    if (title !== undefined) {
      db.prepare('UPDATE conversations SET title = ?, updated_at = ? WHERE id = ?')
        .run(title, now, row.id);
    }
    if (archived !== undefined) {
      db.prepare('UPDATE conversations SET archived_at = ?, updated_at = ? WHERE id = ?')
        .run(archived ? now : null, now, row.id);
    }
    if (modelOverride !== undefined) {
      // null clears the override (revert to server default); a string sets it
      db.prepare('UPDATE conversations SET model_override = ?, updated_at = ? WHERE id = ?')
        .run(modelOverride ?? null, now, row.id);
    }
    if (assistantName !== undefined) {
      db.prepare('UPDATE conversations SET assistant_name = ?, updated_at = ? WHERE id = ?')
        .run(assistantName ?? null, now, row.id);
    }
    if (accentColor !== undefined) {
      db.prepare('UPDATE conversations SET accent_color = ?, updated_at = ? WHERE id = ?')
        .run(accentColor ?? null, now, row.id);
    }

    const updated = db
      .prepare('SELECT * FROM conversations WHERE id = ?')
      .get(row.id) as ConversationRow;

    return {
      id: updated.id,
      title: updated.title,
      isProtected: updated.is_protected === 1,
      kind: updated.kind ?? undefined,
      modelOverride: updated.model_override ?? undefined,
      assistantName: updated.assistant_name ?? undefined,
      accentColor: updated.accent_color ?? undefined,
      createdAt: updated.created_at,
      updatedAt: updated.updated_at,
      archivedAt: updated.archived_at ?? undefined,
    };
  });

  // GET /conversations/:id/persona
  app.get<{ Params: { id: string } }>('/conversations/:id/persona', async (req, reply) => {
    const row = db
      .prepare('SELECT soul, identity, user_bio FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as Pick<ConversationRow, 'soul' | 'identity' | 'user_bio'> | undefined;

    if (!row) return reply.notFound();

    return {
      soul:     row.soul     ?? null,
      identity: row.identity ?? null,
      userBio:  row.user_bio ?? null,
    };
  });

  // PUT /conversations/:id/persona
  app.put<{ Params: { id: string } }>('/conversations/:id/persona', async (req, reply) => {
    const row = db
      .prepare('SELECT id FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as { id: string } | undefined;

    if (!row) return reply.notFound();

    const { soul, identity, userBio } = req.body as {
      soul?: string | null;
      identity?: string | null;
      userBio?: string | null;
    };

    const now = Date.now();
    if (soul !== undefined) {
      db.prepare('UPDATE conversations SET soul = ?, updated_at = ? WHERE id = ?')
        .run(soul ?? null, now, row.id);
    }
    if (identity !== undefined) {
      db.prepare('UPDATE conversations SET identity = ?, updated_at = ? WHERE id = ?')
        .run(identity ?? null, now, row.id);
    }
    if (userBio !== undefined) {
      db.prepare('UPDATE conversations SET user_bio = ?, updated_at = ? WHERE id = ?')
        .run(userBio ?? null, now, row.id);
    }

    const updated = db
      .prepare('SELECT soul, identity, user_bio FROM conversations WHERE id = ?')
      .get(row.id) as Pick<ConversationRow, 'soul' | 'identity' | 'user_bio'>;

    reply.status(200).send({
      soul:     updated.soul     ?? null,
      identity: updated.identity ?? null,
      userBio:  updated.user_bio ?? null,
    });
  });

  // DELETE /conversations/:id
  app.delete<{ Params: { id: string } }>('/conversations/:id', async (req, reply) => {
    const row = db
      .prepare('SELECT id FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as { id: string } | undefined;

    if (!row) return reply.notFound();

    const full = db.prepare('SELECT is_protected FROM conversations WHERE id = ?').get(row.id) as { is_protected: number };
    if (full.is_protected) return reply.status(403).send({ error: 'Cannot delete a protected conversation.' });

    db.prepare('DELETE FROM conversations WHERE id = ?').run(row.id);
    reply.status(204).send();
  });
}
