import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { Db, BeadRow } from './db.js';
import type { WsHub } from './ws.js';

// ─── Helpers ──────────────────────────────────────────────────────────────────

function toApiBead(r: BeadRow) {
  return {
    id: r.id,
    title: r.title,
    status: r.status,
    description: r.description ?? undefined,
    priority: r.priority ?? undefined,
    owner: r.owner ?? undefined,
    labels: r.labels ? (JSON.parse(r.labels) as string[]) : [],
    createdAt: r.created_at,
    updatedAt: r.updated_at,
    closedAt: r.closed_at ?? undefined,
    closeReason: r.close_reason ?? undefined,
  };
}

function now(): string {
  return new Date().toISOString();
}

// ─── Routes ───────────────────────────────────────────────────────────────────

export function registerBeadsRoutes(app: FastifyInstance, db: Db, hub: WsHub): void {
  const broadcastBeadsUpdated = (userId: string) =>
    hub.broadcast(userId, { type: 'beads.updated' });
  // GET /beads?status=open|all|in_progress|blocked|closed&limit=100
  app.get('/beads', async (req) => {
    const userId = (req as any).userId as string;
    const { status, limit } = req.query as { status?: string; limit?: string };
    const maxRows = limit ? parseInt(limit, 10) : 100;

    let rows: BeadRow[];
    if (!status || status === 'all') {
      rows = db
        .prepare('SELECT * FROM beads WHERE user_id = ? ORDER BY created_at DESC LIMIT ?')
        .all(userId, maxRows) as BeadRow[];
    } else {
      rows = db
        .prepare('SELECT * FROM beads WHERE user_id = ? AND status = ? ORDER BY created_at DESC LIMIT ?')
        .all(userId, status, maxRows) as BeadRow[];
    }
    return { beads: rows.map(toApiBead) };
  });

  // GET /beads/:id
  app.get<{ Params: { id: string } }>('/beads/:id', async (req, reply) => {
    const userId = (req as any).userId as string;
    const row = db
      .prepare('SELECT * FROM beads WHERE id = ? AND user_id = ?')
      .get(req.params.id, userId) as BeadRow | undefined;
    if (!row) return reply.notFound();
    return toApiBead(row);
  });

  // POST /beads — create
  app.post('/beads', async (req, reply) => {
    const userId = (req as any).userId as string;
    const { title, description, priority, owner, labels } = req.body as {
      title?: string;
      description?: string;
      priority?: number;
      owner?: string;
      labels?: string[];
    };
    if (!title?.trim()) return reply.badRequest('title is required');

    const id = randomUUID();
    const ts = now();
    db.prepare(`
      INSERT INTO beads (id, user_id, title, status, description, priority, owner, labels, created_at, updated_at)
      VALUES (?, ?, ?, 'open', ?, ?, ?, ?, ?, ?)
    `).run(
      id, userId, title.trim(),
      description ?? null,
      priority ?? null,
      owner ?? null,
      labels ? JSON.stringify(labels) : null,
      ts, ts,
    );

    const row = db.prepare('SELECT * FROM beads WHERE id = ?').get(id) as BeadRow;
    broadcastBeadsUpdated(userId);
    reply.status(201).send(toApiBead(row));
  });

  // PATCH /beads/:id — update fields
  app.patch<{ Params: { id: string } }>('/beads/:id', async (req, reply) => {
    const userId = (req as any).userId as string;
    const existing = db
      .prepare('SELECT * FROM beads WHERE id = ? AND user_id = ?')
      .get(req.params.id, userId) as BeadRow | undefined;
    if (!existing) return reply.notFound();

    const { title, description, status, priority, owner } = req.body as {
      title?: string;
      description?: string;
      status?: string;
      priority?: number | null;
      owner?: string | null;
    };

    db.prepare(`
      UPDATE beads SET
        title       = COALESCE(?, title),
        description = CASE WHEN ? IS NOT NULL THEN ? ELSE description END,
        status      = COALESCE(?, status),
        priority    = CASE WHEN ? IS NOT NULL THEN ? ELSE priority END,
        owner       = CASE WHEN ? IS NOT NULL THEN ? ELSE owner END,
        updated_at  = ?
      WHERE id = ?
    `).run(
      title?.trim() ?? null,
      description !== undefined ? 1 : null, description ?? null,
      status ?? null,
      priority !== undefined ? 1 : null, priority ?? null,
      owner !== undefined ? 1 : null, owner ?? null,
      now(),
      req.params.id,
    );

    const row = db.prepare('SELECT * FROM beads WHERE id = ?').get(req.params.id) as BeadRow;
    broadcastBeadsUpdated(userId);
    return toApiBead(row);
  });

  // POST /beads/:id/close
  app.post<{ Params: { id: string } }>('/beads/:id/close', async (req, reply) => {
    const userId = (req as any).userId as string;
    const existing = db
      .prepare('SELECT * FROM beads WHERE id = ? AND user_id = ?')
      .get(req.params.id, userId) as BeadRow | undefined;
    if (!existing) return reply.notFound();

    const { reason } = req.body as { reason?: string };
    const ts = now();
    db.prepare(`
      UPDATE beads SET status = 'closed', closed_at = ?, close_reason = ?, updated_at = ?
      WHERE id = ?
    `).run(ts, reason ?? null, ts, req.params.id);

    const row = db.prepare('SELECT * FROM beads WHERE id = ?').get(req.params.id) as BeadRow;
    broadcastBeadsUpdated(userId);
    return toApiBead(row);
  });

  // POST /beads/:id/labels — add a label
  app.post<{ Params: { id: string } }>('/beads/:id/labels', async (req, reply) => {
    const userId = (req as any).userId as string;
    const existing = db
      .prepare('SELECT * FROM beads WHERE id = ? AND user_id = ?')
      .get(req.params.id, userId) as BeadRow | undefined;
    if (!existing) return reply.notFound();

    const { label } = req.body as { label?: string };
    if (!label?.trim()) return reply.badRequest('label is required');

    const labels: string[] = existing.labels ? (JSON.parse(existing.labels) as string[]) : [];
    if (!labels.includes(label.trim())) {
      labels.push(label.trim());
    }

    db.prepare('UPDATE beads SET labels = ?, updated_at = ? WHERE id = ?')
      .run(JSON.stringify(labels), now(), req.params.id);

    const row = db.prepare('SELECT * FROM beads WHERE id = ?').get(req.params.id) as BeadRow;
    broadcastBeadsUpdated(userId);
    return toApiBead(row);
  });
}
