import { describe, expect, it, vi } from 'vitest';

import { createMessageCreateHandler } from './discord.js';

function makeQueue() {
  return {
    run: vi.fn(async (_key: string, fn: () => Promise<any>) => fn()),
  };
}

function makeMsg(overrides: Partial<any>) {
  const replyObj = { edit: vi.fn(async () => {}) };
  return {
    author: { id: '123', bot: false },
    guildId: 'guild',
    channelId: 'chan',
    channel: { send: vi.fn(async () => {}), isThread: () => false, name: 'general' },
    content: 'hello',
    reply: vi.fn(async () => replyObj),
    ...overrides,
  };
}

describe('prompt includes correct context file paths', () => {
  it('guild channel uses channel context file', async () => {
    const queue = makeQueue();
    let seenPrompt = '';
    const runtime = {
      invoke: vi.fn(async function* (p: any) {
        seenPrompt = p.prompt;
        yield { type: 'text_final', text: 'ok' } as any;
      }),
    } as any;

    const discordChannelContext = {
      contentDir: '/content',
      indexPath: '/content/discord/DISCORD.md',
      baseDir: '/content/discord/base',
      baseCorePath: '/content/discord/base/core.md',
      baseSafetyPath: '/content/discord/base/safety.md',
      baseCoreLinkFromChannel: '../base/core.md',
      baseSafetyLinkFromChannel: '../base/safety.md',
      channelsDir: '/content/discord/channels',
      byChannelId: new Map([['chan', { channelId: 'chan', channelName: 'general', contextPath: '/content/discord/channels/general.md' }]]),
      dmContextPath: '/content/discord/channels/dm.md',
    };

    const handler = createMessageCreateHandler({
      allowUserIds: new Set(['123']),
      runtime,
      sessionManager: { getOrCreate: vi.fn(async () => 'sess') } as any,
      workspaceCwd: '/tmp',
      groupsDir: '/tmp',
      useGroupDirCwd: false,
      runtimeModel: 'opus',
      runtimeTools: [],
      runtimeTimeoutMs: 1000,
      requireChannelContext: true,
      autoIndexChannelContext: false,
      discordChannelContext: discordChannelContext as any,
    }, queue);

    await handler(makeMsg({ channelId: 'chan' }));

    expect(runtime.invoke).toHaveBeenCalled();
    expect(seenPrompt).toContain('- /content/discord/base/core.md');
    expect(seenPrompt).toContain('- /content/discord/base/safety.md');
    expect(seenPrompt).toContain('- /content/discord/channels/general.md');
    expect(seenPrompt).toContain('User message:\nhello');
  });

  it('thread uses parent channel context file', async () => {
    const queue = makeQueue();
    let seenPrompt = '';
    const runtime = {
      invoke: vi.fn(async function* (p: any) {
        seenPrompt = p.prompt;
        yield { type: 'text_final', text: 'ok' } as any;
      }),
    } as any;

    const discordChannelContext = {
      contentDir: '/content',
      indexPath: '/content/discord/DISCORD.md',
      baseDir: '/content/discord/base',
      baseCorePath: '/content/discord/base/core.md',
      baseSafetyPath: '/content/discord/base/safety.md',
      baseCoreLinkFromChannel: '../base/core.md',
      baseSafetyLinkFromChannel: '../base/safety.md',
      channelsDir: '/content/discord/channels',
      byChannelId: new Map([['parent', { channelId: 'parent', channelName: 'general', contextPath: '/content/discord/channels/general.md' }]]),
      dmContextPath: '/content/discord/channels/dm.md',
    };

    const handler = createMessageCreateHandler({
      allowUserIds: new Set(['123']),
      runtime,
      sessionManager: { getOrCreate: vi.fn(async () => 'sess') } as any,
      workspaceCwd: '/tmp',
      groupsDir: '/tmp',
      useGroupDirCwd: false,
      runtimeModel: 'opus',
      runtimeTools: [],
      runtimeTimeoutMs: 1000,
      requireChannelContext: true,
      autoIndexChannelContext: false,
      discordChannelContext: discordChannelContext as any,
    }, queue);

    await handler(makeMsg({
      channelId: 'thread',
      channel: { send: vi.fn(async () => {}), isThread: () => true, parentId: 'parent', name: 'thread-name', id: 'thread' },
    }));

    expect(runtime.invoke).toHaveBeenCalled();
    expect(seenPrompt).toContain('- /content/discord/channels/general.md');
  });

  it('DM uses dm context file', async () => {
    const queue = makeQueue();
    let seenPrompt = '';
    const runtime = {
      invoke: vi.fn(async function* (p: any) {
        seenPrompt = p.prompt;
        yield { type: 'text_final', text: 'ok' } as any;
      }),
    } as any;

    const discordChannelContext = {
      contentDir: '/content',
      indexPath: '/content/discord/DISCORD.md',
      baseDir: '/content/discord/base',
      baseCorePath: '/content/discord/base/core.md',
      baseSafetyPath: '/content/discord/base/safety.md',
      baseCoreLinkFromChannel: '../base/core.md',
      baseSafetyLinkFromChannel: '../base/safety.md',
      channelsDir: '/content/discord/channels',
      byChannelId: new Map(),
      dmContextPath: '/content/discord/channels/dm.md',
    };

    const handler = createMessageCreateHandler({
      allowUserIds: new Set(['123']),
      runtime,
      sessionManager: { getOrCreate: vi.fn(async () => 'sess') } as any,
      workspaceCwd: '/tmp',
      groupsDir: '/tmp',
      useGroupDirCwd: false,
      runtimeModel: 'opus',
      runtimeTools: [],
      runtimeTimeoutMs: 1000,
      requireChannelContext: true,
      autoIndexChannelContext: false,
      discordChannelContext: discordChannelContext as any,
    }, queue);

    await handler(makeMsg({ guildId: null, channelId: 'dmchan' }));

    expect(runtime.invoke).toHaveBeenCalled();
    expect(seenPrompt).toContain('- /content/discord/channels/dm.md');
  });
});

