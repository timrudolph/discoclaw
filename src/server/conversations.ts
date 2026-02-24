import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import type { FastifyInstance } from 'fastify';
import type { Db, ConversationRow } from './db.js';
import { nextSeq } from './db.js';
import type { ServerConfig } from './config.js';

const WORKSPACE_CONV_ALLOWED = new Set(['SOUL.md', 'IDENTITY.md', 'USER.md', 'MEMORY.md', 'AGENTS.md', 'TOOLS.md']);

export function registerConversationRoutes(app: FastifyInstance, db: Db, config: ServerConfig): void {
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

    // Create the conversation's workspace directory
    const workspacePath = path.join(config.workspacesBaseDir, id);
    fs.mkdirSync(workspacePath, { recursive: true });

    // Seed identity files from global workspace defaults if they exist
    for (const name of ['SOUL.md', 'IDENTITY.md', 'USER.md'] as const) {
      try {
        fs.copyFileSync(path.join(config.workspaceCwd, name), path.join(workspacePath, name));
      } catch { /* file absent in global workspace, fine */ }
    }

    db.prepare('UPDATE conversations SET workspace_path = ? WHERE id = ?').run(workspacePath, id);

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

  // DELETE /conversations/:id
  app.delete<{ Params: { id: string } }>('/conversations/:id', async (req, reply) => {
    const row = db
      .prepare('SELECT id FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as { id: string } | undefined;

    if (!row) return reply.notFound();

    const full = db.prepare('SELECT is_protected, workspace_path FROM conversations WHERE id = ?').get(row.id) as { is_protected: number; workspace_path: string | null };
    if (full.is_protected) return reply.status(403).send({ error: 'Cannot delete a protected conversation.' });

    // Remove the conversation's workspace directory
    if (full.workspace_path) {
      try { fs.rmSync(full.workspace_path, { recursive: true, force: true }); } catch { /* ignore */ }
    }

    db.prepare('DELETE FROM conversations WHERE id = ?').run(row.id);
    reply.status(204).send();
  });

  // ─── Conversation workspace file endpoints ────────────────────────────────

  // GET /conversations/:id/workspace/files — list workspace files with preview
  app.get<{ Params: { id: string } }>('/conversations/:id/workspace/files', async (req, reply) => {
    const conv = db
      .prepare('SELECT workspace_path FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as { workspace_path: string | null } | undefined;
    if (!conv) return reply.notFound();

    const workspacePath = conv.workspace_path ?? path.join(config.workspacesBaseDir, req.params.id);
    const files = await Promise.all(
      [...WORKSPACE_CONV_ALLOWED].map(async (name) => {
        const filePath = path.join(workspacePath, name);
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

  // GET /conversations/:id/workspace/files/:name — get file content
  app.get<{ Params: { id: string; name: string } }>('/conversations/:id/workspace/files/:name', async (req, reply) => {
    if (!WORKSPACE_CONV_ALLOWED.has(req.params.name)) return reply.forbidden('File not in allowed list');

    const conv = db
      .prepare('SELECT workspace_path FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as { workspace_path: string | null } | undefined;
    if (!conv) return reply.notFound();

    const workspacePath = conv.workspace_path ?? path.join(config.workspacesBaseDir, req.params.id);
    const filePath = path.join(workspacePath, req.params.name);
    try {
      const content = await fs.promises.readFile(filePath, 'utf8');
      return { name: req.params.name, content };
    } catch {
      return { name: req.params.name, content: '' };
    }
  });

  // PUT /conversations/:id/workspace/files/:name — write file content
  app.put<{ Params: { id: string; name: string } }>('/conversations/:id/workspace/files/:name', async (req, reply) => {
    if (!WORKSPACE_CONV_ALLOWED.has(req.params.name)) return reply.forbidden('File not in allowed list');

    const conv = db
      .prepare('SELECT workspace_path FROM conversations WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as { workspace_path: string | null } | undefined;
    if (!conv) return reply.notFound();

    const { content } = req.body as { content?: string };
    if (content === undefined) return reply.badRequest('content is required');

    const workspacePath = conv.workspace_path ?? path.join(config.workspacesBaseDir, req.params.id);
    await fs.promises.mkdir(workspacePath, { recursive: true });
    await fs.promises.writeFile(path.join(workspacePath, req.params.name), content, 'utf8');
    reply.status(204).send();
  });
}
