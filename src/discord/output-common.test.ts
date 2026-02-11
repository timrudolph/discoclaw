import { describe, expect, it, vi } from 'vitest';
import {
  buildAttachments,
  imageMediaTypeToExtension,
  editThenSendChunks,
  replyThenSendChunks,
  sendChunks,
} from './output-common.js';
import type { ImageData } from '../runtime/types.js';

describe('imageMediaTypeToExtension', () => {
  it('maps known types', () => {
    expect(imageMediaTypeToExtension('image/png')).toBe('png');
    expect(imageMediaTypeToExtension('image/jpeg')).toBe('jpeg');
    expect(imageMediaTypeToExtension('image/webp')).toBe('webp');
    expect(imageMediaTypeToExtension('image/gif')).toBe('gif');
  });

  it('defaults to png for unknown', () => {
    expect(imageMediaTypeToExtension('image/bmp')).toBe('png');
  });
});

describe('buildAttachments', () => {
  it('creates correct filenames and buffers', () => {
    const images: ImageData[] = [
      { base64: Buffer.from('png-data').toString('base64'), mediaType: 'image/png' },
      { base64: Buffer.from('jpeg-data').toString('base64'), mediaType: 'image/jpeg' },
    ];
    const attachments = buildAttachments(images);
    expect(attachments).toHaveLength(2);
    expect(attachments[0].name).toBe('image-1.png');
    expect(attachments[1].name).toBe('image-2.jpeg');
  });

  it('returns empty array for empty input', () => {
    expect(buildAttachments([])).toHaveLength(0);
  });
});

describe('editThenSendChunks with images', () => {
  function mockReply() {
    return { edit: vi.fn().mockResolvedValue(undefined) };
  }
  function mockChannel() {
    return { send: vi.fn().mockResolvedValue(undefined) };
  }

  it('sends text-only with no images', async () => {
    const reply = mockReply();
    const channel = mockChannel();
    await editThenSendChunks(reply, channel, 'hello');
    expect(reply.edit).toHaveBeenCalledOnce();
    expect(reply.edit.mock.calls[0][0].content).toBe('hello');
    expect(reply.edit.mock.calls[0][0].files).toBeUndefined();
  });

  it('sends image-only when text is empty', async () => {
    const reply = mockReply();
    const channel = mockChannel();
    const images: ImageData[] = [
      { base64: Buffer.from('test').toString('base64'), mediaType: 'image/png' },
    ];
    await editThenSendChunks(reply, channel, '', images);
    expect(reply.edit).toHaveBeenCalledOnce();
    expect(reply.edit.mock.calls[0][0].content).toBe('');
    expect(reply.edit.mock.calls[0][0].files).toHaveLength(1);
  });

  it('attaches images to single text chunk', async () => {
    const reply = mockReply();
    const channel = mockChannel();
    const images: ImageData[] = [
      { base64: Buffer.from('test').toString('base64'), mediaType: 'image/png' },
    ];
    await editThenSendChunks(reply, channel, 'Response text', images);
    expect(reply.edit).toHaveBeenCalled();
    // Single chunk: images in the edit call
    const editCall = reply.edit.mock.calls[reply.edit.mock.calls.length - 1][0];
    expect(editCall.files).toHaveLength(1);
  });

  it('shows (no output) when empty text and no images', async () => {
    const reply = mockReply();
    const channel = mockChannel();
    await editThenSendChunks(reply, channel, '');
    expect(reply.edit).toHaveBeenCalledOnce();
    expect(reply.edit.mock.calls[0][0].content).toBe('(no output)');
  });
});

describe('replyThenSendChunks with images', () => {
  function mockMessage() {
    return {
      reply: vi.fn().mockResolvedValue(undefined),
      channel: { send: vi.fn().mockResolvedValue(undefined) },
    };
  }

  it('sends image-only with empty text', async () => {
    const message = mockMessage();
    const images: ImageData[] = [
      { base64: Buffer.from('test').toString('base64'), mediaType: 'image/png' },
    ];
    await replyThenSendChunks(message, '', images);
    expect(message.reply).toHaveBeenCalledOnce();
    expect(message.reply.mock.calls[0][0].content).toBe('');
    expect(message.reply.mock.calls[0][0].files).toHaveLength(1);
  });

  it('shows (no output) when no text and no images', async () => {
    const message = mockMessage();
    await replyThenSendChunks(message, '');
    expect(message.reply).toHaveBeenCalledOnce();
    expect(message.reply.mock.calls[0][0].content).toBe('(no output)');
  });
});

describe('sendChunks with images', () => {
  function mockChannel() {
    return { send: vi.fn().mockResolvedValue(undefined) };
  }

  it('sends image-only with empty text', async () => {
    const channel = mockChannel();
    const images: ImageData[] = [
      { base64: Buffer.from('test').toString('base64'), mediaType: 'image/png' },
    ];
    await sendChunks(channel, '', images);
    expect(channel.send).toHaveBeenCalledOnce();
    expect(channel.send.mock.calls[0][0].content).toBe('');
    expect(channel.send.mock.calls[0][0].files).toHaveLength(1);
  });

  it('attaches images to last text chunk', async () => {
    const channel = mockChannel();
    const images: ImageData[] = [
      { base64: Buffer.from('test').toString('base64'), mediaType: 'image/png' },
    ];
    await sendChunks(channel, 'Hello world', images);
    expect(channel.send).toHaveBeenCalledOnce();
    expect(channel.send.mock.calls[0][0].files).toHaveLength(1);
  });
});
