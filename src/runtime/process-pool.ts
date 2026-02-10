import { LongRunningProcess, type LongRunningProcessOpts } from './long-running-process.js';

export type ProcessPoolOpts = {
  maxProcesses?: number;
  log?: { info(...args: unknown[]): void; debug(...args: unknown[]): void };
};

/**
 * Pool of LongRunningProcess instances keyed by Discord session key.
 */
export class ProcessPool {
  private readonly pool = new Map<string, LongRunningProcess>();
  private readonly maxProcesses: number;
  private readonly log?: ProcessPoolOpts['log'];

  constructor(opts?: ProcessPoolOpts) {
    this.maxProcesses = opts?.maxProcesses ?? 5;
    this.log = opts?.log;
  }

  /**
   * Get an existing alive process for the session key, or spawn a new one.
   * Returns null if spawn fails (caller should fall back to one-shot).
   */
  getOrSpawn(sessionKey: string, processOpts: LongRunningProcessOpts): LongRunningProcess | null {
    const existing = this.pool.get(sessionKey);
    if (existing?.isAlive) {
      this.log?.debug({ sessionKey }, 'process-pool: reusing existing process');
      return existing;
    }

    // Remove dead process if present.
    if (existing) {
      this.pool.delete(sessionKey);
    }

    // Evict oldest idle process if at capacity.
    if (this.pool.size >= this.maxProcesses) {
      this.evictOldest();
    }

    // Spawn a new process.
    const proc = new LongRunningProcess(processOpts);
    const ok = proc.spawn();
    if (!ok) {
      this.log?.info({ sessionKey }, 'process-pool: spawn failed');
      return null;
    }

    // Auto-remove when the process dies.
    proc.onCleanup = () => {
      const current = this.pool.get(sessionKey);
      if (current === proc) {
        this.pool.delete(sessionKey);
      }
    };

    this.pool.set(sessionKey, proc);
    this.log?.info({ sessionKey, poolSize: this.pool.size }, 'process-pool: spawned new process');
    return proc;
  }

  /** Kill and remove a specific session's process. */
  remove(sessionKey: string): void {
    const proc = this.pool.get(sessionKey);
    if (proc) {
      this.pool.delete(sessionKey);
      proc.kill();
      this.log?.info({ sessionKey }, 'process-pool: removed process');
    }
  }

  /** Kill all processes (shutdown cleanup). */
  killAll(): void {
    for (const [key, proc] of this.pool) {
      proc.forceKill();
      this.log?.debug({ sessionKey: key }, 'process-pool: killed process');
    }
    this.pool.clear();
  }

  get size(): number {
    return this.pool.size;
  }

  private evictOldest(): void {
    // Evict the first idle process found (Map preserves insertion order).
    for (const [key, proc] of this.pool) {
      if (proc.state === 'idle') {
        this.pool.delete(key);
        proc.kill();
        this.log?.info({ sessionKey: key }, 'process-pool: evicted idle process');
        return;
      }
    }
    // If no idle processes, evict the oldest regardless.
    const firstKey = this.pool.keys().next().value;
    if (firstKey !== undefined) {
      const proc = this.pool.get(firstKey);
      this.pool.delete(firstKey);
      proc?.forceKill();
      this.log?.info({ sessionKey: firstKey }, 'process-pool: evicted oldest process');
    }
  }
}
