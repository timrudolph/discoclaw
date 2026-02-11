# Discoclaw

A Discord-based personal assistant and workspace powered by AI.

Discoclaw turns a private Discord server into a customizable AI workspace. Talk to your assistant in channels and DMs, give it per-channel context, schedule recurring tasks, track work with a built-in issue tracker, and let it take actions in your server — all through natural conversation.

The codebase is intentionally small — small enough to read, audit, and modify directly. Customization means changing the code, not configuring a plugin system.

## What it does

**Personal assistant** — Conversation with memory. Discoclaw remembers facts across sessions (`!memory remember ...`), maintains rolling conversation summaries, and loads per-channel context so it knows how to behave in different spaces.

**Workspace** — Your assistant runs in a dedicated working directory with access to files, tools, and the web. Point it at a Dropbox folder or local directory and it becomes a persistent workspace you interact with through Discord.

**Scheduled tasks** — Create a thread in a forum channel describing what you want and when. Discoclaw parses it into a cron job and runs it on schedule. Edit the thread to change it, archive to pause, unarchive to resume.

**Discord actions** — Your assistant can create channels, manage threads, search messages, post to other channels, and more — all gated behind granular feature flags you control.

**Task tracking** — Integrated with the `bd` issue tracker. Create, update, and close tasks from Discord or the terminal — both sync to the same forum threads.

## How it works

Discoclaw is a bridge between Discord and an AI runtime (Claude Code by default). When you send a message, it:

1. Checks the user allowlist (fail-closed — empty list means respond to nobody)
2. Loads per-channel context, conversation history, rolling summary, and durable memory
3. Passes everything to the runtime (Claude CLI) running in your workspace directory
4. Streams the response back, chunked to fit Discord's message limits
5. Parses and executes any Discord actions the assistant emitted

## Customization

Discoclaw is designed to be yours. Identity, personality, and behavior are defined in plain markdown files in your workspace:

| File | Purpose |
|------|---------|
| `SOUL.md` | Core personality and values |
| `IDENTITY.md` | Name and vibe |
| `USER.md` | Who you're helping |
| `AGENTS.md` | Personal rules and conventions |
| `TOOLS.md` | Available tools and integrations |

Per-channel context lives in `content/discord/channels/` — one markdown file per channel telling the assistant how to behave there.

These files are gitignored. They're yours, not the project's.

## Quick start

1. **Create a Discord bot** and invite it to a private server (see the [bot setup guide](.context/bot-setup.md))

2. **Install and configure:**
   ```bash
   pnpm install
   cp .env.example .env
   # Edit .env with your bot token, allowed user IDs, etc.
   ```

3. **Run:**
   ```bash
   pnpm dev
   ```

## Safety

Discoclaw can execute powerful local tooling via an agent runtime, often with elevated permissions. Treat it like a local automation system connected to Discord.

- Use a **private Discord server** — don't start in a shared or public server
- Use **least-privilege** Discord permissions
- Keep `DISCORD_ALLOW_USER_IDS` tight — this is the primary security boundary
- Empty allowlist = respond to nobody (fail-closed)
- Optionally restrict channels with `DISCORD_CHANNEL_IDS`
- External content (Discord messages, web pages, files) is **data**, not instructions

## Workspace layout

Discoclaw runs the AI runtime in a separate working directory (`WORKSPACE_CWD`), keeping the repo clean while giving your assistant a persistent workspace.

- Set `DISCOCLAW_DATA_DIR` to use `$DISCOCLAW_DATA_DIR/workspace` (good for Dropbox-backed setups)
- Or leave it unset to use `./workspace` relative to the repo
- Content (channel context, Discord config) defaults to `$DISCOCLAW_DATA_DIR/content`

## Development

```bash
pnpm dev        # start dev mode
pnpm build      # compile TypeScript
pnpm test       # run tests
```

## License

MIT
