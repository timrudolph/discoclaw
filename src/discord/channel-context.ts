import fs from 'node:fs/promises';
import path from 'node:path';

export type ChannelContextEntry = {
  channelId: string;
  channelName: string;
  // Absolute path to the per-channel context file.
  contextPath: string;
};

export type DiscordChannelContext = {
  contentDir: string;
  indexPath: string;
  channelsDir: string;
  byChannelId: Map<string, ChannelContextEntry>;
  defaultContextPath: string;
  dmContextPath: string;
};

type LoggerLike = {
  info(obj: unknown, msg?: string): void;
  warn(obj: unknown, msg?: string): void;
  error(obj: unknown, msg?: string): void;
};

function parseChannelIndexMarkdown(md: string, channelsDir: string): Map<string, ChannelContextEntry> {
  // Parse rows like:
  // | #gallery | 1465092721646637087 | `discord/gallery.md` | ... |
  // We only need channel name + id + context file hint.
  const out = new Map<string, ChannelContextEntry>();

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

    let contextPath = path.join(channelsDir, `${channelName}.md`);
    const ctxCell = cells[2] ?? '';
    // Prefer explicit context file mapping when present.
    if (ctxCell && ctxCell !== '—' && ctxCell !== '-') {
      const unquoted = ctxCell.replace(/`/g, '').trim();
      const base = path.basename(unquoted);
      if (base && base.toLowerCase().endsWith('.md')) {
        contextPath = path.join(channelsDir, base);
      }
    }

    out.set(channelId, { channelId, channelName, contextPath });
  }

  return out;
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

async function writeFileIfMissing(p: string, body: string): Promise<boolean> {
  if (await fileExists(p)) return false;
  await fs.mkdir(path.dirname(p), { recursive: true });
  await fs.writeFile(p, body, 'utf8');
  return true;
}

export async function loadDiscordChannelContext(opts: {
  contentDir: string;
  log?: LoggerLike;
}): Promise<DiscordChannelContext> {
  const contentDir = opts.contentDir;
  const indexPath = path.join(contentDir, 'discord', 'DISCORD.md');
  const channelsDir = path.join(contentDir, 'discord', 'channels');
  const defaultContextPath = path.join(channelsDir, '_default.md');
  const dmContextPath = path.join(channelsDir, 'dm.md');

  // Ensure we always have a fallback context file, even if the index is missing.
  await writeFileIfMissing(
    defaultContextPath,
    [
      '# Default Channel Context',
      '',
      'This is the fallback context when a Discord channel has no specific context file.',
      '',
      'Rules:',
      '- Ask clarifying questions when the channel purpose is unclear.',
      '- Keep responses concise and practical.',
      '- Do not assume hidden context; use files when referenced.',
      '',
    ].join('\n'),
  );
  await writeFileIfMissing(
    dmContextPath,
    [
      '# DM Context',
      '',
      'This context applies to direct messages.',
      '',
      'Rules:',
      '- Treat DMs as private support requests.',
      '- Ask clarifying questions and confirm risky actions.',
      '',
    ].join('\n'),
  );

  let md = '';
  try {
    md = await fs.readFile(indexPath, 'utf8');
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code !== 'ENOENT') throw err;
    opts.log?.warn({ indexPath }, 'discord:context index missing; using fallback only');
    md = '';
  }

  const byChannelId = md ? parseChannelIndexMarkdown(md, channelsDir) : new Map<string, ChannelContextEntry>();

  // Guarantee that every indexed channel has a context file (create placeholders for missing).
  let created = 0;
  for (const entry of byChannelId.values()) {
    const didCreate = await writeFileIfMissing(
      entry.contextPath,
      [
        `# #${entry.channelName} Context`,
        '',
        `Channel ID: ${entry.channelId}`,
        '',
        'TODO: Add channel-specific background, constraints, and definitions.',
        '',
        'Default rules:',
        '- Keep responses scoped to this channel purpose.',
        '- Prefer referencing files instead of pasting large blobs.',
        '',
      ].join('\n'),
    );
    if (didCreate) created++;
  }
  if (created > 0) {
    opts.log?.info({ created, channelsDir }, 'discord:context bootstrapped missing channel context files');
  }

  return {
    contentDir,
    indexPath,
    channelsDir,
    byChannelId,
    defaultContextPath,
    dmContextPath,
  };
}

export function resolveDiscordChannelContext(args: {
  ctx: DiscordChannelContext | undefined;
  isDm: boolean;
  channelId: string;
  threadParentId?: string | null;
}): { channelId: string; channelName?: string; contextPath?: string } {
  const ctx = args.ctx;
  if (!ctx) return { channelId: args.channelId };

  if (args.isDm) {
    return { channelId: args.channelId, channelName: 'dm', contextPath: ctx.dmContextPath };
  }

  const id = (args.threadParentId && args.threadParentId.trim()) ? args.threadParentId : args.channelId;
  const hit = ctx.byChannelId.get(id);
  if (hit) return { channelId: id, channelName: hit.channelName, contextPath: hit.contextPath };
  return { channelId: id, channelName: 'unknown', contextPath: ctx.defaultContextPath };
}

