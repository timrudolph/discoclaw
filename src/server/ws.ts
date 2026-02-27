import type { WebSocket } from '@fastify/websocket';

// ─── Event types sent to clients ─────────────────────────────────────────────

export type WsEvent =
  | { type: 'message.delta'; messageId: string; conversationId: string; delta: string; seq: number }
  | { type: 'message.complete'; messageId: string; conversationId: string; content: string; seq: number; sourceConversationId?: string }
  | { type: 'message.error'; messageId: string; conversationId: string; error: string }
  | { type: 'tool.start'; messageId: string; tool: string; label: string }
  | { type: 'tool.end'; messageId: string; tool: string }
  | { type: 'conversation.updated'; conversationId: string }
  | { type: 'beads.updated' };

// ─── Hub ─────────────────────────────────────────────────────────────────────

/**
 * Tracks open WebSocket connections per user and broadcasts events to them.
 * Each user can have multiple connections (e.g. iPhone + Mac simultaneously).
 */
export class WsHub {
  private readonly connections = new Map<string, Set<WebSocket>>();

  register(userId: string, ws: WebSocket): () => void {
    let conns = this.connections.get(userId);
    if (!conns) {
      conns = new Set();
      this.connections.set(userId, conns);
    }
    conns.add(ws);

    return () => {
      conns!.delete(ws);
      if (conns!.size === 0) this.connections.delete(userId);
    };
  }

  broadcast(userId: string, event: WsEvent): void {
    const conns = this.connections.get(userId);
    if (!conns?.size) return;
    const payload = JSON.stringify(event);
    for (const ws of conns) {
      if (ws.readyState === ws.OPEN) {
        ws.send(payload);
      }
    }
  }

  connectionCount(userId?: string): number {
    if (userId) return this.connections.get(userId)?.size ?? 0;
    let total = 0;
    for (const s of this.connections.values()) total += s.size;
    return total;
  }
}
