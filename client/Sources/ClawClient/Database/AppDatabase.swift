import Foundation
import GRDB

/// The shared database. Holds the GRDB writer (DatabasePool in production,
/// DatabaseQueue for in-memory tests). All reads and writes go through here.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try migrator.migrate(writer)
    }

    // MARK: - Factory

    public static func makeShared() throws -> AppDatabase {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("ClawClient")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("db.sqlite").path
        let pool = try DatabasePool(path: dbPath)
        return try AppDatabase(pool)
    }

    public static func makeInMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    // MARK: - Async convenience wrappers

    public func read<T: Sendable>(
        _ block: @Sendable @escaping (Database) throws -> T
    ) async throws -> T {
        try await writer.read(block)
    }

    public func write<T: Sendable>(
        _ block: @Sendable @escaping (Database) throws -> T
    ) async throws -> T {
        try await writer.write(block)
    }
}
