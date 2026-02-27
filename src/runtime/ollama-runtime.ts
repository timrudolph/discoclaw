import type { RuntimeAdapter, EngineEvent, RuntimeCapability } from './types.js';

export interface OllamaRuntimeOpts {
  baseUrl: string;
  defaultModel: string;
  imageModels: string[];
}

/**
 * Ollama runtime adapter. Two code paths:
 * - Text LLMs via POST /api/chat (streaming NDJSON)
 * - Image generation via POST /api/generate (non-streaming)
 */
export function createOllamaRuntime(opts: OllamaRuntimeOpts): RuntimeAdapter {
  const capabilities: ReadonlySet<RuntimeCapability> = new Set(['streaming_text']);

  function isImageModel(model: string): boolean {
    return opts.imageModels.some((prefix) => model.startsWith(prefix));
  }

  async function* invoke(
    params: Parameters<RuntimeAdapter['invoke']>[0],
  ): AsyncIterable<EngineEvent> {
    const model = params.model || opts.defaultModel;

    try {
      if (isImageModel(model)) {
        yield* invokeImageGen(model, params.prompt);
      } else {
        yield* invokeTextChat(model, params);
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      if (msg.includes('ECONNREFUSED') || msg.includes('fetch failed')) {
        yield { type: 'text_delta', text: '⚠️ Ollama is not running. Start it with: `ollama serve`' };
      } else {
        yield { type: 'error', message: msg };
      }
      yield { type: 'done' };
    }
  }

  async function* invokeTextChat(
    model: string,
    params: Parameters<RuntimeAdapter['invoke']>[0],
  ): AsyncIterable<EngineEvent> {
    const messages: Array<{ role: string; content: string; images?: string[] }> = [
      { role: 'user', content: params.prompt },
    ];

    // Attach base64 images for vision models (e.g. llava)
    if (params.images?.length) {
      messages[0].images = params.images.map((img) => img.base64);
    }

    const resp = await fetch(`${opts.baseUrl}/api/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, messages, stream: true }),
    });

    if (!resp.ok) {
      const body = await resp.text();
      if (resp.status === 404) {
        yield { type: 'text_delta', text: `⚠️ Model "${model}" not found. Pull it with: \`ollama pull ${model}\`` };
        yield { type: 'done' };
        return;
      }
      yield { type: 'error', message: `Ollama API error ${resp.status}: ${body}` };
      yield { type: 'done' };
      return;
    }

    const reader = resp.body?.getReader();
    if (!reader) {
      yield { type: 'error', message: 'No response body from Ollama' };
      yield { type: 'done' };
      return;
    }

    const decoder = new TextDecoder();
    let buffer = '';

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        // Keep incomplete last line in the buffer
        buffer = lines.pop() ?? '';

        for (const line of lines) {
          const trimmed = line.trim();
          if (!trimmed) continue;

          let chunk: OllamaChatChunk;
          try {
            chunk = JSON.parse(trimmed);
          } catch {
            continue; // skip malformed lines
          }

          if (chunk.message?.content) {
            yield { type: 'text_delta', text: chunk.message.content };
          }

          if (chunk.done) {
            yield {
              type: 'usage',
              inputTokens: chunk.prompt_eval_count,
              outputTokens: chunk.eval_count,
            };
          }
        }
      }

      // Process any remaining buffer
      if (buffer.trim()) {
        try {
          const chunk: OllamaChatChunk = JSON.parse(buffer.trim());
          if (chunk.message?.content) {
            yield { type: 'text_delta', text: chunk.message.content };
          }
          if (chunk.done) {
            yield {
              type: 'usage',
              inputTokens: chunk.prompt_eval_count,
              outputTokens: chunk.eval_count,
            };
          }
        } catch { /* ignore trailing garbage */ }
      }
    } finally {
      reader.releaseLock();
    }

    yield { type: 'done' };
  }

  async function* invokeImageGen(
    model: string,
    prompt: string,
  ): AsyncIterable<EngineEvent> {
    const resp = await fetch(`${opts.baseUrl}/api/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ model, prompt, stream: false }),
    });

    if (!resp.ok) {
      const body = await resp.text();
      if (resp.status === 404) {
        yield { type: 'text_delta', text: `⚠️ Image model "${model}" not found. Pull it with: \`ollama pull ${model}\`` };
        yield { type: 'done' };
        return;
      }
      yield { type: 'error', message: `Ollama API error ${resp.status}: ${body}` };
      yield { type: 'done' };
      return;
    }

    const data = (await resp.json()) as OllamaGenerateResponse;

    if (data.images?.[0]) {
      yield { type: 'image_data', image: { mediaType: 'image/png', base64: data.images[0] } };
    } else if ((data as any).image) {
      // Some Ollama versions return a single `image` field
      yield { type: 'image_data', image: { mediaType: 'image/png', base64: (data as any).image } };
    } else {
      // Model returned text instead of an image
      if (data.response) {
        yield { type: 'text_delta', text: data.response };
      } else {
        yield { type: 'text_delta', text: '⚠️ No image was generated. The model may not support image generation.' };
      }
    }

    yield { type: 'done' };
  }

  return { id: 'ollama', capabilities, invoke };
}

// ─── Ollama API types ──────────────────────────────────────────────────────────

type OllamaChatChunk = {
  model?: string;
  created_at?: string;
  message?: { role: string; content: string };
  done: boolean;
  total_duration?: number;
  eval_count?: number;
  prompt_eval_count?: number;
};

type OllamaGenerateResponse = {
  model?: string;
  response?: string;
  images?: string[];
  done?: boolean;
};
