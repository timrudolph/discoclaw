# discord.md — Discord Behavior & Routing

## Access Control
- `DISCORD_ALLOW_USER_IDS` is the primary gate.
- Fail closed: if the allowlist is empty, Discoclaw responds to nobody.
- Optional: `DISCORD_CHANNEL_IDS` restricts the bot to specific guild channels (DMs are still allowed).

## Channel Context (Token-Efficient)
Discoclaw can link a per-channel context file into the runtime prompt (instead of inlining it) to keep initial context small.

Layout (under `$DISCOCLAW_CONTENT_DIR` or `$DISCOCLAW_DATA_DIR/content`):
- `discord/DISCORD.md` (index: channel -> id -> context file)
- `discord/channels/*.md` (per-channel context modules)
- `discord/channels/_default.md` (fallback for unknown channels)
- `discord/channels/dm.md` (DM fallback)

Behavior:
- For each message, Discoclaw tells the runtime to `Read` the relevant channel context file before responding.
- For threads, the parent channel context applies.

## Session Keys
- DM: `discord:dm:<authorId>`
- Thread: `discord:thread:<threadId>` (if the incoming channel is a thread)
- Channel: `discord:channel:<channelId>`

These session keys map to persisted UUIDs via `data/sessions.json`.

## Concurrency (Single Flight)
- Discoclaw serializes processing per session key to avoid interleaving tool runs/context.
- Implementation: `src/group-queue.ts`

## Output Constraints
- Discord has a ~2000 char limit per message.
- Discoclaw chunks long replies and attempts to keep fenced code blocks renderable across splits.

## Group CWD Mode
If `USE_GROUP_DIR_CWD=1`:
- CWD becomes `groups/<sessionKey>/` for that Discord context.
- The main workspace (`WORKSPACE_CWD`) is added via `--add-dir` so tools can still read/write it.
- Discoclaw bootstraps `groups/<sessionKey>/CLAUDE.md` on first use.
