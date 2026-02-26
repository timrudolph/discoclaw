import Foundation
import GRDB

public struct Message: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var clientId: String?
    public var conversationId: String
    public var role: Role
    public var content: String
    public var status: Status
    public var error: String?
    public var seq: Int
    public var createdAt: Date
    public var completedAt: Date?
    /// Set when this message was cross-posted from another bot's conversation.
    public var sourceConversationId: String?

    public enum Role: String, Codable, Sendable {
        case user, assistant
    }

    public enum Status: String, Codable, Sendable {
        case pending, streaming, complete, error
    }

    public init(
        id: String,
        clientId: String? = nil,
        conversationId: String,
        role: Role,
        content: String,
        status: Status,
        error: String? = nil,
        seq: Int,
        createdAt: Date,
        completedAt: Date? = nil,
        sourceConversationId: String? = nil
    ) {
        self.id = id
        self.clientId = clientId
        self.conversationId = conversationId
        self.role = role
        self.content = content
        self.status = status
        self.error = error
        self.seq = seq
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.sourceConversationId = sourceConversationId
    }
}

extension Message: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "messages"

    public enum Columns {
        public static let id = Column(CodingKeys.id)
        public static let clientId = Column(CodingKeys.clientId)
        public static let conversationId = Column(CodingKeys.conversationId)
        public static let role = Column(CodingKeys.role)
        public static let content = Column(CodingKeys.content)
        public static let status = Column(CodingKeys.status)
        public static let error = Column(CodingKeys.error)
        public static let seq = Column(CodingKeys.seq)
        public static let createdAt = Column(CodingKeys.createdAt)
        public static let completedAt = Column(CodingKeys.completedAt)
        public static let sourceConversationId = Column(CodingKeys.sourceConversationId)
    }

    public static let conversation = belongsTo(Conversation.self)

    public var conversation: QueryInterfaceRequest<Conversation> {
        request(for: Message.conversation)
    }
}
