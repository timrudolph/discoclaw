import { describe, expect, it, vi, beforeEach } from 'vitest';
import type { BeadData } from './types.js';

// Mock the external dependencies that findBeadByThreadId calls internally.
vi.mock('./bd-cli.js', () => ({
  bdList: vi.fn(),
}));
vi.mock('./discord-sync.js', () => ({
  getThreadIdFromBead: vi.fn((b: BeadData) => {
    const ref = (b.external_ref ?? '').trim();
    if (!ref) return null;
    if (ref.startsWith('discord:')) return ref.slice('discord:'.length).trim() || null;
    if (/^\d+$/.test(ref)) return ref;
    return null;
  }),
}));

import { bdList } from './bd-cli.js';
import { BeadThreadCache } from './bead-thread-cache.js';

const mockedBdList = vi.mocked(bdList);

function makeBead(overrides: Partial<BeadData> = {}): BeadData {
  return { id: 'ws-001', title: 'Test', status: 'open', external_ref: 'discord:thread-1', ...overrides };
}

function setupBdList(beads: BeadData[]) {
  mockedBdList.mockResolvedValue(beads);
}

describe('BeadThreadCache', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns cached bead within TTL', async () => {
    const cache = new BeadThreadCache(60_000);
    const bead = makeBead();
    setupBdList([bead]);

    const first = await cache.get('thread-1', '/tmp');
    expect(first?.id).toBe('ws-001');
    expect(mockedBdList).toHaveBeenCalledTimes(1);

    // Second call should use cache, not call bdList again.
    const second = await cache.get('thread-1', '/tmp');
    expect(second?.id).toBe('ws-001');
    expect(mockedBdList).toHaveBeenCalledTimes(1);
  });

  it('refetches after TTL expires', async () => {
    const cache = new BeadThreadCache(0); // 0ms TTL = always expired
    const bead1 = makeBead({ id: 'ws-001', external_ref: 'discord:thread-1' });
    const bead2 = makeBead({ id: 'ws-002', external_ref: 'discord:thread-1' });
    mockedBdList.mockResolvedValueOnce([bead1]).mockResolvedValueOnce([bead2]);

    const first = await cache.get('thread-1', '/tmp');
    expect(first?.id).toBe('ws-001');

    const second = await cache.get('thread-1', '/tmp');
    expect(second?.id).toBe('ws-002');
    expect(mockedBdList).toHaveBeenCalledTimes(2);
  });

  it('invalidate() clears all entries', async () => {
    const cache = new BeadThreadCache(60_000);
    setupBdList([
      makeBead({ id: 'ws-001', external_ref: 'discord:thread-1' }),
      makeBead({ id: 'ws-002', external_ref: 'discord:thread-2' }),
    ]);

    await cache.get('thread-1', '/tmp');
    await cache.get('thread-2', '/tmp');
    expect(mockedBdList).toHaveBeenCalledTimes(2);

    cache.invalidate();

    await cache.get('thread-1', '/tmp');
    expect(mockedBdList).toHaveBeenCalledTimes(3);
  });

  it('invalidate(threadId) clears single entry', async () => {
    const cache = new BeadThreadCache(60_000);
    setupBdList([
      makeBead({ id: 'ws-001', external_ref: 'discord:thread-1' }),
      makeBead({ id: 'ws-002', external_ref: 'discord:thread-2' }),
    ]);

    await cache.get('thread-1', '/tmp');
    await cache.get('thread-2', '/tmp');
    expect(mockedBdList).toHaveBeenCalledTimes(2);

    cache.invalidate('thread-1');

    // thread-1 should refetch, thread-2 should still be cached.
    await cache.get('thread-1', '/tmp');
    await cache.get('thread-2', '/tmp');
    expect(mockedBdList).toHaveBeenCalledTimes(3);
  });

  it('returns null when no bead matches', async () => {
    const cache = new BeadThreadCache(60_000);
    setupBdList([]);

    const result = await cache.get('thread-1', '/tmp');
    expect(result).toBeNull();
  });

  it('caches null results (negative cache)', async () => {
    const cache = new BeadThreadCache(60_000);
    setupBdList([]);

    const first = await cache.get('thread-1', '/tmp');
    expect(first).toBeNull();

    const second = await cache.get('thread-1', '/tmp');
    expect(second).toBeNull();
    // Only one bdList call — the null was cached.
    expect(mockedBdList).toHaveBeenCalledTimes(1);
  });
});
