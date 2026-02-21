import GRDB

extension AppDatabase {
    var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1_initial") { db in
            try db.create(table: "conversations") { t in
                t.primaryKey("id", .text)
                t.column("title", .text)
                t.column("claudeSessionId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("archivedAt", .datetime)
                t.column("isProtected", .boolean).notNull().defaults(to: false)
                t.column("kind", .text)
                t.column("modelOverride", .text)
            }

            try db.create(table: "messages") { t in
                t.primaryKey("id", .text)
                t.column("clientId", .text)
                t.column("conversationId", .text).notNull()
                    .references("conversations", onDelete: .cascade)
                t.column("role", .text).notNull()
                t.column("content", .text).notNull().defaults(to: "")
                t.column("status", .text).notNull()
                t.column("error", .text)
                t.column("seq", .integer).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("completedAt", .datetime)
            }

            try db.create(indexOn: "messages", columns: ["conversationId", "seq"])
            try db.create(indexOn: "messages", columns: ["seq"])
        }

        m.registerMigration("v2_conversation_persona") { db in
            try db.alter(table: "conversations") { t in
                t.add(column: "soul",     .text)
                t.add(column: "identity", .text)
                t.add(column: "userBio",  .text)
            }
        }

        return m
    }
}
