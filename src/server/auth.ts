import crypto from 'node:crypto';
import type { FastifyRequest, FastifyReply } from 'fastify';
import type { Db, DeviceRow, UserRow } from './db.js';

export function generateToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

export function hashToken(token: string): string {
  return crypto.createHash('sha256').update(token).digest('hex');
}

// ─── Request augmentation ─────────────────────────────────────────────────────

declare module 'fastify' {
  interface FastifyRequest {
    device: DeviceRow;
    user: UserRow;
  }
}

// ─── Auth middleware (preHandler hook) ────────────────────────────────────────

export function makeAuthHook(db: Db) {
  return async function authHook(req: FastifyRequest, reply: FastifyReply): Promise<void> {
    const header = req.headers.authorization;
    // Support both header and query-string for WebSocket clients
    const tokenParam = (req.query as Record<string, string>)?.token;
    const raw = header?.startsWith('Bearer ') ? header.slice(7) : tokenParam;

    if (!raw) {
      reply.status(401).send({ error: 'Missing authorization token' });
      return;
    }

    const hash = hashToken(raw);
    const device = db
      .prepare('SELECT * FROM devices WHERE token_hash = ?')
      .get(hash) as DeviceRow | undefined;

    if (!device) {
      reply.status(401).send({ error: 'Invalid token' });
      return;
    }

    const user = db
      .prepare('SELECT * FROM users WHERE id = ?')
      .get(device.user_id) as UserRow | undefined;

    if (!user) {
      reply.status(401).send({ error: 'User not found' });
      return;
    }

    // Stamp last_seen
    db.prepare('UPDATE devices SET last_seen = ? WHERE id = ?').run(Date.now(), device.id);

    req.device = device;
    req.user = user;
  };
}
