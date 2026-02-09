import { describe, expect, it } from 'vitest';

import { resolveDiscordChannelContext } from './discord/channel-context.js';

describe('resolveDiscordChannelContext', () => {
  it('returns no contextPath for unknown guild channels (strict mode can require indexing)', () => {
    const ctx = {
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
    const res = resolveDiscordChannelContext({ ctx, isDm: false, channelId: '1', threadParentId: null });
    expect(res.contextPath).toBeUndefined();
  });

  it('uses dm context for DMs', () => {
    const ctx = {
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
    const res = resolveDiscordChannelContext({ ctx, isDm: true, channelId: 'dmchan', threadParentId: null });
    expect(res.contextPath).toBe('/content/discord/channels/dm.md');
  });
});
