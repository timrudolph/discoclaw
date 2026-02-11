# Context
Added MIT license, disclaimer, and attribution notices for open-source release. Also wrapping up uncommitted memory provenance work from a prior session.

# Changes Made
- `LICENSE` — Standard MIT license, copyright 2025 David Marsh
- `DISCLAIMER.md` — Usage disclaimer, ToS compliance, trademark attribution
- `README.md` — License section links to LICENSE and DISCLAIMER.md
- `package.json` — Added `"license": "MIT"` field
- `src/discord/durable-memory.ts` — Extended `source` with `guildId` and `channelName`; formatted output includes channel name
- `src/discord/memory-commands.ts` — Pass `guildId`/`channelName` through to durable storage
- `src/discord/user-turn-to-durable.ts` — Pass Discord metadata to auto-extracted items
- `src/discord/shortterm-memory.ts` — Added optional `channelId` to `ShortTermEntry`
- `src/discord.ts` — Thread metadata through to memory commands, short-term, and user-turn-to-durable
- `.context/memory.md` — Documented provenance section
- `templates/workspace/BOOTSTRAP.md` — Expanded onboarding checklist with workflow/online fields
- `templates/workspace/USER.md` — Added Workflow and Online sections
- Tests added for all provenance features

# Findings
- License bead was straightforward — no compilation or test impact
- Memory provenance changes were already complete and tested from a prior session, just needed committing

# Follow-ups
- None — both features are complete and tested
