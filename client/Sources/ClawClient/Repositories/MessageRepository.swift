import Combine
import Foundation
import GRDB

public final class MessageRepository {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Reads

    /// Fetch messages for a conversation, oldest-first, with optional cursor pagination.
    /// Pass `before:` to load earlier messages (for infinite scroll upward).
    public func fetchMessages(
        conversationId: String,
        limit: Int = 50,
        before seq: Int? = nil
    ) async throws -> [Message] {
        try await db.read { db in
            var request = Message
                .filter(Message.Columns.conversationId == conversationId)
                .order(Message.Columns.seq.asc)
                .limit(limit)
            if let seq {
                request = request.filter(Message.Columns.seq < seq)
            }
            return try request.fetchAll(db)
        }
    }

    public func fetch(id: String) async throws -> Message? {
        try await db.read { db in
            try Message.fetchOne(db, key: id)
        }
    }

    /// Look up an optimistic message by the temp ID the client assigned before
    /// the server responded.
    public func findByClientId(_ clientId: String) async throws -> Message? {
        try await db.read { db in
            try Message.filter(Message.Columns.clientId == clientId).fetchOne(db)
        }
    }

    // MARK: - Writes

    public func save(_ message: Message) async throws {
        try await db.write { db in
            try message.save(db)
        }
    }

    /// Bulk upsert — used by the sync engine on app launch.
    public func saveAll(_ messages: [Message]) async throws {
        try await db.write { db in
            for message in messages {
                try message.save(db)
            }
        }
    }

    /// Append a streaming delta from the WebSocket to the assistant message's content.
    /// Uses a single SQL UPDATE to avoid a read-modify-write race.
    public func appendDelta(id: String, delta: String) async throws {
        try await db.write { db in
            try db.execute(
                sql: "UPDATE messages SET content = content || ? WHERE id = ?",
                arguments: [delta, id]
            )
        }
    }

    /// Update message status as a turn progresses: pending → streaming → complete | error.
    public func updateStatus(
        id: String,
        status: Message.Status,
        error: String? = nil,
        completedAt: Date? = nil
    ) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE messages
                       SET status = ?, error = ?, completedAt = ?
                     WHERE id = ?
                    """,
                arguments: [status.rawValue, error, completedAt, id]
            )
        }
    }

    /// Called on `message.complete` — overwrites content with the authoritative final value.
    /// Safer than trusting all deltas arrived in order (handles any missed chunks).
    public func finalize(id: String, content: String, completedAt: Date) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE messages
                       SET content = ?, status = 'complete', completedAt = ?
                     WHERE id = ?
                    """,
                arguments: [content, completedAt, id]
            )
        }
    }

    /// Called when the server responds to a POST /messages with { id, seq }.
    /// Promotes the optimistic (client-temp-id) row to the server-assigned id and seq.
    public func confirmOptimistic(clientId: String, serverId: String, seq: Int) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE messages
                       SET id = ?, seq = ?, status = 'streaming'
                     WHERE clientId = ?
                    """,
                arguments: [serverId, seq, clientId]
            )
        }
    }

    // MARK: - Observations

    /// Emits the full message list for a conversation whenever any message in it changes.
    /// Used by the chat view to reactively update as streaming deltas arrive.
    public func observeMessages(conversationId: String) -> AnyPublisher<[Message], Error> {
        ValueObservation
            .tracking { db in
                try Message
                    .filter(Message.Columns.conversationId == conversationId)
                    .order(Message.Columns.seq.asc)
                    .fetchAll(db)
            }
            .publisher(in: db.writer, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}
