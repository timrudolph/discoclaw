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

    /// Bulk upsert — used by the delta sync engine.
    public func saveAll(_ messages: [Message]) async throws {
        try await db.write { db in
            for message in messages {
                try message.save(db)
            }
        }
    }

    /// Full replace — upserts server records and deletes anything not on the server.
    /// Used on app launch to make the client exactly match the server.
    public func replaceAll(_ messages: [Message]) async throws {
        try await db.write { db in
            if messages.isEmpty {
                try Message.deleteAll(db)
            } else {
                let ids = messages.map { $0.id }
                let placeholders = ids.map { _ in "?" }.joined(separator: ",")
                try db.execute(
                    sql: "DELETE FROM messages WHERE id NOT IN (\(placeholders))",
                    arguments: StatementArguments(ids)
                )
                for message in messages {
                    try message.save(db)
                }
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

    /// Upsert an error state for an assistant message.
    /// If the row doesn't exist yet (WS event arrived before the client saved the placeholder),
    /// it is created with status=error. If it already exists, only status and error are updated.
    public func setError(id: String, conversationId: String, error: String) async throws {
        let now = Date()
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT INTO messages (id, conversationId, role, content, status, error, seq, createdAt)
                    VALUES (?, ?, 'assistant', '', 'error', ?, 0, ?)
                    ON CONFLICT(id) DO UPDATE SET status = 'error', error = excluded.error
                    """,
                arguments: [id, conversationId, error, now]
            )
        }
    }

    /// INSERT OR IGNORE — saves the message only if no row with the same id exists.
    /// Used for assistant placeholders so they don't overwrite an error state already
    /// established by an earlier WebSocket event.
    public func saveIfAbsent(_ message: Message) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO messages
                        (id, clientId, conversationId, role, content, status, error, seq, createdAt, completedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    message.id, message.clientId, message.conversationId,
                    message.role.rawValue, message.content, message.status.rawValue,
                    message.error, message.seq, message.createdAt, message.completedAt,
                ]
            )
        }
    }

    /// Called on `message.complete` — overwrites content with the authoritative final value.
    /// Safer than trusting all deltas arrived in order (handles any missed chunks).
    /// Guards against overwriting an error state: the runtime always emits done after error,
    /// so a message.complete can arrive after message.error on the same turn.
    public func finalize(id: String, content: String, completedAt: Date) async throws {
        try await db.write { db in
            try db.execute(
                sql: """
                    UPDATE messages
                       SET content = ?, status = 'complete', completedAt = ?
                     WHERE id = ? AND status != 'error'
                    """,
                arguments: [content, completedAt, id]
            )
        }
    }

    public func delete(id: String) async throws {
        try await db.write { db in
            try Message.deleteOne(db, key: id)
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

    /// Emits a dictionary of conversationId → latest complete Message whenever any
    /// message changes. Used to populate last-message previews in the conversation list.
    public func observeLastMessages() -> AnyPublisher<[String: Message], Never> {
        ValueObservation
            .tracking { db -> [String: Message] in
                // One row per conversation: the highest-seq complete message.
                let messages = try SQLRequest<Message>(sql: """
                    SELECT * FROM messages
                    WHERE seq IN (
                        SELECT MAX(seq) FROM messages
                        WHERE status = 'complete'
                        GROUP BY conversationId
                    )
                """).fetchAll(db)
                return Dictionary(messages.map { ($0.conversationId, $0) },
                                  uniquingKeysWith: { first, _ in first })
            }
            .publisher(in: db.writer, scheduling: .async(onQueue: .main))
            .catch { _ in Just([:]) }
            .eraseToAnyPublisher()
    }

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
            .publisher(in: db.writer, scheduling: .async(onQueue: .main))
            .eraseToAnyPublisher()
    }
}
