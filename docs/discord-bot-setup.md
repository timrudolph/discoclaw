# Discoclaw Discord Bot Setup

This walks you through creating a fresh Discord bot for Discoclaw and configuring the repo to use it.

## Safety disclaimer (read first)

Discoclaw can drive powerful local automation through an agent runtime connected to Discord.

Recommended starting point:
- Create a **standalone private Discord server** for Discoclaw.
- Use **least privilege** bot permissions (avoid `Administrator` unless you explicitly need it).
- Keep allowlists tight: `DISCORD_ALLOW_USER_IDS` and `DISCORD_CHANNEL_IDS`.

## 1) Create The Bot

1. Go to the Discord Developer Portal and create a new application.
2. Open the application -> **Bot** -> **Add Bot**.
3. Turn on:
   - **Message Content Intent** (required for reading message content in guild channels)
4. Copy the bot token and paste it into your local `.env` immediately (`DISCORD_TOKEN=...`).
   - Clipboard tip: don’t copy the Application ID until after you’ve pasted the token, or you may overwrite it.
   - If you lose it: go back to the Bot page and **Reset Token**.

## 2) Invite The Bot To Your Server

Use the Developer Portal:

1. OAuth2 -> URL Generator
2. Scopes:
   - `bot`
3. Bot permissions (minimal recommended):
   - View Channels
   - Send Messages
   - Read Message History
   - Send Messages in Threads
4. Open the generated URL, pick your server, and authorize.

### Permission profiles (choose intentionally)

Discoclaw has 4 common “permission profiles”. You can always re-invite the bot later with a different permission set.

- **Minimal** (recommended default)
  - What works: read/send messages in channels it can see; reply inside threads it can see.
  - What won’t work: creating/archiving/deleting threads; moderating; changing channels/roles.
  - Pros: lowest blast radius, easier to recommend publicly.
  - Cons: more “it can’t do X” situations if you want it to administer Discord.
- **Threads**
  - Adds: thread creation + thread management.
  - Pros: “works in threads” even when you want the bot to create/manage them.
  - Cons: higher risk than minimal; still not “server admin”.
- **Moderator**
  - Adds: channel management, message management, thread management, webhooks, uploads, etc. (still not `Administrator`).
  - Pros: broad ops capabilities while avoiding full admin.
  - Cons: meaningful blast radius if the bot is misconfigured/compromised; still may hit edge cases that require admin.
- **Administrator**
  - Pros: lowest operational friction; “everything will always work” (as far as Discord permissions go).
  - Cons: highest blast radius. Only use on a private server you control. If the bot token or runtime is compromised, an attacker can do essentially anything in that server.

Notes:
- “Work inside threads” means: being able to read/respond **in** threads. Minimal covers this for threads the bot can see. Private threads may require additional permission or being explicitly added.
- If you want slash commands: add the `applications.commands` scope.
- Discord does not expose the same full-text “search like the client” via the public bot API; if you want search, you generally need to log/index messages yourself.
- If you want the bot to reply inside threads reliably, set `DISCORD_AUTO_JOIN_THREADS=1` so it joins threads it encounters (public threads; private threads still require adding the bot).
- To join all *active public* threads in a server (one-time):
  - Dry run: `pnpm discord:join-threads -- --guild-id <YOUR_SERVER_ID>`
  - Apply: `pnpm discord:join-threads -- --guild-id <YOUR_SERVER_ID> --apply 1`

## 3) Get User/Channel IDs

1. Discord client -> Settings -> Advanced -> enable **Developer Mode**
2. Right-click:
   - your user -> Copy ID (use this in `DISCORD_ALLOW_USER_IDS`)
   - a channel -> Copy ID (use this in `DISCORD_CHANNEL_IDS`)

## 4) Configure Discoclaw

```bash
cp .env.example .env
pnpm i
```

Edit `.env`:
- `DISCORD_TOKEN=...`
- `DISCORD_ALLOW_USER_IDS=...` (required; if empty, the bot responds to nobody)
- `DISCORD_CHANNEL_IDS=...` (recommended for servers)
- `DISCOCLAW_DATA_DIR=...` (optional; defaults workspace/content under this folder)

Run:

```bash
pnpm dev
```

## 5) Validate

- Quick auth smoke test (exits immediately on success):
  - `pnpm discord:smoke-test` (prints `Discord bot ready`)
- To verify the bot is actually in your server, set the server ID (guild ID) and re-run:
  - `pnpm discord:smoke-test -- --guild-id <YOUR_SERVER_ID>` (prints `Discord bot ready (guild ok: ...)`)
- DM the bot: it should respond only if your user ID is allowlisted.
- Post in an allowlisted channel: it should respond.
- Post in a non-allowlisted channel: it should not respond.
- Create a new channel and post once: Discoclaw should auto-create a stub context file under `content/discord/channels/` and add it to `content/discord/DISCORD.md`.
