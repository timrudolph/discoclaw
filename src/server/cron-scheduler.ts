import crypto from 'node:crypto';
import { Cron } from 'croner';
import type { Db, CronJobRow, ConversationRow } from './db.js';
import { nextSeq } from './db.js';
import type { WsHub } from './ws.js';
import type { RuntimeAdapter } from '../runtime/types.js';
import type { ServerConfig } from './config.js';
import { invokeRuntime } from './runtime-bridge.js';
import pino from 'pino';

const log = pino({ level: process.env.LOG_LEVEL ?? 'info' });

// ─── ServerCronScheduler ──────────────────────────────────────────────────────

type CronHandle = { cron: Cron; running: boolean };

export class ServerCronScheduler {
  private handles = new Map<string, CronHandle>();
  private db: Db;
  private hub: WsHub;
  private runtime: RuntimeAdapter;
  private config: ServerConfig;

  constructor(db: Db, hub: WsHub, runtime: RuntimeAdapter, config: ServerConfig) {
    this.db = db;
    this.hub = hub;
    this.runtime = runtime;
    this.config = config;
  }

  /** Load all enabled jobs from DB and register them. */
  start(): void {
    const rows = this.db
      .prepare('SELECT * FROM server_cron_jobs WHERE enabled = 1')
      .all() as CronJobRow[];
    for (const row of rows) {
      this.register(row);
    }
    log.info({ count: rows.length }, 'server-cron:started');
  }

  stop(): void {
    for (const [, handle] of this.handles) {
      handle.cron.stop();
    }
    this.handles.clear();
    log.info('server-cron:stopped');
  }

  register(row: CronJobRow): void {
    this.unregister(row.id);
    if (!row.enabled) return;

    let handle!: CronHandle;
    const cron = new Cron(row.schedule, { timezone: row.timezone }, () => {
      if (handle.running) {
        log.warn({ jobId: row.id }, 'server-cron:skip (already running)');
        return;
      }
      handle.running = true;
      void this.fire(row).finally(() => { handle.running = false; });
    });
    handle = { cron, running: false };
    this.handles.set(row.id, handle);
    log.info({ jobId: row.id, name: row.name, schedule: row.schedule }, 'server-cron:registered');
  }

  unregister(id: string): void {
    const handle = this.handles.get(id);
    if (handle) {
      handle.cron.stop();
      this.handles.delete(id);
    }
  }

  private async fire(row: CronJobRow): Promise<void> {
    log.info({ jobId: row.id, name: row.name }, 'server-cron:fire');

    // Load the conversation
    const conv = this.db
      .prepare('SELECT * FROM conversations WHERE id = ?')
      .get(row.conversation_id) as ConversationRow | undefined;

    if (!conv) {
      log.error({ jobId: row.id, conversationId: row.conversation_id }, 'server-cron:conversation not found');
      return;
    }

    // Insert a user message (from the cron job)
    const userMsgId = crypto.randomUUID();
    const userSeq = nextSeq();
    const now = Date.now();
    const content = `[Scheduled: ${row.name}]\n\n${row.prompt}`;

    this.db.prepare(`
      INSERT INTO messages (id, conversation_id, role, content, status, seq, created_at, completed_at)
      VALUES (?, ?, 'user', ?, 'complete', ?, ?, ?)
    `).run(userMsgId, conv.id, content, userSeq, now, now);

    this.db.prepare('UPDATE conversations SET updated_at = ? WHERE id = ?').run(now, conv.id);
    this.db.prepare('UPDATE server_cron_jobs SET last_run_at = ? WHERE id = ?').run(now, row.id);

    try {
      await invokeRuntime({
        db: this.db,
        hub: this.hub,
        runtime: this.runtime,
        config: this.config,
        conversation: conv,
        userMessageContent: content,
      });
    } catch (err) {
      log.error({ err, jobId: row.id }, 'server-cron:invoke failed');
    }
  }
}
