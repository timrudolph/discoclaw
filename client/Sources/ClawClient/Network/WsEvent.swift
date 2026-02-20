import Foundation

/// Events received from the server over WebSocket.
public enum WsEvent: Sendable {
    /// A streaming text chunk for an in-progress assistant message.
    case messageDelta(messageId: String, conversationId: String, delta: String, seq: Int)
    /// The assistant turn is complete. `content` is the authoritative full text.
    case messageComplete(messageId: String, conversationId: String, content: String, seq: Int)
    /// The assistant turn failed.
    case messageError(messageId: String, conversationId: String, error: String)
    /// A tool call started — drives a spinner in the UI.
    case toolStart(messageId: String, tool: String, label: String)
    /// A tool call finished.
    case toolEnd(messageId: String, tool: String)
    /// A conversation's metadata changed (title, archived) on another device.
    case conversationUpdated(conversationId: String)
}

extension WsEvent {
    /// Parse a raw JSON string from the WebSocket into a typed event.
    /// Returns nil for unknown event types or malformed payloads.
    static func parse(_ text: String) -> WsEvent? {
        guard
            let data = text.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = json["type"] as? String
        else { return nil }

        switch type {
        case "message.delta":
            guard
                let messageId = json["messageId"] as? String,
                let conversationId = json["conversationId"] as? String,
                let delta = json["delta"] as? String,
                let seq = json["seq"] as? Int
            else { return nil }
            return .messageDelta(messageId: messageId, conversationId: conversationId, delta: delta, seq: seq)

        case "message.complete":
            guard
                let messageId = json["messageId"] as? String,
                let conversationId = json["conversationId"] as? String,
                let content = json["content"] as? String,
                let seq = json["seq"] as? Int
            else { return nil }
            return .messageComplete(messageId: messageId, conversationId: conversationId, content: content, seq: seq)

        case "message.error":
            guard
                let messageId = json["messageId"] as? String,
                let conversationId = json["conversationId"] as? String,
                let error = json["error"] as? String
            else { return nil }
            return .messageError(messageId: messageId, conversationId: conversationId, error: error)

        case "tool.start":
            guard
                let messageId = json["messageId"] as? String,
                let tool = json["tool"] as? String,
                let label = json["label"] as? String
            else { return nil }
            return .toolStart(messageId: messageId, tool: tool, label: label)

        case "tool.end":
            guard
                let messageId = json["messageId"] as? String,
                let tool = json["tool"] as? String
            else { return nil }
            return .toolEnd(messageId: messageId, tool: tool)

        case "conversation.updated":
            guard let conversationId = json["conversationId"] as? String else { return nil }
            return .conversationUpdated(conversationId: conversationId)

        default:
            return nil
        }
    }
}
