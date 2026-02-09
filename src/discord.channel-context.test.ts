import { describe, expect, it } from 'vitest';

import { resolveDiscordChannelContext } from './discord/channel-context.js';

describe('resolveDiscordChannelContext', () => {
  it('uses default for unknown guild channels', () => {
    const ctx = {
      contentDir: '/content',
      indexPath: '/content/discord/DISCORD.md',
      channelsDir: '/content/discord/channels',
      byChannelId: new Map(),
      defaultContextPath: '/content/discord/channels/_default.md',
      dmContextPath: '/content/discord/channels/dm.md',
    };
    const res = resolveDiscordChannelContext({ ctx, isDm: false, channelId: '1', threadParentId: null });
    expect(res.contextPath).toBe('/content/discord/channels/_default.md');
  });

  it('uses dm context for DMs', () => {
    const ctx = {
      contentDir: '/content',
      indexPath: '/content/discord/DISCORD.md',
      channelsDir: '/content/discord/channels',
      byChannelId: new Map(),
      defaultContextPath: '/content/discord/channels/_default.md',
      dmContextPath: '/content/discord/channels/dm.md',
    };
    const res = resolveDiscordChannelContext({ ctx, isDm: true, channelId: 'dmchan', threadParentId: null });
    expect(res.contextPath).toBe('/content/discord/channels/dm.md');
  });
});

