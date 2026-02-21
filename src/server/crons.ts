import crypto from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type { Db, CronJobRow } from './db.js';
import type { ServerCronScheduler } from './cron-scheduler.js';

function formatJob(r: CronJobRow) {
  return {
    id: r.id,
    name: r.name,
    schedule: r.schedule,
    timezone: r.timezone,
    prompt: r.prompt,
    conversationId: r.conversation_id,
    enabled: r.enabled === 1,
    lastRunAt: r.last_run_at ?? undefined,
    createdAt: r.created_at,
  };
}

export function registerCronRoutes(
  app: FastifyInstance,
  db: Db,
  scheduler: ServerCronScheduler,
): void {
  // GET /crons
  app.get('/crons', async (req) => {
    const rows = db
      .prepare('SELECT * FROM server_cron_jobs WHERE user_id = ? ORDER BY created_at ASC')
      .all(req.user.id) as CronJobRow[];
    return { jobs: rows.map(formatJob) };
  });

  // POST /crons — create
  app.post('/crons', async (req, reply) => {
    const { name, schedule, timezone, prompt, conversationId } = req.body as {
      name?: string;
      schedule?: string;
      timezone?: string;
      prompt?: string;
      conversationId?: string;
    };

    if (!name?.trim()) return reply.badRequest('name is required');
    if (!schedule?.trim()) return reply.badRequest('schedule is required');
    if (!prompt?.trim()) return reply.badRequest('prompt is required');
    if (!conversationId?.trim()) return reply.badRequest('conversationId is required');

    // Validate schedule by trying to construct a Cron
    try {
      const { Cron } = await import('croner');
      const c = new Cron(schedule.trim(), { paused: true });
      c.stop();
    } catch {
      return reply.badRequest(`Invalid cron schedule: "${schedule}"`);
    }

    // Verify conversation belongs to user
    const conv = db
      .prepare('SELECT id FROM conversations WHERE id = ? AND user_id = ?')
      .get(conversationId, req.user.id);
    if (!conv) return reply.notFound();

    const id = crypto.randomUUID();
    const now = Date.now();
    const row: CronJobRow = {
      id,
      user_id: req.user.id,
      name: name.trim(),
      schedule: schedule.trim(),
      timezone: timezone?.trim() || 'UTC',
      prompt: prompt.trim(),
      conversation_id: conversationId,
      enabled: 1,
      last_run_at: null,
      created_at: now,
    };

    db.prepare(`
      INSERT INTO server_cron_jobs
        (id, user_id, name, schedule, timezone, prompt, conversation_id, enabled, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?)
    `).run(id, row.user_id, row.name, row.schedule, row.timezone, row.prompt, row.conversation_id, now);

    scheduler.register(row);
    reply.status(201).send(formatJob(row));
  });

  // PATCH /crons/:id — update fields or toggle enabled
  app.patch<{ Params: { id: string } }>('/crons/:id', async (req, reply) => {
    const existing = db
      .prepare('SELECT * FROM server_cron_jobs WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as CronJobRow | undefined;
    if (!existing) return reply.notFound();

    const { name, schedule, timezone, prompt, enabled } = req.body as {
      name?: string;
      schedule?: string;
      timezone?: string;
      prompt?: string;
      enabled?: boolean;
    };

    if (schedule !== undefined) {
      try {
        const { Cron } = await import('croner');
        const c = new Cron(schedule, { paused: true });
        c.stop();
      } catch {
        return reply.badRequest(`Invalid cron schedule: "${schedule}"`);
      }
    }

    db.prepare(`
      UPDATE server_cron_jobs SET
        name = COALESCE(?, name),
        schedule = COALESCE(?, schedule),
        timezone = COALESCE(?, timezone),
        prompt = COALESCE(?, prompt),
        enabled = COALESCE(?, enabled)
      WHERE id = ?
    `).run(
      name?.trim() ?? null,
      schedule?.trim() ?? null,
      timezone?.trim() ?? null,
      prompt?.trim() ?? null,
      enabled !== undefined ? (enabled ? 1 : 0) : null,
      existing.id,
    );

    const updated = db
      .prepare('SELECT * FROM server_cron_jobs WHERE id = ?')
      .get(existing.id) as CronJobRow;

    // Re-register (handles enable/disable/schedule change)
    if (updated.enabled) {
      scheduler.register(updated);
    } else {
      scheduler.unregister(updated.id);
    }

    return formatJob(updated);
  });

  // DELETE /crons/:id
  app.delete<{ Params: { id: string } }>('/crons/:id', async (req, reply) => {
    const existing = db
      .prepare('SELECT id FROM server_cron_jobs WHERE id = ? AND user_id = ?')
      .get(req.params.id, req.user.id) as { id: string } | undefined;
    if (!existing) return reply.notFound();
    scheduler.unregister(existing.id);
    db.prepare('DELETE FROM server_cron_jobs WHERE id = ?').run(existing.id);
    reply.status(204).send();
  });
}
