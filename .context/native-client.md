# native-client.md — Native iOS/Mac Client + Server

## Status

| Component | Status |
|-----------|--------|
| API design | **Done** (see below) |
| Server scaffolding (`src/server/`) | **Done** |
| SQLite schema + migrations | **Done** (`src/server/db.ts`) |
| Auth (device registration, bearer tokens) | **Done** (`src/server/auth.ts`) |
| REST routes (conversations, messages, sync, health) | **Done** |
| WebSocket streaming bridge | **Done** (`src/server/ws.ts`) |
| Runtime bridge (wraps existing `src/runtime/`) | **Done** (`src/server/runtime-bridge.ts`) |
| SwiftUI client — data layer (local SQLite) | **Done** (`client/`) |
| SwiftUI client — sync layer + networking | **Done** (`client/Sources/ClawClient/Sync/`, `Network/`) |
| SwiftUI client — chat UI | **Done** (`client/App/`) |
| SwiftUI client — WebSocket streaming | **Done** (via `SyncEngine` + `WebSocketClient`) |

---

## Overview

Replace Discord as the transport layer with a native iOS/Mac client and a custom
TypeScript server. The server is the **source of record**; the client keeps a local
SQLite cache for instant display and offline reading.

```
iOS/Mac Client (SwiftUI)
  ├── Local SQLite (messages, conversations — cache only)
  ├── Sync layer  (delta pull on launch, WebSocket for real-time)
  └── HTTP/WebSocket ──────────────────────────────────┐
                                                        ▼
                                              Server (Node.js / TypeScript)
                                                ├── Auth (bearer tokens per device)
                                                ├── SQLite — source of record
                                                ├── REST API
                                                ├── WebSocket (streaming responses)
                                                └── Claude Code runtime (reuses src/runtime/)
```

The Discord subsystem continues to run unchanged. The server is a second entry
point alongside `src/index.ts`.

---

## SQLite Schema (server)

```sql
CREATE TABLE users (
  id         TEXT PRIMARY KEY,   -- UUID
  name       TEXT,
  created_at INTEGER NOT NULL
);

CREATE TABLE devices (
  id          TEXT PRIMARY KEY,  -- UUID
  user_id     TEXT NOT NULL REFERENCES users(id),
  name        TEXT,              -- "Tim's iPhone 16"
  platform    TEXT,              -- "ios" | "macos"
  token_hash  TEXT NOT NULL,     -- SHA-256 of bearer token
  last_seen   INTEGER,
  created_at  INTEGER NOT NULL
);

CREATE TABLE conversations (
  id                TEXT PRIMARY KEY,
  user_id           TEXT NOT NULL REFERENCES users(id),
  title             TEXT,
  claude_session_id TEXT,        -- persisted Claude Code session ID
  created_at        INTEGER NOT NULL,
  updated_at        INTEGER NOT NULL,
  archived_at       INTEGER       -- NULL = active
);

CREATE TABLE messages (
  id              TEXT PRIMARY KEY,  -- UUID (server-assigned)
  client_id       TEXT,              -- temp ID from client (optimistic UI)
  conversation_id TEXT NOT NULL REFERENCES conversations(id),
  role            TEXT NOT NULL,     -- "user" | "assistant"
  content         TEXT NOT NULL DEFAULT '',
  status          TEXT NOT NULL,     -- "pending" | "streaming" | "complete" | "error"
  error           TEXT,
  seq             INTEGER NOT NULL,  -- monotonic per user (sync cursor)
  created_at      INTEGER NOT NULL,
  completed_at    INTEGER
);

CREATE INDEX idx_messages_conv ON messages(conversation_id, seq);
CREATE INDEX idx_messages_seq  ON messages(seq);
```

---

## Auth

- Bearer token per device — 32-byte random hex, stored as `SHA-256(token)` on server.
- All requests: `Authorization: Bearer <token>`
- No refresh tokens (personal tool; revoke by deleting the device row).

### Endpoints

```
POST /auth/register          body: { name, platform }   → { userId, deviceId, token }
POST /auth/devices           body: { name, platform }   → { deviceId, token }
GET  /auth/me                                            → { user, device }
DELETE /auth/devices/:id
```

---

## REST API

### Conversations

```
GET    /conversations              query: archived=false
       → [{ id, title, updatedAt, lastMessage }]

POST   /conversations              body: { title? }
       → { id, title, createdAt }

GET    /conversations/:id
       → { id, title, claudeSessionId, createdAt, updatedAt }

PATCH  /conversations/:id          body: { title?, archived? }
       → { id, title, updatedAt }

DELETE /conversations/:id          hard delete (cascades messages)
```

### Messages

```
GET  /conversations/:id/messages   query: limit=50, before=<seq>
     → { messages: [...], hasMore: bool }

POST /conversations/:id/messages   body: { content, clientId? }
     → { id, seq, clientId, status: "pending" }
     ← triggers Claude invocation; response streams over WebSocket
```

### Sync

```
GET  /sync?since=<seq>
     → { conversations: [...], messages: [...], cursor: <highest seq> }
```

Client stores `cursor` locally. On app launch: `/sync?since=<cursor>` before opening WebSocket.

### Health

```
GET /health  → { ok: true, uptime: 12345 }
```

---

## WebSocket

