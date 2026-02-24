import Database from 'better-sqlite3';
import fs from 'node:fs';
import path from 'node:path';

export type Db = Database.Database;

// Monotonic seq generator. Falls back to incrementing if two calls happen
// within the same millisecond (shouldn't happen in practice for a personal tool).
let _lastSeq = 0;
export function nextSeq(): number {
  const now = Date.now();
  _lastSeq = now > _lastSeq ? now : _lastSeq + 1;
  return _lastSeq;
}

export function openDb(dbPath: string, workspacesBaseDir: string): Db {
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  const db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  migrate(db, workspacesBaseDir);
  return db;
}

// ─── Row types (snake_case matches SQLite column names) ───────────────────────

export type UserRow = {
  id: string;
  name: string | null;
  created_at: number;
};

export type DeviceRow = {
  id: string;
  user_id: string;
  name: string | null;
  platform: string | null;
  token_hash: string;
  last_seen: number | null;
  created_at: number;
};

export type ConversationRow = {
  id: string;
  user_id: string;
  title: string | null;
  claude_session_id: string | null;
  created_at: number;
  updated_at: number;
  archived_at: number | null;
  is_protected: 0 | 1;
  kind: string | null;
  context_modules: string | null;   // JSON array of module filenames, e.g. ["beads.md", "pa.md"]
  model_override: string | null;    // Claude model alias override, e.g. "sonnet", "haiku"
  soul: string | null;              // Per-conversation SOUL.md — who the assistant is
  identity: string | null;          // Per-conversation IDENTITY.md — name and vibe
  user_bio: string | null;          // Per-conversation USER.md — who is being helped
  assistant_name: string | null;    // Display name for the assistant in this conversation
  accent_color: string | null;      // Hex accent color, e.g. "#A08060"
  workspace_path: string | null;    // Per-conversation workspace directory
};

export type MessageRow = {
  id: string;
  client_id: string | null;
  conversation_id: string;
  role: 'user' | 'assistant';
  content: string;
  status: 'pending' | 'streaming' | 'complete' | 'error';
  error: string | null;
  seq: number;
  created_at: number;
  completed_at: number | null;
};

export type CronJobRow = {
  id: string;
  user_id: string;
  name: string;
  schedule: string;
  timezone: string;
  prompt: string;
  conversation_id: string;
  enabled: 0 | 1;
  last_run_at: number | null;
  created_at: number;
};

export type MemoryItemRow = {
  id: string;
  user_id: string;
  conversation_id: string | null;   // null = global; set = scoped to that conversation
  content: string;
  created_at: number;
  deprecated_at: number | null;
};

export type BeadRow = {
  id: string;
  user_id: string;
  title: string;
  status: string;          // open | in_progress | blocked | closed
  description: string | null;
  priority: number | null;
  owner: string | null;
  labels: string | null;   // JSON array, e.g. '["bug","urgent"]'
  created_at: string;      // ISO-8601
  updated_at: string;
  closed_at: string | null;
  close_reason: string | null;
};

// ─── Migrations ───────────────────────────────────────────────────────────────

