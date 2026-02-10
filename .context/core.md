# core.md — Discoclaw Core Context

## Identity
- **Name:** Discoclaw
- **Role:** Minimal Discord bridge that routes messages to AI runtimes (Claude Code first; OpenAI/Gemini adapters later).
- **Philosophy:** Keep it small, explicit, auditable. See `docs/philosophy.md`.

## Trust Boundary
- We assume Claude Code runs with `--dangerously-skip-permissions` in production.
- The **Discord allowlist** is the primary security boundary (`DISCORD_ALLOW_USER_IDS`).
- Default policy is **fail closed**: empty allowlist means respond to nobody.

## Repo Layout
- `src/index.ts` — entrypoint
- `src/discord.ts` — Discord bot + routing + per-session queue
- `src/discord/` — Discord submodules (allowlist, channel-context, session-key)
- `src/runtime/` — runtime adapters (Claude CLI now; OpenAI/Gemini later)
- `src/sessions.ts` — sessionKey -> UUID mapping (stored in `data/sessions.json`)
- `src/pidlock.ts` — PID lock (duplicate instance guard)
- `src/group-queue.ts` — per-session concurrency serialization
- `groups/` — optional per-session working directories (nanoclaw-style). Enabled by `USE_GROUP_DIR_CWD=1`.
- `systemd/discoclaw.service` — service unit template

## State Files
- `data/sessions.json` (gitignored) — sessionKey -> UUID mapping
- `data/discoclaw.pid` (gitignored) — PID lock file preventing duplicate instances (auto-cleaned on SIGTERM/SIGINT; stale locks from SIGKILL are detected and overwritten on next startup)
- `data/memory/rolling/<session-key>.json` (gitignored) — rolling conversation summaries per session
- `data/memory/durable/<discord-user-id>.json` (gitignored) — per-user durable memory items
- `groups/<sessionKey>/CLAUDE.md` — bootstrapped per-group instructions when group cwd is enabled

## External Workspace (Important)
- Discoclaw runs the runtime (Claude CLI) in a separate working directory (`WORKSPACE_CWD`).
- Defaults:
  - If `DISCOCLAW_DATA_DIR` is set, `WORKSPACE_CWD` defaults to `$DISCOCLAW_DATA_DIR/workspace`.
  - Otherwise, `WORKSPACE_CWD` defaults to `./workspace` (relative to the repo).
- You can still point `WORKSPACE_CWD` at an external workspace (for example, an older "weston" folder), but treat it as data: avoid unrelated edits while developing Discoclaw itself.
