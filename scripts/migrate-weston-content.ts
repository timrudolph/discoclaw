import 'dotenv/config';

import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

import { ensureIndexedDiscordChannelContext, loadDiscordChannelContext } from '../src/discord/channel-context.js';

const __filename_migrate = fileURLToPath(import.meta.url);
const __dirname_migrate = path.dirname(__filename_migrate);

function hasFlag(flag: string): boolean {
  return process.argv.includes(flag);
}

function getArgValue(flag: string): string | null {
  const idx = process.argv.indexOf(flag);
  if (idx === -1) return null;
  return process.argv[idx + 1] ?? null;
}

async function fileExists(p: string): Promise<boolean> {
  try {
    await fs.stat(p);
    return true;
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === 'ENOENT') return false;
    throw err;
  }
}

async function copyFile(opts: { src: string; dst: string; overwrite: boolean; dryRun: boolean }) {
  if (!opts.overwrite && await fileExists(opts.dst)) return { copied: false, reason: 'exists' as const };
  if (opts.dryRun) return { copied: true, reason: 'dry-run' as const };
  await fs.mkdir(path.dirname(opts.dst), { recursive: true });
  await fs.copyFile(opts.src, opts.dst);
  return { copied: true, reason: 'copied' as const };
}

function parseLegacyDiscordIndex(md: string): Array<{ channelName: string; channelId: string; legacyFileBase?: string }> {
  // Accept both old Weston DISCORD.md rows and Discoclaw index rows.
  // Examples:
  // | #gallery | 146509... | `discord/gallery.md` | ... |
  // | #gallery | 146509... | `discord/channels/gallery.md` | ... |
  const out: Array<{ channelName: string; channelId: string; legacyFileBase?: string }> = [];
  const lines = md.split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed.startsWith('|')) continue;
    const cells = trimmed
      .split('|')
      .map((c) => c.trim())
      .filter((c) => c.length > 0);
    if (cells.length < 2) continue;
    const chanCell = cells[0] ?? '';
    const idCell = cells[1] ?? '';
    if (!chanCell.startsWith('#')) continue;
    if (!/^\d{17,20}$/.test(idCell)) continue;

    const channelName = chanCell.replace(/^#+/, '').trim();
    const channelId = idCell;

    let legacyFileBase: string | undefined = undefined;
    const ctxCell = cells[2] ?? '';
    if (ctxCell && ctxCell !== '—' && ctxCell !== '-') {
      const unquoted = ctxCell.replace(/`/g, '').trim();
      const base = path.basename(unquoted);
      if (base && base.toLowerCase().endsWith('.md')) legacyFileBase = base;
    }

    out.push({ channelName, channelId, legacyFileBase });
  }
  return out;
}

function ensureLegacyLinkInStub(args: { stubBody: string; legacyRel: string }): { next: string; changed: boolean } {
  if (args.stubBody.includes(args.legacyRel)) return { next: args.stubBody, changed: false };
  // Only mutate files that look like our stub template.
  if (!args.stubBody.includes('Channel-specific notes:')) return { next: args.stubBody, changed: false };

  const lines = args.stubBody.split(/\r?\n/);
  const idx = lines.findIndex((l) => l.trim() === 'Channel-specific notes:');
  if (idx === -1) return { next: args.stubBody, changed: false };

  // Insert immediately after the "Channel-specific notes:" line (keep blank bullet intact).
  lines.splice(idx + 1, 0, `- Legacy notes: ${args.legacyRel}`);
  return { next: lines.join('\n'), changed: true };
}

async function main() {
  const dryRun = hasFlag('--dry-run');
  const overwrite = hasFlag('--overwrite');

  const fromDir = (getArgValue('--from') ?? '').trim() || path.join(process.cwd(), 'legacy', 'weston');

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

  const legacyIndexPath = path.join(fromDir, 'DISCORD.md');
  if (!await fileExists(legacyIndexPath)) {
    log.error({ legacyIndexPath }, 'Legacy DISCORD.md not found');
    process.exit(2);
  }

  const contextModulesDir = path.join(__dirname_migrate, '..', '.context');
  const ctx = await loadDiscordChannelContext({ contentDir, contextModulesDir, log });

  // Keep a copy of the legacy index for reference.
  await copyFile({
    src: legacyIndexPath,
    dst: path.join(contentDir, 'discord', 'DISCORD.legacy.md'),
    overwrite,
    dryRun,
  });

  const legacyIndexMd = await fs.readFile(legacyIndexPath, 'utf8');
  const rows = parseLegacyDiscordIndex(legacyIndexMd);

  let ensured = 0;
  let legacyCopied = 0;
  let stubLinked = 0;

  for (const row of rows) {
    const entry = await ensureIndexedDiscordChannelContext({
      ctx,
      channelId: row.channelId,
      channelName: row.channelName,
      log,
    });
    ensured++;

    // Copy legacy per-channel file into a sidecar file, then link it from the stub.
    const base = row.legacyFileBase ?? `${row.channelName}.md`;
    const legacySrc = path.join(fromDir, 'discord', base);
    if (!await fileExists(legacySrc)) continue;

    const legacyDst = path.join(contentDir, 'discord', 'channels', path.basename(base, '.md') + '.legacy.md');
    const legacyRelFromStub = `./${path.basename(legacyDst)}`;

    const res = await copyFile({ src: legacySrc, dst: legacyDst, overwrite, dryRun });
    if (res.copied) legacyCopied++;

    if (!dryRun) {
      const stubPath = entry.contextPath;
      const stubBody = await fs.readFile(stubPath, 'utf8');
      const { next, changed } = ensureLegacyLinkInStub({ stubBody, legacyRel: legacyRelFromStub });
      if (changed) {
        await fs.writeFile(stubPath, next, 'utf8');
        stubLinked++;
      }
    }
  }

  log.info(
    {
      fromDir,
      contentDir,
      channelsInLegacyIndex: rows.length,
      ensured,
      legacyCopied,
      stubLinked,
      dryRun,
      overwrite,
    },
    'migrate:weston-content done',
  );
}

await main();

