import { describe, expect, it, vi } from 'vitest';
import { createStatusPoster } from './status-channel.js';

function mockChannel() {
  return { send: vi.fn().mockResolvedValue(undefined) } as any;
}

function mockLog() {
  return { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
}

describe('createStatusPoster', () => {
  it('online() sends a green embed', async () => {
    const ch = mockChannel();
    const poster = createStatusPoster(ch);
    await poster.online();
    expect(ch.send).toHaveBeenCalledOnce();
    const embed = ch.send.mock.calls[0][0].embeds[0];
    expect(embed.data.color).toBe(0x57f287);
    expect(embed.data.title).toBe('Bot Online');
  });

  it('offline() sends a gray embed', async () => {
    const ch = mockChannel();
    const poster = createStatusPoster(ch);
    await poster.offline();
    expect(ch.send).toHaveBeenCalledOnce();
    const embed = ch.send.mock.calls[0][0].embeds[0];
    expect(embed.data.color).toBe(0x95a5a6);
    expect(embed.data.title).toBe('Bot Offline');
  });

  it('runtimeError() sends a red embed with context', async () => {
    const ch = mockChannel();
    const poster = createStatusPoster(ch);
    await poster.runtimeError({ sessionKey: 'dm:123', channelName: 'general' }, 'timeout');
    expect(ch.send).toHaveBeenCalledOnce();
    const embed = ch.send.mock.calls[0][0].embeds[0];
    expect(embed.data.color).toBe(0xed4245);
    expect(embed.data.title).toBe('Runtime Error');
    expect(embed.data.description).toBe('timeout');
    expect(embed.data.fields).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ name: 'Session', value: 'dm:123' }),
        expect.objectContaining({ name: 'Channel', value: 'general' }),
      ]),
    );
  });

  it('handlerError() sends a red embed', async () => {
    const ch = mockChannel();
    const poster = createStatusPoster(ch);
    await poster.handlerError({ sessionKey: 'g:1:c:2' }, new Error('boom'));
    expect(ch.send).toHaveBeenCalledOnce();
    const embed = ch.send.mock.calls[0][0].embeds[0];
    expect(embed.data.color).toBe(0xed4245);
    expect(embed.data.title).toBe('Handler Failure');
    expect(embed.data.description).toContain('boom');
  });

  it('actionFailed() sends an orange embed', async () => {
    const ch = mockChannel();
    const poster = createStatusPoster(ch);
    await poster.actionFailed('channelCreate', 'Missing perms');
    expect(ch.send).toHaveBeenCalledOnce();
    const embed = ch.send.mock.calls[0][0].embeds[0];
    expect(embed.data.color).toBe(0xfee75c);
    expect(embed.data.title).toBe('Action Failed');
    expect(embed.data.fields).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ name: 'Action', value: 'channelCreate' }),
        expect.objectContaining({ name: 'Error', value: 'Missing perms' }),
      ]),
    );
  });

  it('beadSyncComplete() sends green embed with non-zero fields', async () => {
    const ch = mockChannel();
    const poster = createStatusPoster(ch);
    await poster.beadSyncComplete({
      threadsCreated: 1, emojisUpdated: 0, starterMessagesUpdated: 2, threadsArchived: 3, statusesUpdated: 0, warnings: 0,
    });
    expect(ch.send).toHaveBeenCalledOnce();
    const embed = ch.send.mock.calls[0][0].embeds[0];
    expect(embed.data.color).toBe(0x57f287);
    expect(embed.data.title).toBe('Bead Sync Complete');
    const fieldNames = embed.data.fields.map((f: any) => f.name);
    expect(fieldNames).toContain('Created');
    expect(fieldNames).toContain('Starters Updated');
    expect(fieldNames).toContain('Archived');
    expect(fieldNames).not.toContain('Names Updated');
    expect(fieldNames).not.toContain('Statuses Fixed');
    expect(fieldNames).not.toContain('Warnings');
  });

  it('beadSyncComplete() sends orange embed when warnings > 0', async () => {
    const ch = mockChannel();
    const poster = createStatusPoster(ch);
    await poster.beadSyncComplete({
      threadsCreated: 0, emojisUpdated: 0, starterMessagesUpdated: 0, threadsArchived: 0, statusesUpdated: 0, warnings: 2,
    });
    expect(ch.send).toHaveBeenCalledOnce();
    const embed = ch.send.mock.calls[0][0].embeds[0];
    expect(embed.data.color).toBe(0xfee75c);
    expect(embed.data.title).toBe('Bead Sync Complete');
    const fieldNames = embed.data.fields.map((f: any) => f.name);
    expect(fieldNames).toContain('Warnings');
  });

  it('beadSyncComplete() sends orange embed when warnings > 0 even with non-zero counters', async () => {
    const ch = mockChannel();
    const poster = createStatusPoster(ch);
    await poster.beadSyncComplete({
      threadsCreated: 2, emojisUpdated: 0, starterMessagesUpdated: 0, threadsArchived: 1, statusesUpdated: 0, warnings: 1,
    });
    expect(ch.send).toHaveBeenCalledOnce();
    const embed = ch.send.mock.calls[0][0].embeds[0];
    expect(embed.data.color).toBe(0xfee75c);
    const fieldNames = embed.data.fields.map((f: any) => f.name);
    expect(fieldNames).toContain('Created');
    expect(fieldNames).toContain('Archived');
    expect(fieldNames).toContain('Warnings');
  });

  it('beadSyncComplete() is silent when all counters and warnings are zero', async () => {
    const ch = mockChannel();
    const poster = createStatusPoster(ch);
    await poster.beadSyncComplete({
      threadsCreated: 0, emojisUpdated: 0, starterMessagesUpdated: 0, threadsArchived: 0, statusesUpdated: 0, warnings: 0,
    });
    expect(ch.send).not.toHaveBeenCalled();
  });

  it('does not throw when channel.send fails', async () => {
    const ch = { send: vi.fn().mockRejectedValue(new Error('network')) } as any;
    const log = mockLog();
    const poster = createStatusPoster(ch, { log });
    await expect(poster.online()).resolves.toBeUndefined();
    expect(log.warn).toHaveBeenCalledOnce();
  });
});