function migrate(db: Db, workspacesBaseDir: string): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY
    )
  `);

  const applied = new Set(
    (db.prepare('SELECT version FROM schema_migrations').pluck().all() as number[]),
  );

  const migrations: [number, () => void][] = [
    [0, () => v0(db)],
    [1, () => v1(db)],
    [2, () => v2(db, workspacesBaseDir)],
  ];

  for (const [version, run] of migrations) {
    if (applied.has(version)) continue;
    db.transaction(() => {
      run();
      db.prepare('INSERT INTO schema_migrations (version) VALUES (?)').run(version);
    })();
  }
}

function v0(db: Db): void {
  db.exec(`
    CREATE TABLE users (
      id         TEXT PRIMARY KEY,
      name       TEXT,
      created_at INTEGER NOT NULL
    );

    CREATE TABLE devices (
      id          TEXT PRIMARY KEY,
      user_id     TEXT NOT NULL REFERENCES users(id),
      name        TEXT,
      platform    TEXT,
      token_hash  TEXT NOT NULL,
      last_seen   INTEGER,
      created_at  INTEGER NOT NULL
    );

    CREATE TABLE conversations (
      id                TEXT PRIMARY KEY,
      user_id           TEXT NOT NULL REFERENCES users(id),
      title             TEXT,
      claude_session_id TEXT,
      created_at        INTEGER NOT NULL,
      updated_at        INTEGER NOT NULL,
      archived_at       INTEGER,
      is_protected      INTEGER NOT NULL DEFAULT 0,
      kind              TEXT,
      context_modules   TEXT,
      model_override    TEXT,
      soul              TEXT,
      identity          TEXT,
      user_bio          TEXT,
      assistant_name    TEXT,
      accent_color      TEXT
    );

    CREATE TABLE messages (
      id              TEXT PRIMARY KEY,
      client_id       TEXT,
      conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      role            TEXT NOT NULL,
      content         TEXT NOT NULL DEFAULT '',
      status          TEXT NOT NULL,
      error           TEXT,
      seq             INTEGER NOT NULL,
      created_at      INTEGER NOT NULL,
      completed_at    INTEGER
    );

    CREATE INDEX idx_messages_conv ON messages(conversation_id, seq);
    CREATE INDEX idx_messages_seq  ON messages(seq);

    CREATE TABLE sync_cursors (
      device_id  TEXT PRIMARY KEY,
      last_seq   INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    );

    CREATE TABLE memory_items (
      id            TEXT PRIMARY KEY,
      user_id       TEXT NOT NULL REFERENCES users(id),
      content       TEXT NOT NULL,
      created_at    INTEGER NOT NULL,
      deprecated_at INTEGER
    );

    CREATE INDEX idx_memory_user ON memory_items(user_id, deprecated_at);

    CREATE TABLE server_cron_jobs (
      id              TEXT PRIMARY KEY,
      user_id         TEXT NOT NULL REFERENCES users(id),
      name            TEXT NOT NULL,
      schedule        TEXT NOT NULL,
      timezone        TEXT NOT NULL DEFAULT 'UTC',
      prompt          TEXT NOT NULL,
      conversation_id TEXT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
      enabled         INTEGER NOT NULL DEFAULT 1,
      last_run_at     INTEGER,
      created_at      INTEGER NOT NULL
    );

    CREATE INDEX idx_cron_user ON server_cron_jobs(user_id);

    CREATE TABLE beads (
      id           TEXT PRIMARY KEY,
      user_id      TEXT NOT NULL REFERENCES users(id),
      title        TEXT NOT NULL,
      status       TEXT NOT NULL DEFAULT 'open',
      description  TEXT,
      priority     INTEGER,
      owner        TEXT,
      labels       TEXT,
      created_at   TEXT NOT NULL,
      updated_at   TEXT NOT NULL,
      closed_at    TEXT,
      close_reason TEXT
    );

    CREATE INDEX idx_beads_user_status ON beads(user_id, status);
  `);
}

function v1(db: Db): void {
  db.exec(`
    ALTER TABLE memory_items ADD COLUMN conversation_id TEXT REFERENCES conversations(id) ON DELETE CASCADE;
    CREATE INDEX idx_memory_conv ON memory_items(conversation_id, deprecated_at);
  `);
}

function v2(db: Db, workspacesBaseDir: string): void {
  db.exec(`ALTER TABLE conversations ADD COLUMN workspace_path TEXT`);
  // For existing conversations: create workspace dirs and write identity files from old DB columns.
  const rows = db.prepare('SELECT id, soul, identity, user_bio FROM conversations').all();
  for (const row of rows as Array<{ id: string; soul: string | null; identity: string | null; user_bio: string | null }>) {
    const workspacePath = path.join(workspacesBaseDir, row.id);
    fs.mkdirSync(workspacePath, { recursive: true });
    if (row.soul)     fs.writeFileSync(path.join(workspacePath, 'SOUL.md'),     row.soul,     'utf8');
    if (row.identity) fs.writeFileSync(path.join(workspacePath, 'IDENTITY.md'), row.identity, 'utf8');
    if (row.user_bio) fs.writeFileSync(path.join(workspacePath, 'USER.md'),     row.user_bio, 'utf8');
    db.prepare('UPDATE conversations SET workspace_path = ? WHERE id = ?').run(workspacePath, row.id);
  }
}
