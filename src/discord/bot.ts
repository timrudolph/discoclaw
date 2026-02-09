import { Client, GatewayIntentBits, Partials } from 'discord.js';
import type { RuntimeAdapter } from '../engine/types.js';
import type { SessionManager } from '../sessionManager.js';
import { isAllowlisted } from './allowlist.js';
import { KeyedQueue } from './keyed-queue.js';

export type BotParams = {
  token: string;
  allowUserIds: Set<string>;
  runtime: RuntimeAdapter;
  sessionManager: SessionManager;
  workspaceCwd: string;
};

function discordSessionKey(msg: { channelId: string; authorId: string; isDm: boolean }): string {
  if (msg.isDm) return `discord:dm:${msg.authorId}`;
  return `discord:channel:${msg.channelId}`;
}

function splitDiscord(text: string, limit = 2000): string[] {
  // Minimal fence-safe markdown chunking.
  const normalized = text.replace(/\r\n?/g, '\n');
  if (normalized.length <= limit) return [normalized];

  const rawLines = normalized.split('\n');
  const chunks: string[] = [];

  let cur = '';
  let inFence = false;
  let fenceHeader = '```';

  const ensureFenceOpen = () => {
    if (cur) return;
    if (inFence) cur = `${fenceHeader}\n`;
  };

  const flush = () => {
    if (!cur) return;
    if (inFence && !cur.trimEnd().endsWith('```')) {
      const close = '\n```';
      if (cur.length + close.length <= limit) {
        cur += close;
      }
    }
    chunks.push(cur);
    cur = '';
  };

  const appendLine = (line: string) => {
    ensureFenceOpen();
    const sep = cur.length > 0 ? '\n' : '';
    cur += sep + line;
  };

  for (const line of rawLines) {
    const nextLen = (cur.length ? cur.length + 1 : 0) + line.length;
    if (nextLen > limit) {
      flush();
      // Reopen fence if we flushed mid-fence.
      ensureFenceOpen();
    }

    // If the line itself is too long, hard split.
    if (line.length > limit) {
      let rest = line;
      while (rest.length > 0) {
        const room = Math.max(1, limit - (cur.length ? cur.length + 1 : 0));
        const take = rest.slice(0, room);
        appendLine(take);
        rest = rest.slice(room);
        if (rest.length > 0) {
          flush();
          ensureFenceOpen();
        }
      }
    } else {
      appendLine(line);
    }

    const trimmed = line.trimStart();
    if (trimmed.startsWith('```')) {
      if (!inFence) {
        inFence = true;
        fenceHeader = trimmed.trimEnd();
      } else {
        inFence = false;
        fenceHeader = '```';
      }
    }

    // If we are in a fence and we're close to the limit, proactively flush
    // to reduce the chance of an un-closable fence close.
    if (inFence && cur.length >= limit - 8) {
      flush();
      // Next line will reopen.
    }
  }

  flush();
  return chunks.filter((c) => c.trim().length > 0);
}

export async function startDiscordBot(params: BotParams) {
  const client = new Client({
    intents: [
      GatewayIntentBits.Guilds,
      GatewayIntentBits.GuildMessages,
      GatewayIntentBits.MessageContent,
      GatewayIntentBits.DirectMessages,
    ],
    partials: [Partials.Channel],
  });

  const queue = new KeyedQueue();

  client.on('messageCreate', async (msg) => {
    if (!msg.author || msg.author.bot) return;

    if (!isAllowlisted(params.allowUserIds, msg.author.id)) return;

    const isDm = msg.guildId == null;
    const sessionKey = discordSessionKey({
      channelId: msg.channelId,
      authorId: msg.author.id,
      isDm,
    });

    await queue.run(sessionKey, async () => {
      const sessionId = await params.sessionManager.getOrCreate(sessionKey);
      const reply = await msg.reply('...');

      let finalText = '';
      for await (const evt of params.runtime.invoke({
        prompt: msg.content,
        model: 'opus',
        cwd: params.workspaceCwd,
        sessionId,
        tools: ['Bash', 'Read', 'Edit', 'WebSearch', 'WebFetch'],
        timeoutMs: 10 * 60_000,
      })) {
        if (evt.type === 'text_final') {
          finalText = evt.text;
        } else if (evt.type === 'error') {
          finalText = `Error: ${evt.message}`;
        } else if (evt.type === 'text_delta' && !finalText) {
          // Only use deltas when we don't get a final text payload.
          finalText += evt.text;
        }
      }

      const chunks = splitDiscord(finalText || '(no output)');
      await reply.edit(chunks[0] ?? '(no output)');
      for (const extra of chunks.slice(1)) {
        await msg.channel.send(extra);
      }
    });
  });

  await client.login(params.token);
  return client;
}
