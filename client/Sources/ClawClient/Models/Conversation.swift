import Foundation
import GRDB

public struct Conversation: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String?
    public var claudeSessionId: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var archivedAt: Date?
    public var isProtected: Bool
    public var kind: String?

    public var isArchived: Bool { archivedAt != nil }

    /// SF Symbol name for the conversation's kind, or nil for regular conversations.
    public var kindIcon: String? {
        switch kind {
        case "general": return "bubble.left.and.bubble.right.fill"
        case "tasks":   return "checklist"
        case "journal": return "book.closed.fill"
        default:        return nil
        }
    }

    public init(
        id: String,
        title: String? = nil,
        claudeSessionId: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        archivedAt: Date? = nil,
        isProtected: Bool = false,
        kind: String? = nil
    ) {
        self.id = id
        self.title = title
        self.claudeSessionId = claudeSessionId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.isProtected = isProtected
        self.kind = kind
    }
}

extension Conversation: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "conversations"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let title = Column(CodingKeys.title)
        public static let claudeSessionId = Column(CodingKeys.claudeSessionId)
        public static let updatedAt = Column(CodingKeys.updatedAt)
        public static let archivedAt = Column(CodingKeys.archivedAt)
    }

    public static let messages = hasMany(Message.self)

    public var messages: QueryInterfaceRequest<Message> {
        request(for: Conversation.messages)
    }
}
