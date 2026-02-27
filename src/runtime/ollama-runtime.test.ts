import { afterEach, describe, expect, it, vi } from 'vitest';
import { createOllamaRuntime } from './ollama-runtime.js';
import type { EngineEvent } from './types.js';

async function collect(iter: AsyncIterable<EngineEvent>): Promise<EngineEvent[]> {
  const events: EngineEvent[] = [];
  for await (const ev of iter) events.push(ev);
  return events;
}

// Helper: create a streaming response from NDJSON lines
function ndjsonResponse(lines: object[], status = 200): Response {
  const body = lines.map((l) => JSON.stringify(l) + '\n').join('');
  return new Response(body, {
    status,
    headers: { 'Content-Type': 'application/x-ndjson' },
  });
}

function jsonResponse(data: object, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

const DEFAULT_OPTS = {
  baseUrl: 'http://localhost:11434',
  defaultModel: 'llama3.2',
  imageModels: ['x/z-image-turbo', 'x/flux2-klein'],
};

describe('Ollama runtime adapter', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('text chat (POST /api/chat)', () => {
    it('streams text deltas from NDJSON response', async () => {
      vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
        ndjsonResponse([
          { model: 'llama3.2', message: { role: 'assistant', content: 'Hello' }, done: false },
          { model: 'llama3.2', message: { role: 'assistant', content: ' world!' }, done: false },
          { model: 'llama3.2', message: { role: 'assistant', content: '' }, done: true, eval_count: 10, prompt_eval_count: 5 },
        ]),
      );

      const rt = createOllamaRuntime(DEFAULT_OPTS);
      const events = await collect(rt.invoke({ prompt: 'Hi', model: 'llama3.2', cwd: '/tmp' }));

      expect(events).toEqual([
        { type: 'text_delta', text: 'Hello' },
        { type: 'text_delta', text: ' world!' },
        { type: 'usage', inputTokens: 5, outputTokens: 10 },
        { type: 'done' },
      ]);
    });

    it('uses default model when model param is empty', async () => {
      const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
        ndjsonResponse([
          { message: { role: 'assistant', content: 'ok' }, done: true, eval_count: 1, prompt_eval_count: 1 },
        ]),
      );

      const rt = createOllamaRuntime(DEFAULT_OPTS);
      await collect(rt.invoke({ prompt: 'Hi', model: '', cwd: '/tmp' }));

      expect(fetchSpy).toHaveBeenCalledWith(
        'http://localhost:11434/api/chat',
        expect.objectContaining({
          body: expect.stringContaining('"model":"llama3.2"'),
        }),
      );
    });

    it('handles 404 (model not found) gracefully', async () => {
      vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
        new Response('model not found', { status: 404 }),
      );

      const rt = createOllamaRuntime(DEFAULT_OPTS);
      const events = await collect(rt.invoke({ prompt: 'Hi', model: 'nonexistent', cwd: '/tmp' }));

      expect(events[0]).toEqual(expect.objectContaining({ type: 'text_delta' }));
      expect((events[0] as any).text).toContain('not found');
      expect(events[events.length - 1]).toEqual({ type: 'done' });
    });

    it('handles connection refused gracefully', async () => {
      vi.spyOn(globalThis, 'fetch').mockRejectedValueOnce(
        new TypeError('fetch failed: ECONNREFUSED'),
      );

      const rt = createOllamaRuntime(DEFAULT_OPTS);
      const events = await collect(rt.invoke({ prompt: 'Hi', model: 'llama3.2', cwd: '/tmp' }));

      expect(events[0]).toEqual(expect.objectContaining({ type: 'text_delta' }));
      expect((events[0] as any).text).toContain('Ollama is not running');
      expect(events[events.length - 1]).toEqual({ type: 'done' });
    });

    it('includes images for vision models', async () => {
      const fetchSpy = vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
        ndjsonResponse([
          { message: { role: 'assistant', content: 'I see a cat' }, done: true, eval_count: 4, prompt_eval_count: 10 },
        ]),
      );

      const rt = createOllamaRuntime(DEFAULT_OPTS);
      await collect(
        rt.invoke({
          prompt: 'What is this?',
          model: 'llava',
          cwd: '/tmp',
          images: [{ base64: 'abc123', mediaType: 'image/png' }],
        }),
      );

      const body = JSON.parse(fetchSpy.mock.calls[0][1]!.body as string);
      expect(body.messages[0].images).toEqual(['abc123']);
    });
  });

  describe('image generation (POST /api/generate)', () => {
    it('emits image_data for image model with images[] response', async () => {
      vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
        jsonResponse({ model: 'x/z-image-turbo', images: ['base64imagedata'], done: true }),
      );

      const rt = createOllamaRuntime(DEFAULT_OPTS);
      const events = await collect(
        rt.invoke({ prompt: 'a cat in space', model: 'x/z-image-turbo', cwd: '/tmp' }),
      );

      expect(events).toEqual([
        { type: 'image_data', image: { mediaType: 'image/png', base64: 'base64imagedata' } },
        { type: 'done' },
      ]);
    });

    it('emits image_data for image model with single image field', async () => {
      vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
        jsonResponse({ model: 'x/flux2-klein:4b', image: 'singleimage', done: true }),
      );

      const rt = createOllamaRuntime(DEFAULT_OPTS);
      const events = await collect(
        rt.invoke({ prompt: 'landscape', model: 'x/flux2-klein:4b', cwd: '/tmp' }),
      );

      expect(events).toEqual([
        { type: 'image_data', image: { mediaType: 'image/png', base64: 'singleimage' } },
        { type: 'done' },
      ]);
    });

    it('falls back to text if no image in response', async () => {
      vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
        jsonResponse({ model: 'x/z-image-turbo', response: 'I cannot generate images', done: true }),
      );

      const rt = createOllamaRuntime(DEFAULT_OPTS);
      const events = await collect(
        rt.invoke({ prompt: 'a cat', model: 'x/z-image-turbo', cwd: '/tmp' }),
      );

      expect(events[0]).toEqual({ type: 'text_delta', text: 'I cannot generate images' });
      expect(events[events.length - 1]).toEqual({ type: 'done' });
    });

    it('handles 404 for missing image model', async () => {
      vi.spyOn(globalThis, 'fetch').mockResolvedValueOnce(
        new Response('model not found', { status: 404 }),
      );

      const rt = createOllamaRuntime(DEFAULT_OPTS);
      const events = await collect(
        rt.invoke({ prompt: 'test', model: 'x/z-image-turbo', cwd: '/tmp' }),
      );

      expect(events[0]).toEqual(expect.objectContaining({ type: 'text_delta' }));
      expect((events[0] as any).text).toContain('not found');
    });
  });
});
