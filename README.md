# Discoclaw

A Discord-based personal assistant and workspace powered by AI.

Discoclaw turns a private Discord server into a customizable AI workspace. Talk to your assistant in channels and DMs, give it per-channel context, schedule recurring tasks, track work with a built-in issue tracker, and let it take actions in your server — all through natural conversation.

It's designed for a single user on a fresh, private server — your own sandbox. Not a shared bot, not a multi-user platform. Just you and your assistant in a space you control.

No gateways, no proxies, no web UI to deploy — Discord *is* the interface. Run the Discoclaw service on a Linux or macOS machine (see [Platform support](#platform-support)) and talk to your assistant from anywhere Discord works: desktop, mobile, browser.

The codebase is intentionally small — small enough to read, audit, and modify directly. Customization means changing the code, not configuring a plugin system.

## Personal assistant

Your assistant lives in Discord and knows who you are.

- **Memory** — Remembers facts you tell it across sessions (`!memory remember ...`) and injects them into every conversation
- **Rolling summaries** — Automatically compresses earlier conversation into a summary so context carries forward, even across restarts
- **Per-channel context** — Each channel gets its own markdown file describing how the assistant should behave there (formal in #work, casual in #random)
- **Customizable identity** — Define your assistant's personality, name, and values through workspace files (`SOUL.md`, `IDENTITY.md`, etc.)
- **Group chat aware** — Knows when to speak up and when to stay quiet in shared channels
- **Scheduled tasks** — Describe a recurring task in a forum thread ("every weekday at 7am, check the weather and post to #general") and it runs on schedule

## Workspace

Your assistant has a persistent working directory with real tools.

- **File access** — Read, write, and organize files in a dedicated workspace directory
- **Web access** — Search the web, fetch pages, and pull in information
- **Browser automation** — Connect to a real browser session for tasks that need it
- **Discord actions** — Your assistant can manage your server: create channels, send messages, search history, create threads, run polls, manage roles, and more — each category gated behind its own feature flag
- **Multi-turn sessions** — A live process persists between messages, so file reads, edits, and tool results carry across turns instead of starting fresh every time
- **Cron jobs** — Define scheduled tasks as forum threads in plain language; edit to change, archive to pause, unarchive to resume
- **Task tracking** — Integrated with [beads](https://github.com/qwibitai/beads), a lightweight issue tracker; create, update, and close tasks from Discord or the terminal, synced to forum threads

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

On first run, these files are scaffolded from templates so you have a guided starting point. They're gitignored — yours, not the project's.

### Shareable integration plans

Discoclaw supports a shareable markdown plan format for passing integrations between users:

- Spec: `docs/discoclaw-plan-spec.md`
- Template: `templates/plans/integration.discoclaw-plan.md`
- Example files: `plans/*.discoclaw-plan.md`
- Skills:
  - `skills/discoclaw-plan-generator/SKILL.md`
  - `skills/discoclaw-plan-consumer/SKILL.md`

Author one plan file for an integration, share it, then let another user's Discoclaw agent consume it and produce a local implementation checklist before coding.

## Prerequisites

- **Node.js >=20** — check with `node --version`
- **pnpm** — enable via Corepack (`corepack enable`) or install separately
- **Claude CLI** on your `PATH` — check with `claude --version` (see [Claude CLI docs](https://docs.anthropic.com/en/docs/claude-code) to install)
- An **Anthropic account** with an active Claude plan or API credits (the CLI needs this to run)

## Quick start

1. **Create a Discord bot** and invite it to a private server (see the [bot setup guide](docs/discord-bot-setup.md))

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

## Platform support

- **All platforms** — `pnpm dev` works everywhere Node.js runs (Linux, macOS, Windows)
- **Linux** — systemd service file provided for production deployment (see `.context/ops.md`)
- **macOS / Windows** — use pm2, screen, or another process manager for long-running deployment; or just `pnpm dev` in a terminal

> Windows is not tested for production use in v0.x. The session scanner has known path-handling issues on Windows, and the Claude CLI primarily targets Linux and macOS.

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
pnpm doctor     # preflight check (Node, pnpm, Claude CLI, .env)
pnpm dev        # start dev mode
pnpm build      # compile TypeScript
pnpm test       # run tests
```

## License

MIT
