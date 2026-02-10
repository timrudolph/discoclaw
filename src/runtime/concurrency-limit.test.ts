import { describe, expect, it, vi } from 'vitest';

import { withConcurrencyLimit } from './concurrency-limit.js';
import type { EngineEvent, RuntimeAdapter } from './types.js';

function makeDeferred<T>() {
  let resolve!: (v: T) => void;
  let reject!: (e: unknown) => void;
  const promise = new Promise<T>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

describe('withConcurrencyLimit', () => {
  it('serializes invocations when maxConcurrentInvocations=1', async () => {
    const started: string[] = [];
    const finishA = makeDeferred<void>();
    const finishB = makeDeferred<void>();

    const runtime: RuntimeAdapter = {
      id: 'other',
      capabilities: new Set(['streaming_text']),
      async *invoke(params): AsyncIterable<EngineEvent> {
        started.push(params.prompt);
        if (params.prompt === 'A') await finishA.promise;
        if (params.prompt === 'B') await finishB.promise;
        yield { type: 'text_final', text: params.prompt };
        yield { type: 'done' };
      },
    };

    const limited = withConcurrencyLimit(runtime, { maxConcurrentInvocations: 1 });

    const consume = async (prompt: string) => {
      const out: EngineEvent[] = [];
      for await (const evt of limited.invoke({ prompt, model: 'm', cwd: '/tmp' })) {
        out.push(evt);
      }
      return out;
    };

    const pA = consume('A');
    // Let A acquire the slot and start.
    await vi.waitFor(() => {
      expect(started).toEqual(['A']);
    });

    const pB = consume('B');

    // B should not start until A finishes.
    await new Promise((r) => setTimeout(r, 25));
    expect(started).toEqual(['A']);

    finishA.resolve();
    await vi.waitFor(() => {
      expect(started).toEqual(['A', 'B']);
    });

    finishB.resolve();
    const [outA, outB] = await Promise.all([pA, pB]);
    expect(outA.some((e) => e.type === 'text_final' && e.text === 'A')).toBe(true);
    expect(outB.some((e) => e.type === 'text_final' && e.text === 'B')).toBe(true);
  });

  it('is a no-op when maxConcurrentInvocations=0', async () => {
    const started: string[] = [];
    const finishA = makeDeferred<void>();
    const finishB = makeDeferred<void>();

    const runtime: RuntimeAdapter = {
      id: 'other',
      capabilities: new Set(['streaming_text']),
      async *invoke(params): AsyncIterable<EngineEvent> {
        started.push(params.prompt);
        if (params.prompt === 'A') await finishA.promise;
        if (params.prompt === 'B') await finishB.promise;
        yield { type: 'done' };
      },
    };

    const limited = withConcurrencyLimit(runtime, { maxConcurrentInvocations: 0 });

    const pA = (async () => {
      for await (const _ of limited.invoke({ prompt: 'A', model: 'm', cwd: '/tmp' })) {
        // ignore
      }
    })();
    const pB = (async () => {
      for await (const _ of limited.invoke({ prompt: 'B', model: 'm', cwd: '/tmp' })) {
        // ignore
      }
    })();

    await vi.waitFor(() => {
      expect(new Set(started)).toEqual(new Set(['A', 'B']));
    });

    finishA.resolve();
    finishB.resolve();
    await Promise.all([pA, pB]);
  });
});

