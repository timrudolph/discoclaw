import crypto from 'node:crypto';
import type { RuntimeAdapter } from '../runtime/types.js';
import type { Db, ConversationRow, MessageRow, MemoryItemRow } from './db.js';
import { nextSeq } from './db.js';
import type { WsHub } from './ws.js';
import type { ServerConfig } from './config.js';

/**
 * Detects rate-limit / overload errors and returns the epoch-ms timestamp
 * at which the client should be able to retry. Returns null for non-limit errors.
 */
function rateLimitRetryAt(errorMsg: string): number | null {
  const lower = errorMsg.toLowerCase();
  const isLimit =
    lower.includes('rate limit') ||
    lower.includes('429') ||
    lower.includes('too many requests') ||
    lower.includes('overloaded') ||
    lower.includes('usage limit') ||
    lower.includes('token limit');

  if (!isLimit) return null;

  // "in X seconds / minutes / hours"
  const m = errorMsg.match(/in\s+(\d+)\s+(second|minute|hour)/i);
  if (m) {
    const n = parseInt(m[1], 10);
    const unit = m[2].toLowerCase();
    const ms = unit.startsWith('hour') ? n * 3_600_000
              : unit.startsWith('minute') ? n * 60_000
              : n * 1_000;
    return Date.now() + ms;
  }

  // Default: assume 1 hour until we have better info
  return Date.now() + 3_600_000;
}

const TOOL_LABELS: Record<string, string> = {
  Bash: 'Running command…',
  Read: 'Reading file…',
  Write: 'Writing file…',
  Edit: 'Editing file…',
  Glob: 'Searching files…',
  Grep: 'Searching content…',
  WebSearch: 'Searching the web…',
  WebFetch: 'Fetching URL…',
};

function toolLabel(name: string): string {
  return TOOL_LABELS[name] ?? `Using ${name}…`;
}

const KIND_SYSTEM_PREFIX: Record<string, string> = {
  tasks: [
    'You are managing a persistent task list for this conversation.',
    'Always include the full current task list as a markdown checklist at the end of your response.',
    'When the user adds, completes, or removes tasks, update the list accordingly.',
    'Use [ ] for incomplete tasks and [x] for completed ones.',
  ].join(' '),
};

/** Build the prompt for a new turn, injecting recent conversation history and memory. */
function buildPrompt(
  history: MessageRow[],
  userContent: string,
  kind: string | null,
  memoryItems: MemoryItemRow[],
): string {
  const MAX_HISTORY = 20;
  const recent = history.slice(-MAX_HISTORY);

  const systemPrefix = kind && KIND_SYSTEM_PREFIX[kind]
    ? `${KIND_SYSTEM_PREFIX[kind]}\n\n---\n\n`
    : '';

  const memoryBlock = memoryItems.length > 0
    ? `Durable memory (${memoryItems.length} item${memoryItems.length === 1 ? '' : 's'}):\n${
        memoryItems.map((m) => `- ${m.content}`).join('\n')
      }\n\n---\n\n`
    : '';

  if (recent.length === 0) return systemPrefix + memoryBlock + userContent;

  const lines = recent
    .filter((m) => m.status === 'complete' && m.content.trim())
    .map((m) => `[${m.role === 'user' ? 'User' : 'Assistant'}]: ${m.content.trim()}`)
    .join('\n\n');

  const historyBlock = lines ? `Recent conversation:\n\n${lines}\n\n---\n\n` : '';
  return systemPrefix + memoryBlock + historyBlock + userContent;
}

export type InvokeOptions = {
  db: Db;
  hub: WsHub;
  runtime: RuntimeAdapter;
  config: ServerConfig;
  conversation: ConversationRow;
  userMessageContent: string;
};

/**
 * Creates the pending assistant message row, invokes the Claude runtime,
 * and streams EngineEvents to both the database and connected WebSocket clients.
 * Returns the assistant message id.
 */