```
ws://<host>/ws
Authorization: Bearer <token>
(fallback: ?token=<token> for iOS URLSessionWebSocketTask)
```

On connect, server immediately pushes any messages in `streaming` status so the
client is current before any new activity arrives.

Message sending stays on REST (POST). WebSocket is **receive-only** from the client.

### Server → Client events

```jsonc
{ "type": "message.delta",    "messageId": "…", "conversationId": "…", "delta": "text chunk", "seq": 7 }
{ "type": "message.complete", "messageId": "…", "conversationId": "…", "content": "full text", "seq": 7 }
{ "type": "message.error",    "messageId": "…", "conversationId": "…", "error": "timeout" }
{ "type": "tool.start",       "messageId": "…", "tool": "Bash", "label": "Running command…" }
{ "type": "tool.end",         "messageId": "…", "tool": "Bash" }
{ "type": "conversation.updated", "conversationId": "…" }
```

---

## Client Sync Flow

```
App launch
  1. Load local SQLite → display immediately (zero latency)
  2. GET /sync?since=<cursor> → merge missed messages, save cursor
  3. Connect WebSocket → real-time events going forward

Send a message
  1. Write local row: status="pending", generate clientId
  2. POST /conversations/:id/messages { content, clientId }
  3. Server responds { id, seq } → update local row with server id + seq
  4. WebSocket message.delta events → append to local assistant row
  5. message.complete → mark local row complete, update cursor

Reconnect after network loss
  1. GET /sync?since=<cursor>
  2. Reconnect WebSocket
```

---

## Server File Layout

New files alongside existing DiscoClaw source — Discord subsystem untouched.

```
src/server/
  index.ts          — Fastify app setup, plugin registration, startup
  auth.ts           — register endpoint, token validation middleware
  db.ts             — better-sqlite3 init, schema migrations
  conversations.ts  — conversation CRUD routes
  messages.ts       — message send route, Claude invocation trigger
  sync.ts           — /sync delta endpoint
  ws.ts             — WebSocket handler, per-user connection registry
  runtime-bridge.ts — wraps src/runtime/claude-code-cli.ts;
                      pipes EngineEvents → WS pushes + DB writes
```

`runtime-bridge.ts` is the critical new piece. It reuses the existing
`RuntimeAdapter` interface unchanged, translating the `EngineEvent` stream into
simultaneous WebSocket pushes and SQLite writes.

---

## Decisions deferred

- Push notifications (WebSocket covers real-time; add APNs later if needed)
- Pagination on `/sync` (chat history small for personal use)
- Rate limiting (single-user personal tool)
- Message editing/deletion
- Multi-user support (schema supports it; auth flow is single-user for now)

---

## Feature Roadmap — Discord Bot → Native Client Gap

Features the Discord bot has that the native client doesn't yet. Ordered roughly by complexity within each tier.

### Simple (UI / polish)

- [x] Copy message content to clipboard (long-press or button)
- [x] Scroll-to-bottom button when scrolled up in a conversation
- [x] Conversation search / filter in the sidebar
- [x] View archived conversations (toggle in sidebar)
- [x] Load older messages (pagination / "load more" above the oldest visible message)
- [x] Markdown rendering in message bubbles (bold, italics, inline code, lists, blockquotes)
- [x] Code block syntax highlighting
- [x] Inline image display (when Claude produces an image or a URL is an image)
- [x] Message timestamps (tap to reveal exact time)

### Medium (backend + client work)

- [x] Memory system — durable facts + rolling summary injected into prompts
  - `!memory remember <text>`, `!memory forget <text>`, `!memory show`
  - Mirrors `.context/memory.md` architecture; store in server SQLite, inject via `buildPrompt()`
  - Memory view in sidebar menu; REST endpoints for manage/add/delete
- [ ] Workspace file viewer/editor (SOUL.md, IDENTITY.md, USER.md, AGENTS.md, MEMORY.md)
  - Read/edit the `workspace/` files that shape the PA's personality
- [x] Session continuity — persist `claude_session_id` per conversation so Claude Code resumes its session rather than starting fresh each turn
- [ ] Push notifications (APNs) for completed assistant responses when app is backgrounded
- [x] File attachment — paperclip button opens file picker; content appended as code block in compose bar
- [x] Conversation export — share as plain text or markdown
- [x] Device management UI — list registered devices, revoke from settings
- [x] Appearance settings — light/dark/auto, font size

### Complex (significant feature parity)

- [ ] Beads integration — view, create, update, close `bd` tasks from native app
  - Replaces the Discord thread-backed beads UI with a native list view
  - Hook into the existing `bd` CLI the same way the Discord bot does
- [ ] Cron / scheduled prompts — heartbeat check-ins, daily summaries
  - Port the `DISCOCLAW_CRON_ENABLED` system to fire server-side on a schedule
  - Results delivered to the native client via WebSocket (or APNs if backgrounded)
- [ ] Appfigures analytics — expose App Store / Play Store data via chat in native app
  - Currently only available through the Discord bot (`.context/appfigures.md`)
- [ ] Context module awareness — let the user toggle which `.context/*.md` files are active for a conversation, similar to how the Discord bot loads modules per task
- [ ] Multi-runtime support — the Discord bot uses `RuntimeAdapter`; native server is currently Claude-only; add ability to switch model/runtime per conversation
