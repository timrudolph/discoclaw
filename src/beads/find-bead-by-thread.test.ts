import { describe, expect, it, vi } from 'vitest';
import type { BeadData } from './types.js';

// Mock execa so bdList doesn't spawn a real process.
vi.mock('execa', () => ({
  execa: vi.fn(),
}));

import { execa } from 'execa';
import { findBeadByThreadId } from './bead-thread-cache.js';

const mockedExeca = vi.mocked(execa);

function makeBeadList(beads: Partial<BeadData>[]): string {
  return JSON.stringify(beads.map((b) => ({
    id: 'ws-001',
    title: 'Test',
    status: 'open',
    ...b,
  })));
}

describe('findBeadByThreadId', () => {
  it('returns bead when external_ref matches as discord:<threadId>', async () => {
    mockedExeca.mockResolvedValue({
      stdout: makeBeadList([
        { id: 'ws-001', external_ref: 'discord:111222333444555666' },
        { id: 'ws-002', external_ref: 'discord:999888777666555444' },
      ]),
      exitCode: 0,
    } as any);

    const result = await findBeadByThreadId('111222333444555666', '/tmp');
    expect(result?.id).toBe('ws-001');
  });

  it('returns bead when external_ref is raw numeric ID', async () => {
    mockedExeca.mockResolvedValue({
      stdout: makeBeadList([
        { id: 'ws-003', external_ref: '111222333444555666' },
      ]),
      exitCode: 0,
    } as any);

    const result = await findBeadByThreadId('111222333444555666', '/tmp');
    expect(result?.id).toBe('ws-003');
  });

  it('returns null when no match', async () => {
    mockedExeca.mockResolvedValue({
      stdout: makeBeadList([
        { id: 'ws-001', external_ref: 'discord:999888777666555444' },
      ]),
      exitCode: 0,
    } as any);

    const result = await findBeadByThreadId('111222333444555666', '/tmp');
    expect(result).toBeNull();
  });

  it('returns null when bdList returns empty', async () => {
    mockedExeca.mockResolvedValue({
      stdout: '[]',
      exitCode: 0,
    } as any);

    const result = await findBeadByThreadId('111222333444555666', '/tmp');
    expect(result).toBeNull();
  });
});