export async function invokeRuntime(opts: InvokeOptions): Promise<string> {
  const { db, hub, runtime, config, conversation } = opts;

  // Load recent history for prompt context
  const history = db
    .prepare(
      'SELECT * FROM messages WHERE conversation_id = ? ORDER BY seq ASC LIMIT 40',
    )
    .all(conversation.id) as MessageRow[];

  // Load active memory items for this user
  const memoryItems = db
    .prepare('SELECT * FROM memory_items WHERE user_id = ? AND deprecated_at IS NULL ORDER BY created_at ASC')
    .all(conversation.user_id) as MemoryItemRow[];

  const prompt = buildPrompt(history, opts.userMessageContent, conversation.kind, memoryItems);
  const assistantId = crypto.randomUUID();
  const assistantSeq = nextSeq();
  const now = Date.now();

  // Reuse the conversation's Claude session ID for continuity across turns.
  // Generate and persist a new one on the first message of each conversation.
  const sessionId = conversation.claude_session_id ?? crypto.randomUUID();
  if (!conversation.claude_session_id) {
    db.prepare('UPDATE conversations SET claude_session_id = ? WHERE id = ?')
      .run(sessionId, conversation.id);
  }

  // Create the assistant message row immediately (status=pending)
  db.prepare(`
    INSERT INTO messages (id, conversation_id, role, content, status, seq, created_at)
    VALUES (?, ?, 'assistant', '', 'pending', ?, ?)
  `).run(assistantId, conversation.id, assistantSeq, now);

  // Fire-and-forget: stream in background so the POST /messages response is instant
  streamInBackground({
    db, hub, runtime, config, conversation,
    assistantId, assistantSeq, prompt, sessionId,
  });

  return assistantId;
}

type StreamParams = {
  db: Db;
  hub: WsHub;
  runtime: RuntimeAdapter;
  config: ServerConfig;
  conversation: ConversationRow;
  assistantId: string;
  assistantSeq: number;
  prompt: string;
  sessionId: string;
};

function streamInBackground(params: StreamParams): void {
  void (async () => {
    const { db, hub, runtime, config, conversation, assistantId, assistantSeq, prompt, sessionId } = params;
    const userId = conversation.user_id;
    let fullContent = '';

    // Mark streaming
    db.prepare("UPDATE messages SET status = 'streaming' WHERE id = ?").run(assistantId);

    try {
      const events = runtime.invoke({
        prompt,
        model: config.runtimeModel,
        cwd: config.workspaceCwd,
        sessionId,
        tools: config.runtimeTools,
        timeoutMs: config.runtimeTimeoutMs,
      });

      for await (const event of events) {
        switch (event.type) {
          case 'text_delta':
            fullContent += event.text;
            db.prepare(
              'UPDATE messages SET content = content || ? WHERE id = ?',
            ).run(event.text, assistantId);
            hub.broadcast(userId, {
              type: 'message.delta',
              messageId: assistantId,
              conversationId: conversation.id,
              delta: event.text,
              seq: assistantSeq,
            });
            break;

          case 'tool_start':
            hub.broadcast(userId, {
              type: 'tool.start',
              messageId: assistantId,
              tool: event.name,
              label: toolLabel(event.name),
            });
            break;

          case 'tool_end':
            hub.broadcast(userId, {
              type: 'tool.end',
              messageId: assistantId,
              tool: event.name,
            });
            break;

          case 'done': {
            const completedAt = Date.now();
            db.prepare(`
              UPDATE messages SET status = 'complete', completed_at = ? WHERE id = ?
            `).run(completedAt, assistantId);
            db.prepare(
              'UPDATE conversations SET updated_at = ? WHERE id = ?',
            ).run(completedAt, conversation.id);
            hub.broadcast(userId, {
              type: 'message.complete',
              messageId: assistantId,
              conversationId: conversation.id,
              content: fullContent,
              seq: assistantSeq,
            });
            break;
          }

          case 'error': {
            const retryAt = rateLimitRetryAt(event.message);
            const storedError = retryAt ? `rate_limit:${retryAt}` : event.message;
            db.prepare(`
              UPDATE messages SET status = 'error', error = ? WHERE id = ?
            `).run(storedError, assistantId);
            hub.broadcast(userId, {
              type: 'message.error',
              messageId: assistantId,
              conversationId: conversation.id,
              error: storedError,
            });
            break;
          }
        }
      }
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      db.prepare(`
        UPDATE messages SET status = 'error', error = ? WHERE id = ?
      `).run(msg, assistantId);
      hub.broadcast(userId, {
        type: 'message.error',
        messageId: assistantId,
        conversationId: conversation.id,
        error: msg,
      });
    }
  })();
}
