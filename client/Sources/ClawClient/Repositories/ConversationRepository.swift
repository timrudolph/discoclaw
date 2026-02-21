import Combine
import Foundation
import GRDB

public final class ConversationRepository {
    private let db: AppDatabase

    public init(db: AppDatabase) {
        self.db = db
    }

    // MARK: - Reads

    public func fetchAll(includeArchived: Bool = false) async throws -> [Conversation] {
        try await db.read { db in
            var request = Conversation.order(Conversation.Columns.updatedAt.desc)
            if !includeArchived {
                request = request.filter(Conversation.Columns.archivedAt == nil)
            }
            return try request.fetchAll(db)
        }
    }

    public func fetch(id: String) async throws -> Conversation? {
        try await db.read { db in
            try Conversation.fetchOne(db, key: id)
        }
    }

    public func firstProtected() async throws -> Conversation? {
        try await db.read { db in
            try Conversation
                .filter(Column("isProtected") == true)
                .fetchOne(db)
        }
    }

    // MARK: - Writes

    public func save(_ conversation: Conversation) async throws {
        try await db.write { db in
            try conversation.save(db)
        }
    }

    /// Bulk upsert — used by the delta sync engine.
    public func saveAll(_ conversations: [Conversation]) async throws {
        try await db.write { db in
            for conversation in conversations {
                try conversation.save(db)
            }
        }
    }

    /// Full replace — upserts server records and deletes anything not on the server.
    /// Used on app launch to make the client exactly match the server.
    public func replaceAll(_ conversations: [Conversation]) async throws {
        try await db.write { db in
            if conversations.isEmpty {
                try Conversation.deleteAll(db)
            } else {
                let ids = conversations.map { $0.id }
                let placeholders = ids.map { _ in "?" }.joined(separator: ",")
                try db.execute(
                    sql: "DELETE FROM conversations WHERE id NOT IN (\(placeholders))",
                    arguments: StatementArguments(ids)
                )
                for conversation in conversations {
                    try conversation.save(db)
                }
            }
        }
    }

    public func delete(id: String) async throws {
        _ = try await db.write { db in
            try Conversation.deleteOne(db, key: id)
        }
    }

    // MARK: - Observations

    /// Emits the single conversation whenever its row changes.
    /// Emits `nil` if the conversation is deleted.
    public func observe(id: String) -> AnyPublisher<Conversation?, Never> {
        ValueObservation
            .tracking { db in try Conversation.fetchOne(db, key: id) }
            .publisher(in: db.writer, scheduling: .immediate)
            .catch { _ in Just(nil) }
            .eraseToAnyPublisher()
    }

    /// Emits the full sorted list whenever any conversation changes.
    /// Schedule on `.immediate` so the first value arrives synchronously
    /// (no blank state flash in SwiftUI).
    public func observeAll(includeArchived: Bool = false) -> AnyPublisher<[Conversation], Error> {
        ValueObservation
            .tracking { db -> [Conversation] in
                var request = Conversation.order(Conversation.Columns.updatedAt.desc)
                if !includeArchived {
                    request = request.filter(Conversation.Columns.archivedAt == nil)
                }
                return try request.fetchAll(db)
            }
            .publisher(in: db.writer, scheduling: .immediate)
            .eraseToAnyPublisher()
    }
}
