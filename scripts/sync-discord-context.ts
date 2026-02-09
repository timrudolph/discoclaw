import 'dotenv/config';

import path from 'node:path';
import process from 'node:process';
import fs from 'node:fs/promises';

import { ensureIndexedDiscordChannelContext, loadDiscordChannelContext } from '../src/discord/channel-context.js';

function getArgValue(flag: string): string | null {
  const idx = process.argv.indexOf(flag);
  if (idx === -1) return null;
  return process.argv[idx + 1] ?? null;
}

function hasFlag(flag: string): boolean {
  return process.argv.includes(flag);
}

function parseAddChannelArgs(argv: string[]): Array<{ channelId: string; channelName?: string }> {
  const out: Array<{ channelId: string; channelName?: string }> = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] !== '--add-channel') continue;
    const v = argv[i + 1] ?? '';
    if (!v) continue;
    const [id, ...rest] = v.split(':');
    const channelId = String(id ?? '').trim();
    const channelName = rest.join(':').trim() || undefined;
    if (!/^\d{17,20}$/.test(channelId)) continue;
    out.push({ channelId, channelName });
  }
  return out;
}

async function rewriteIndex(indexPath: string, ctx: Awaited<ReturnType<typeof loadDiscordChannelContext>>) {
  const entries = Array.from(ctx.byChannelId.values()).sort((a, b) => a.channelName.localeCompare(b.channelName));
  const lines: string[] = [];
  lines.push('# DISCORD.md - Channel Context Index');
  lines.push('');
  lines.push('| Channel | ID | Context File | Purpose |');
  lines.push('|---------|----|--------------|---------|');
  for (const e of entries) {
    const file = `discord/channels/${path.basename(e.contextPath)}`;
    lines.push(`| #${e.channelName} | ${e.channelId} | \`${file}\` | — |`);
  }
  lines.push('');

  await fs.mkdir(path.dirname(indexPath), { recursive: true });
  await fs.writeFile(indexPath, lines.join('\n'), 'utf8');
}

async function main() {
  const dataDir = (process.env.DISCOCLAW_DATA_DIR ?? '').trim();
  const contentDir =
    (getArgValue('--content-dir') ?? '').trim() ||
    (process.env.DISCOCLAW_CONTENT_DIR ?? '').trim() ||
    (dataDir ? path.join(dataDir, 'content') : path.join(process.cwd(), 'content'));

  const log = {
    info: (obj: unknown, msg?: string) => console.log(msg ?? '', obj ?? ''),
    warn: (obj: unknown, msg?: string) => console.warn(msg ?? '', obj ?? ''),
    error: (obj: unknown, msg?: string) => console.error(msg ?? '', obj ?? ''),
  };

  const ctx = await loadDiscordChannelContext({ contentDir, log });

  const adds = parseAddChannelArgs(process.argv);
  for (const a of adds) {
    await ensureIndexedDiscordChannelContext({
      ctx,
      channelId: a.channelId,
      channelName: a.channelName,
      log,
    });
  }

  if (hasFlag('--rewrite-index')) {
    await rewriteIndex(ctx.indexPath, ctx);
    log.info({ indexPath: ctx.indexPath }, 'rewrite-index: done');
  }

  log.info(
    {
      contentDir,
      indexPath: ctx.indexPath,
      channelsDir: ctx.channelsDir,
      channelsCount: ctx.byChannelId.size,
      createdBase: [ctx.baseCorePath, ctx.baseSafetyPath],
    },
    'sync: done',
  );
}

await main();

