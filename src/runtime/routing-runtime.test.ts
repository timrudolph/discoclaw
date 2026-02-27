import { describe, expect, it, vi } from 'vitest';
import { createRoutingRuntime } from './routing-runtime.js';
import type { RuntimeAdapter, EngineEvent } from './types.js';

async function collect(iter: AsyncIterable<EngineEvent>): Promise<EngineEvent[]> {
  const events: EngineEvent[] = [];
  for await (const ev of iter) events.push(ev);
  return events;
}

function makeMockRuntime(id: string, events: EngineEvent[]): RuntimeAdapter {
  return {
    id: id as any,
    capabilities: new Set(['streaming_text']),
    async *invoke() {
      for (const ev of events) yield ev;
    },
  };
}

describe('Routing runtime adapter', () => {
  it('routes Ollama model to Ollama adapter', async () => {
    const claude = makeMockRuntime('claude_code', [
      { type: 'text_delta', text: 'claude response' },
      { type: 'done' },
    ]);
    const ollama = makeMockRuntime('ollama', [
      { type: 'text_delta', text: 'ollama response' },
      { type: 'done' },
    ]);
    const modelNames = new Set(['llama3.2:latest', 'mistral:latest']);
    const router = createRoutingRuntime(claude, ollama, modelNames);

    const events = await collect(
      router.invoke({ prompt: 'Hi', model: 'llama3.2:latest', cwd: '/tmp' }),
    );

    expect(events).toEqual([
      { type: 'text_delta', text: 'ollama response' },
      { type: 'done' },
    ]);
  });

  it('routes Claude model to Claude adapter', async () => {
    const claude = makeMockRuntime('claude_code', [
      { type: 'text_delta', text: 'claude response' },
      { type: 'done' },
    ]);
    const ollama = makeMockRuntime('ollama', [
      { type: 'text_delta', text: 'ollama response' },
      { type: 'done' },
    ]);
    const modelNames = new Set(['llama3.2:latest']);
    const router = createRoutingRuntime(claude, ollama, modelNames);

    const events = await collect(
      router.invoke({ prompt: 'Hi', model: 'opus', cwd: '/tmp' }),
    );

    expect(events).toEqual([
      { type: 'text_delta', text: 'claude response' },
      { type: 'done' },
    ]);
  });

  it('falls back to Claude for unknown model names', async () => {
    const claude = makeMockRuntime('claude_code', [
      { type: 'text_delta', text: 'fallback' },
      { type: 'done' },
    ]);
    const ollama = makeMockRuntime('ollama', [
      { type: 'text_delta', text: 'nope' },
      { type: 'done' },
    ]);
    const modelNames = new Set(['llama3.2:latest']);
    const router = createRoutingRuntime(claude, ollama, modelNames);

    const events = await collect(
      router.invoke({ prompt: 'Hi', model: 'unknown-model', cwd: '/tmp' }),
    );

    expect(events[0]).toEqual({ type: 'text_delta', text: 'fallback' });
  });

  it('works with null Ollama adapter (disabled)', async () => {
    const claude = makeMockRuntime('claude_code', [
      { type: 'text_delta', text: 'only claude' },
      { type: 'done' },
    ]);
    const modelNames = new Set<string>();
    const router = createRoutingRuntime(claude, null, modelNames);

    const events = await collect(
      router.invoke({ prompt: 'Hi', model: 'llama3.2:latest', cwd: '/tmp' }),
    );

    expect(events[0]).toEqual({ type: 'text_delta', text: 'only claude' });
  });

  it('responds to dynamically added model names', async () => {
    const claude = makeMockRuntime('claude_code', [
      { type: 'text_delta', text: 'claude' },
      { type: 'done' },
    ]);
    const ollama = makeMockRuntime('ollama', [
      { type: 'text_delta', text: 'ollama' },
      { type: 'done' },
    ]);
    const modelNames = new Set<string>();
    const router = createRoutingRuntime(claude, ollama, modelNames);

    // Initially routes to Claude
    let events = await collect(
      router.invoke({ prompt: 'Hi', model: 'phi3:latest', cwd: '/tmp' }),
    );
    expect(events[0]).toEqual({ type: 'text_delta', text: 'claude' });

    // After adding model name, routes to Ollama
    modelNames.add('phi3:latest');
    events = await collect(
      router.invoke({ prompt: 'Hi', model: 'phi3:latest', cwd: '/tmp' }),
    );
    expect(events[0]).toEqual({ type: 'text_delta', text: 'ollama' });
  });

  it('has union of capabilities from both adapters', () => {
    const claude: RuntimeAdapter = {
      id: 'claude_code',
      capabilities: new Set(['streaming_text', 'sessions', 'tools_exec']),
      async *invoke() {},
    };
    const ollama: RuntimeAdapter = {
      id: 'ollama',
      capabilities: new Set(['streaming_text']),
      async *invoke() {},
    };
    const router = createRoutingRuntime(claude, ollama, new Set());

    expect(router.capabilities.has('streaming_text')).toBe(true);
    expect(router.capabilities.has('sessions')).toBe(true);
    expect(router.capabilities.has('tools_exec')).toBe(true);
  });
});
