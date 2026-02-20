import Combine
import Foundation
import ClawClient

@MainActor
final class ConversationListViewModel: ObservableObject {
    @Published private(set) var conversations: [Conversation] = []
    @Published var showArchived = false {
        didSet { setupObservation() }
    }

    private let repo: ConversationRepository
    private let api: APIClient
    private var cancellables = Set<AnyCancellable>()

    init(repo: ConversationRepository, api: APIClient) {
        self.repo = repo
        self.api = api
        setupObservation()
    }

    private func setupObservation() {
        cancellables.removeAll()
        repo.observeAll(includeArchived: showArchived)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] convs in
                self?.conversations = convs.sorted {
                    let order: (Conversation) -> Int = { conv in
                        if conv.isArchived { return 100 }
                        guard conv.isProtected else { return 99 }
                        switch conv.kind {
                        case "general": return 0
                        case "tasks":   return 1
                        case "journal": return 2
                        default:        return 3
                        }
                    }
                    let a = order($0), b = order($1)
                    if a != b { return a < b }
                    return $0.updatedAt > $1.updatedAt
                }
            })
            .store(in: &cancellables)
    }

    /// Creates a new conversation on the server, inserts it locally, and returns its id.
    func newConversation() async -> String? {
        do {
            let detail = try await api.createConversation()
            let conv = Conversation(
                id: detail.id,
                title: detail.title,
                claudeSessionId: nil,
                createdAt: Date(timeIntervalSince1970: Double(detail.createdAt) / 1000),
                updatedAt: Date(timeIntervalSince1970: Double(detail.updatedAt) / 1000),
                archivedAt: nil,
                isProtected: detail.isProtected ?? false,
                kind: detail.kind
            )
            try await repo.save(conv)
            return detail.id
        } catch {
            return nil
        }
    }

    func rename(_ conversation: Conversation, title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let detail = try await api.updateConversation(id: conversation.id, title: trimmed)
            var updated = conversation
            updated.title = detail.title
            updated.updatedAt = Date(timeIntervalSince1970: Double(detail.updatedAt) / 1000)
            try await repo.save(updated)
        } catch {}
    }

    func archive(_ conversation: Conversation) async {
        do {
            let detail = try await api.updateConversation(id: conversation.id, archived: true)
            var updated = conversation
            updated.archivedAt = detail.archivedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) }
            updated.updatedAt = Date(timeIntervalSince1970: Double(detail.updatedAt) / 1000)
            try await repo.save(updated)
        } catch {}
    }

    func unarchive(_ conversation: Conversation) async {
        do {
            let detail = try await api.updateConversation(id: conversation.id, archived: false)
            var updated = conversation
            updated.archivedAt = nil
            updated.updatedAt = Date(timeIntervalSince1970: Double(detail.updatedAt) / 1000)
            try await repo.save(updated)
        } catch {}
    }

    func delete(_ conversation: Conversation) async {
        // Delete locally first so the UI snaps immediately, then server.
        try? await repo.delete(id: conversation.id)
        try? await api.deleteConversation(id: conversation.id)
    }
}
