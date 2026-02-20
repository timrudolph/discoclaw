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

export function openDb(dbPath: string): Db {
  fs.mkdirSync(path.dirname(dbPath), { recursive: true });
  const db = new Database(dbPath);
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  migrate(db);
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

export type MemoryItemRow = {
  id: string;
  user_id: string;
  content: string;
  created_at: number;
  deprecated_at: number | null;
};

// ─── Migrations ───────────────────────────────────────────────────────────────

function migrate(db: Db): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY
    )
  `);

  const applied = new Set(
    (db.prepare('SELECT version FROM schema_migrations').pluck().all() as number[]),
  );

  const migrations: [number, () => void][] = [
    [1, () => v1(db)],
    [2, () => v2(db)],
    [3, () => v3(db)],
    [4, () => v4(db)],
  ];

  for (const [version, run] of migrations) {
    if (applied.has(version)) continue;
    db.transaction(() => {
      run();
      db.prepare('INSERT INTO schema_migrations (version) VALUES (?)').run(version);
    })();
  }
}

function v2(db: Db): void {
  db.exec(`
    ALTER TABLE conversations ADD COLUMN is_protected INTEGER NOT NULL DEFAULT 0
  `);
}

function v3(db: Db): void {
  db.exec(`
    ALTER TABLE conversations ADD COLUMN kind TEXT
  `);
  // Backfill: the one protected conversation that exists is 'general'.
  db.exec(`
    UPDATE conversations SET kind = 'general' WHERE is_protected = 1
  `);
}

function v4(db: Db): void {
  db.exec(`
    CREATE TABLE memory_items (
      id           TEXT PRIMARY KEY,
      user_id      TEXT NOT NULL REFERENCES users(id),
      content      TEXT NOT NULL,
      created_at   INTEGER NOT NULL,
      deprecated_at INTEGER
    );
    CREATE INDEX idx_memory_user ON memory_items(user_id, deprecated_at);
  `);
}

function v1(db: Db): void {
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
      id               TEXT PRIMARY KEY,
      user_id          TEXT NOT NULL REFERENCES users(id),
      title            TEXT,
      claude_session_id TEXT,
      created_at       INTEGER NOT NULL,
      updated_at       INTEGER NOT NULL,
      archived_at      INTEGER
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
  `);
}
