import type { RuntimeAdapter, RuntimeCapability } from './types.js';

/**
 * Meta-adapter that delegates to Ollama or Claude based on the requested model name.
 * `ollamaModelNames` is mutable — refreshed when the /models endpoint is hit.
 */
export function createRoutingRuntime(
  claude: RuntimeAdapter,
  ollama: RuntimeAdapter | null,
  ollamaModelNames: Set<string>,
): RuntimeAdapter {
  // Union of both adapters' capabilities
  const capabilities: ReadonlySet<RuntimeCapability> = new Set([
    ...claude.capabilities,
    ...(ollama?.capabilities ?? []),
  ]);

  async function* invoke(
    params: Parameters<RuntimeAdapter['invoke']>[0],
  ): AsyncIterable<ReturnType<RuntimeAdapter['invoke']> extends AsyncIterable<infer E> ? E : never> {
    if (ollama && ollamaModelNames.has(params.model)) {
      yield* ollama.invoke(params);
    } else {
      yield* claude.invoke(params);
    }
  }

  return {
    id: 'claude_code', // primary runtime identity
    capabilities,
    invoke,
  };
}
