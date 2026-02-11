import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { BeadData } from '../beads/types.js';

import { loadWorkspaceMemoryFile, loadDailyLogFiles, buildBeadContextSection, buildBeadThreadSection } from './prompt-common.js';

describe('loadWorkspaceMemoryFile', () => {
  const dirs: string[] = [];
  afterEach(async () => {
    for (const d of dirs) await fs.rm(d, { recursive: true, force: true });
    dirs.length = 0;
  });

  it('returns path when MEMORY.md exists', async () => {
    const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'pc-test-'));
    dirs.push(workspace);
    await fs.writeFile(path.join(workspace, 'MEMORY.md'), '# Memory', 'utf-8');

    const result = await loadWorkspaceMemoryFile(workspace);
    expect(result).toBe(path.join(workspace, 'MEMORY.md'));
  });

  it('returns null when MEMORY.md does not exist', async () => {
    const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'pc-test-'));
    dirs.push(workspace);

    const result = await loadWorkspaceMemoryFile(workspace);
    expect(result).toBeNull();
  });
});

describe('loadDailyLogFiles', () => {
  const dirs: string[] = [];
  afterEach(async () => {
    for (const d of dirs) await fs.rm(d, { recursive: true, force: true });
    dirs.length = 0;
  });

  function dateStr(d: Date): string {
    return d.toISOString().slice(0, 10);
  }

  it('returns today and yesterday log paths when both exist', async () => {
    const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'pc-test-'));
    dirs.push(workspace);
    const memDir = path.join(workspace, 'memory');
    await fs.mkdir(memDir, { recursive: true });

    const today = new Date();
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);

    await fs.writeFile(path.join(memDir, dateStr(today) + '.md'), 'today', 'utf-8');
    await fs.writeFile(path.join(memDir, dateStr(yesterday) + '.md'), 'yesterday', 'utf-8');

    const result = await loadDailyLogFiles(workspace);
    expect(result).toEqual([
      path.join(memDir, dateStr(today) + '.md'),
      path.join(memDir, dateStr(yesterday) + '.md'),
    ]);
  });

  it('returns only today when yesterday does not exist', async () => {
    const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'pc-test-'));
    dirs.push(workspace);
    const memDir = path.join(workspace, 'memory');
    await fs.mkdir(memDir, { recursive: true });

    const today = new Date();
    await fs.writeFile(path.join(memDir, dateStr(today) + '.md'), 'today', 'utf-8');

    const result = await loadDailyLogFiles(workspace);
    expect(result).toEqual([path.join(memDir, dateStr(today) + '.md')]);
  });

  it('returns empty array when no daily logs exist', async () => {
    const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'pc-test-'));
    dirs.push(workspace);

    const result = await loadDailyLogFiles(workspace);
    expect(result).toEqual([]);
  });

  it('returns empty array when memory dir does not exist', async () => {
    const workspace = await fs.mkdtemp(path.join(os.tmpdir(), 'pc-test-'));
    dirs.push(workspace);

    const result = await loadDailyLogFiles(workspace);
    expect(result).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// buildBeadContextSection
// ---------------------------------------------------------------------------

function makeBead(overrides: Partial<BeadData> = {}): BeadData {
  return { id: 'ws-042', title: 'Fix auth bug', status: 'in_progress', ...overrides };
}

describe('buildBeadContextSection', () => {
  it('formats all fields as JSON', () => {
    const bead = makeBead({
      priority: 2,
      owner: 'David',
      labels: ['bug', 'auth'],
      description: 'Users are getting 401 errors on login.',
    });
    const section = buildBeadContextSection(bead);
    expect(section).toContain('```json');
    const json = JSON.parse(section.split('```json\n')[1].split('\n```')[0]);
    expect(json.id).toBe('ws-042');
    expect(json.title).toBe('Fix auth bug');
    expect(json.status).toBe('in_progress');
    expect(json.priority).toBe(2);
    expect(json.owner).toBe('David');
    expect(json.labels).toEqual(['bug', 'auth']);
    expect(json.description).toBe('Users are getting 401 errors on login.');
  });

  it('handles missing optional fields', () => {
    const bead = makeBead(); // no priority, owner, labels, description
    const section = buildBeadContextSection(bead);
    const json = JSON.parse(section.split('```json\n')[1].split('\n```')[0]);
    expect(json.id).toBe('ws-042');
    expect(json.priority).toBeUndefined();
    expect(json.owner).toBeUndefined();
    expect(json.labels).toBeUndefined();
    expect(json.description).toBeUndefined();
  });

  it('truncates long descriptions', () => {
    const longDesc = 'A'.repeat(600);
    const bead = makeBead({ description: longDesc });
    const section = buildBeadContextSection(bead);
    const json = JSON.parse(section.split('```json\n')[1].split('\n```')[0]);
    expect(json.description.length).toBe(500);
    expect(json.description).toMatch(/\u2026$/);
  });
});

// ---------------------------------------------------------------------------
// buildBeadThreadSection
// ---------------------------------------------------------------------------

// Mock the cache so we don't need a real bd CLI.
vi.mock('../beads/bead-thread-cache.js', () => ({
  beadThreadCache: {
    get: vi.fn(),
  },
}));

import { beadThreadCache } from '../beads/bead-thread-cache.js';

const mockedCacheGet = vi.mocked(beadThreadCache.get);

const SNOWFLAKE_FORUM_ID = '12345678901234567890';

function makeBeadCtx(overrides: Partial<{ beadsCwd: string; forumId: string }> = {}) {
  return {
    beadsCwd: '/tmp/beads',
    forumId: SNOWFLAKE_FORUM_ID,
    tagMap: {},
    runtime: {} as any,
    autoTag: false,
    autoTagModel: 'haiku',
    ...overrides,
  };
}

describe('buildBeadThreadSection', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns empty string when not a thread', async () => {
    const result = await buildBeadThreadSection({
      isThread: false,
      threadId: null,
      threadParentId: null,
      beadCtx: makeBeadCtx(),
    });
    expect(result).toBe('');
  });

  it('returns empty string when beadCtx is undefined', async () => {
    const result = await buildBeadThreadSection({
      isThread: true,
      threadId: 'thread-1',
      threadParentId: SNOWFLAKE_FORUM_ID,
      beadCtx: undefined,
    });
    expect(result).toBe('');
  });

  it('returns empty string when threadParentId does not match forumId', async () => {
    const result = await buildBeadThreadSection({
      isThread: true,
      threadId: 'thread-1',
      threadParentId: '99999999999999999999',
      beadCtx: makeBeadCtx(),
    });
    expect(result).toBe('');
  });

  it('returns empty string when forumId is not a snowflake (logs warning)', async () => {
    const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
    const result = await buildBeadThreadSection({
      isThread: true,
      threadId: 'thread-1',
      threadParentId: 'beads',
      beadCtx: makeBeadCtx({ forumId: 'beads' }),
      log,
    });
    expect(result).toBe('');
    expect(log.warn).toHaveBeenCalledWith(
      expect.objectContaining({ forumId: 'beads' }),
      expect.stringContaining('not a snowflake'),
    );
  });

  it('returns formatted section when bead found', async () => {
    mockedCacheGet.mockResolvedValue(makeBead({ priority: 1, owner: 'David' }));
    const result = await buildBeadThreadSection({
      isThread: true,
      threadId: 'thread-1',
      threadParentId: SNOWFLAKE_FORUM_ID,
      beadCtx: makeBeadCtx(),
    });
    expect(result).toContain('Bead task context');
    expect(result).toContain('```json');
    expect(result).toContain('ws-042');
  });

  it('returns empty string when bead not found', async () => {
    mockedCacheGet.mockResolvedValue(null);
    const result = await buildBeadThreadSection({
      isThread: true,
      threadId: 'thread-1',
      threadParentId: SNOWFLAKE_FORUM_ID,
      beadCtx: makeBeadCtx(),
    });
    expect(result).toBe('');
  });

  it('returns empty string when cache throws (graceful degradation)', async () => {
    mockedCacheGet.mockRejectedValue(new Error('bd CLI not available'));
    const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
    const result = await buildBeadThreadSection({
      isThread: true,
      threadId: 'thread-1',
      threadParentId: SNOWFLAKE_FORUM_ID,
      beadCtx: makeBeadCtx(),
      log,
    });
    expect(result).toBe('');
    expect(log.warn).toHaveBeenCalled();
  });
});
