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
    public let modelOverride: String?
    public let assistantName: String?
    public let accentColor: String?
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
    public let modelOverride: String?
    public let assistantName: String?
    public let accentColor: String?
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
    public let modelOverride: String??    // Double-optional: nil = don't touch; .some(nil) = clear
    public let assistantName: String??    // Double-optional: nil = don't touch; .some(nil) = clear
    public let accentColor: String??      // Double-optional: nil = don't touch; .some(nil) = clear
    public init(
        title: String? = nil,
        archived: Bool? = nil,
        modelOverride: String?? = nil,
        assistantName: String?? = nil,
        accentColor: String?? = nil
    ) {
        self.title = title
        self.archived = archived
        self.modelOverride = modelOverride
        self.assistantName = assistantName
        self.accentColor = accentColor
    }
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

// ─── Cron jobs ────────────────────────────────────────────────────────────────

public struct CronJob: Decodable, Identifiable {
    public let id: String
    public let name: String
    public let schedule: String
    public let timezone: String
    public let prompt: String
    public let conversationId: String
    public let enabled: Bool
    public let lastRunAt: Int?
    public let createdAt: Int
}

public struct CronJobsResponse: Decodable {
    public let jobs: [CronJob]
}

public struct CreateCronJobRequest: Encodable {
    public let name: String
    public let schedule: String
    public let timezone: String
    public let prompt: String
    public let conversationId: String
    public init(name: String, schedule: String, timezone: String, prompt: String, conversationId: String) {
        self.name = name; self.schedule = schedule; self.timezone = timezone
        self.prompt = prompt; self.conversationId = conversationId
    }
}

public struct UpdateCronJobRequest: Encodable {
    public let enabled: Bool?
    public let name: String?
    public let schedule: String?
    public let timezone: String?
    public let prompt: String?
    public init(enabled: Bool? = nil, name: String? = nil, schedule: String? = nil, timezone: String? = nil, prompt: String? = nil) {
        self.enabled = enabled; self.name = name; self.schedule = schedule
        self.timezone = timezone; self.prompt = prompt
    }
}

// ─── Beads ────────────────────────────────────────────────────────────────────

public struct Bead: Decodable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let status: String
    public let description: String?
    public let priority: Int?
    public let owner: String?
    public let labels: [String]?
    public let createdAt: String?
    public let updatedAt: String?
    public let closedAt: String?
    public let closeReason: String?

    public var statusEmoji: String {
        switch status {
        case "open":        return "🟢"
        case "in_progress": return "🟡"
        case "blocked":     return "⚠️"
        case "closed":      return "☑️"
        default:            return "⚪"
        }
    }

    public var displayPriority: String {
        guard let p = priority else { return "" }
        return "P\(p)"
    }
}

public struct BeadsResponse: Decodable {
    public let beads: [Bead]
}

public struct CreateBeadRequest: Encodable {
    public let title: String
    public let description: String?
    public let priority: Int?
    public let owner: String?
    public init(title: String, description: String?, priority: Int?, owner: String? = nil) {
        self.title = title; self.description = description
        self.priority = priority; self.owner = owner
    }
}

public struct UpdateBeadRequest: Encodable {
    public let title: String?
    public let description: String?
    public let status: String?
    public let priority: Int?
    public let owner: String?
    public init(title: String?, description: String?, status: String?, priority: Int?, owner: String? = nil) {
        self.title = title; self.description = description
        self.status = status; self.priority = priority; self.owner = owner
    }
}

public struct AddBeadLabelRequest: Encodable {
    public let label: String
    public init(label: String) { self.label = label }
}

public struct CloseBeadRequest: Encodable {
    public let reason: String?
    public init(reason: String?) { self.reason = reason }
}

// ─── Workspace ────────────────────────────────────────────────────────────────

public struct WorkspaceFilesResponse: Decodable {
    public let files: [WorkspaceFileInfo]

    public struct WorkspaceFileInfo: Decodable, Identifiable {
        public var id: String { name }
        public let name: String
        public let exists: Bool
        public let preview: String
    }
}

public struct WorkspaceFileResponse: Decodable {
    public let name: String
    public let content: String
}

public struct WorkspaceFileUpdateRequest: Encodable {
    public let content: String
    public init(content: String) { self.content = content }
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

// ─── Models ───────────────────────────────────────────────────────────────────

public struct ConversationModel: Decodable, Identifiable {
    public var id: String
    public let label: String
    public let description: String
}

public struct ModelsResponse: Decodable {
    public let models: [ConversationModel]
    public let `default`: String
}

// ─── Context modules ──────────────────────────────────────────────────────────

public struct ContextModule: Decodable, Identifiable {
    public var id: String { name }
    public let name: String    // e.g. "beads.md"
    public let label: String   // first heading from the file
}

public struct ContextModulesListResponse: Decodable {
    public let modules: [ContextModule]
}

public struct ConversationModulesResponse: Decodable {
    public let modules: [String]   // active module filenames
}

public struct CreateContextModuleRequest: Encodable {
    public let name: String
    public let content: String
}

// ─── Health / Features ────────────────────────────────────────────────────────

public struct HealthResponse: Decodable {
    public let ok: Bool
    /// nil if the server is older and doesn't include this field (treat as enabled).
    public let beadsEnabled: Bool?
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
        public let modelOverride: String?
        public let assistantName: String?
        public let accentColor: String?
        public let claudeSessionId: String?
        public let updatedAt: Int
        public let createdAt: Int
        public let archivedAt: Int?

        public func toConversation() -> Conversation {
            Conversation(
                id: id,
                title: title,
                claudeSessionId: claudeSessionId,
                createdAt: Date(timeIntervalSince1970: Double(createdAt) / 1000),
                updatedAt: Date(timeIntervalSince1970: Double(updatedAt) / 1000),
                archivedAt: archivedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) },
                isProtected: isProtected ?? false,
                kind: kind,
                modelOverride: modelOverride,
                assistantName: assistantName,
                accentColor: accentColor
            )
        }
    }
}

// MARK: - Message search

public struct MessageSearchResponse: Decodable {
    public let results: [SearchResult]

    public struct SearchResult: Decodable, Identifiable {
        public let messageId: String
        public let conversationId: String
        public let conversationTitle: String
        public let role: String
        public let snippet: String
        public let createdAt: Int

        public var id: String { messageId }
    }
}
