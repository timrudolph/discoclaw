import Foundation

// ─── Auth ─────────────────────────────────────────────────────────────────────

public struct RegisterRequest: Encodable {
    public let name: String?
    public let platform: String
    public init(name: String?, platform: String) {
        self.name = name
        self.platform = platform
    }
}

/// Used only for the initial device registration (POST /auth/register).
/// Carries the one-time setup token in addition to the device info.
public struct InitialRegisterRequest: Encodable {
    public let name: String?
    public let platform: String
    public let setupToken: String
    public init(name: String?, platform: String, setupToken: String) {
        self.name = name
        self.platform = platform
        self.setupToken = setupToken
    }
}

public struct RegisterResponse: Decodable {
    public let userId: String
    public let deviceId: String
    public let token: String
}

public struct MeResponse: Decodable {
    public let user: UserInfo
    public let device: DeviceInfo

    public struct UserInfo: Decodable {
        public let id: String
        public let name: String?
    }

    public struct DeviceInfo: Decodable {
        public let id: String
        public let name: String?
        public let platform: String?
    }
}

// ─── Conversations ────────────────────────────────────────────────────────────

public struct ConversationListItem: Decodable {
    public let id: String
    public let title: String?
    public let isProtected: Bool?
    public let kind: String?
    public let updatedAt: Int
    public let createdAt: Int
    public let archivedAt: Int?
    public let lastMessage: LastMessage?

    public struct LastMessage: Decodable {
        public let role: String
        public let content: String
        public let createdAt: Int
    }
}

public struct ConversationDetail: Decodable {
    public let id: String
    public let title: String?
    public let isProtected: Bool?
    public let kind: String?
    public let claudeSessionId: String?
    public let createdAt: Int
    public let updatedAt: Int
    public let archivedAt: Int?
}

public struct CreateConversationRequest: Encodable {
    public let title: String?
    public init(title: String?) { self.title = title }
}

public struct UpdateConversationRequest: Encodable {
    public let title: String?
    public let archived: Bool?
    public init(title: String?, archived: Bool?) { self.title = title; self.archived = archived }
}

// ─── Messages ─────────────────────────────────────────────────────────────────

public struct MessageDTO: Decodable {
    public let id: String
    public let clientId: String?
    public let conversationId: String
    public let role: String
    public let content: String
    public let status: String
    public let error: String?
    public let seq: Int
    public let createdAt: Int
    public let completedAt: Int?

    public func toMessage() -> Message {
        Message(
            id: id,
            clientId: clientId,
            conversationId: conversationId,
            role: Message.Role(rawValue: role) ?? .user,
            content: content,
            status: Message.Status(rawValue: status) ?? .complete,
            error: error,
            seq: seq,
            createdAt: Date(timeIntervalSince1970: Double(createdAt) / 1000),
            completedAt: completedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) }
        )
    }
}

public struct MessagesResponse: Decodable {
    public let messages: [MessageDTO]
    public let hasMore: Bool
}

public struct SendMessageRequest: Encodable {
    public let content: String
    public let clientId: String?
    public init(content: String, clientId: String?) { self.content = content; self.clientId = clientId }
}

public struct SendMessageResponse: Decodable {
    public let id: String
    public let seq: Int
    public let clientId: String?
    public let status: String
    public let assistantMessageId: String
}

// ─── Memory ───────────────────────────────────────────────────────────────────

public struct MemoryListResponse: Decodable {
    public let items: [MemoryItem]

    public struct MemoryItem: Decodable, Identifiable {
        public let id: String
        public let content: String
        public let createdAt: Int
    }
}

public struct AddMemoryRequest: Encodable {
    public let content: String
    public init(content: String) { self.content = content }
}

public struct AddMemoryResponse: Decodable {
    public let id: String
    public let content: String
}

// ─── Devices ──────────────────────────────────────────────────────────────────

public struct DeviceListResponse: Decodable {
    public let devices: [DeviceItem]

    public struct DeviceItem: Decodable, Identifiable {
        public let id: String
        public let name: String?
        public let platform: String?
        public let lastSeen: Int?
        public let createdAt: Int
        public let isCurrent: Bool
    }
}

// ─── Sync ─────────────────────────────────────────────────────────────────────

public struct SyncResponse: Decodable {
    public let conversations: [ConversationSyncItem]
    public let messages: [MessageDTO]
    public let cursor: Int

    public struct ConversationSyncItem: Decodable {
        public let id: String
        public let title: String?
        public let isProtected: Bool?
        public let kind: String?
        public let updatedAt: Int
        public let createdAt: Int
        public let archivedAt: Int?

        public func toConversation() -> Conversation {
            Conversation(
                id: id,
                title: title,
                claudeSessionId: nil,
                createdAt: Date(timeIntervalSince1970: Double(createdAt) / 1000),
                updatedAt: Date(timeIntervalSince1970: Double(updatedAt) / 1000),
                archivedAt: archivedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) },
                isProtected: isProtected ?? false,
                kind: kind
            )
        }
    }
}
