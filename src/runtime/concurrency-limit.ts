import type { EngineEvent, RuntimeAdapter, RuntimeInvokeParams } from './types.js';

class Semaphore {
  private active = 0;
  private readonly queue: Array<(release: () => void) => void> = [];

  constructor(private readonly max: number) {}

  async acquire(): Promise<() => void> {
    if (!(this.max > 0)) {
      return () => {};
    }

    if (this.active < this.max) {
      this.active++;
      let released = false;
      return () => {
        if (released) return;
        released = true;
        this.release();
      };
    }

    return await new Promise((resolve) => {
      this.queue.push((release) => resolve(release));
    });
  }

  private release(): void {
    const next = this.queue.shift();
    if (next) {
      // Keep active count constant: transfer slot to the next waiter.
      let released = false;
      next(() => {
        if (released) return;
        released = true;
        this.release();
      });
      return;
    }
    this.active = Math.max(0, this.active - 1);
  }
}

export type ConcurrencyLimitOpts = {
  maxConcurrentInvocations: number;
  log?: { debug?(obj: unknown, msg?: string): void };
};

/**
 * Wrap a runtime adapter with a global concurrency limiter.
 *
 * Important: the permit is held for the entire lifetime of the async iterator,
 * so consumers must exhaust/close the iterator to release the slot.
 */
export function withConcurrencyLimit(runtime: RuntimeAdapter, opts: ConcurrencyLimitOpts): RuntimeAdapter {
  const max = Number.isFinite(opts.maxConcurrentInvocations)
    ? Math.max(0, Math.floor(opts.maxConcurrentInvocations))
    : 0;
  if (max <= 0) return runtime;

  const sem = new Semaphore(max);

  return {
    ...runtime,
    async *invoke(params: RuntimeInvokeParams): AsyncIterable<EngineEvent> {
      const release = await sem.acquire();
      opts.log?.debug?.({ max }, 'runtime:concurrency slot acquired');
      try {
        for await (const evt of runtime.invoke(params)) {
          yield evt;
        }
      } finally {
        release();
        opts.log?.debug?.({ max }, 'runtime:concurrency slot released');
      }
    },
  };
}

