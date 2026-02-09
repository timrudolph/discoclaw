# Phase 2: Migration From Weston (Working Notes)

Goal: selectively migrate durable "content" from the legacy Weston Dropbox tree into the new Discoclaw data root.

Principles:
- Copy only what Discoclaw needs; avoid dragging in build outputs, `node_modules/`, caches, logs, audits.
- Treat legacy as read-only reference (`legacy/weston`).
- Keep secrets out of Dropbox-backed content. No `.env` files.

## Data Root

- Data root: `/home/davidmarsh/Dropbox/discoclaw-data`
- Content root: `/home/davidmarsh/Dropbox/discoclaw-data/content`

Optional local convenience:
- `content` (repo-local symlink, ignored): `content -> /home/davidmarsh/Dropbox/discoclaw-data/content`

## First Import: Discord Channel Context

Source (legacy):
- `/home/davidmarsh/Dropbox/weston/DISCORD.md` (channel index with IDs)
- `/home/davidmarsh/Dropbox/weston/discord/*.md` (per-channel context files)

Destination (new content root):
- `content/discord/DISCORD.md`
- `content/discord/channels/*.md`

## Next: What To Consider Migrating (Triage)

Good candidates (durable, low-churn):
- Markdown knowledge/context files you want the runtime to reference.
- Canonical “indexes” (like `DISCORD.md`) that map channels -> context.
- Small CSVs or reference data used by prompts.

Usually do NOT migrate (high churn / heavy / ops-specific):
- `node_modules/`, `dist/`, `.cache/`, `tmp/`, `logs/`, `audits/`
- Gateway/service scaffolding (`systemd` units, watchdog timers) from legacy Openclaw setup
- Large binary assets unless you explicitly want them as part of the new content set

## Open Questions

- Should Discoclaw *automatically* prepend per-channel context based on `DISCORD_CHANNEL_IDS` + `content/discord/channels/*.md`?
- If yes, what is the desired precedence?
  - Per-channel context vs per-session group (`groups/<sessionKey>/CLAUDE.md`) vs workspace `CLAUDE.md`

