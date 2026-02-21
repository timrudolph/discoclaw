import Foundation
import SwiftUI
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
    public var modelOverride: String?
    /// Per-conversation SOUL.md content.
    public var soul: String?
    /// Per-conversation IDENTITY.md content.
    public var identity: String?
    /// Per-conversation USER.md content.
    public var userBio: String?
    /// Display name for the assistant in this conversation.
    public var assistantName: String?
    /// Hex accent color for the assistant's bubbles, e.g. "#A08060".
    public var accentColor: String?

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

    /// Parses `accentColor` hex string (e.g. "#A08060") into a SwiftUI Color.
    public var accentSwiftUIColor: Color? {
        guard let hex = accentColor else { return nil }
        var str = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("#") { str = String(str.dropFirst()) }
        guard str.count == 6, let value = Int(str, radix: 16) else { return nil }
        return Color(
            red:   Double((value >> 16) & 0xFF) / 255,
            green: Double((value >>  8) & 0xFF) / 255,
            blue:  Double( value        & 0xFF) / 255
        )
    }

    public init(
        id: String,
        title: String? = nil,
        claudeSessionId: String? = nil,
        createdAt: Date,
        updatedAt: Date,
        archivedAt: Date? = nil,
        isProtected: Bool = false,
        kind: String? = nil,
        modelOverride: String? = nil,
        soul: String? = nil,
        identity: String? = nil,
        userBio: String? = nil,
        assistantName: String? = nil,
        accentColor: String? = nil
    ) {
        self.id = id
        self.title = title
        self.claudeSessionId = claudeSessionId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.archivedAt = archivedAt
        self.isProtected = isProtected
        self.kind = kind
        self.modelOverride = modelOverride
        self.soul = soul
        self.identity = identity
        self.userBio = userBio
        self.assistantName = assistantName
        self.accentColor = accentColor
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
