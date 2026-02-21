import Combine
import Foundation
import ClawClient

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messages: [Message] = []
    @Published private(set) var isSending = false
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    /// Set when a send fails at the HTTP level. Displayed as a dismissible alert.
    @Published var sendError: String?

    /// True while the most recent assistant message is still streaming.
    var isStreaming: Bool {
        messages.last?.role == .assistant && messages.last?.status == .streaming
    }

    let conversationId: String

    /// Drive scroll-to-bottom whenever the trailing message's content grows (streaming).
    var lastMessageContent: String { messages.last?.content ?? "" }

    private let repo: MessageRepository
    private let api: APIClient
    private var cancellables = Set<AnyCancellable>()
    /// Set to true after the first loadMore() response to stop showing the button
    /// once we've confirmed nothing older exists.
    private var confirmedAllLoaded = false

    init(conversationId: String, repo: MessageRepository, api: APIClient) {
        self.conversationId = conversationId
        self.repo = repo
        self.api = api

        repo.observeMessages(conversationId: conversationId)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] msgs in
                guard let self else { return }
                self.messages = msgs
                // Show "load more" if we have a full page and haven't yet confirmed
                // there's nothing older from the server.
                if !self.confirmedAllLoaded {
                    self.hasMore = msgs.count >= 50
                }
            })
            .store(in: &cancellables)
    }

    func send(content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        sendError = nil

        let clientId = UUID().uuidString

        // Optimistic insert — shown immediately while the request is in flight.
        let optimistic = Message(
            id: clientId,
            clientId: clientId,
            conversationId: conversationId,
            role: .user,
            content: trimmed,
            status: .pending,
            error: nil,
            seq: (messages.last?.seq ?? 0) + 1,
            createdAt: Date(),
            completedAt: nil
        )
        try? await repo.save(optimistic)

        do {
            let response = try await api.sendMessage(
                conversationId: conversationId,
                content: trimmed,
                clientId: clientId
            )

            // Promote the optimistic row to the server-assigned id + seq.
            try? await repo.confirmOptimistic(
                clientId: clientId,
                serverId: response.id,
                seq: response.seq
            )

            // Insert a placeholder for the incoming assistant turn.
            // Use saveIfAbsent (INSERT OR IGNORE) so we don't overwrite an error state
            // that may have already been written by a fast-arriving WebSocket event.
            let placeholder = Message(
                id: response.assistantMessageId,
                clientId: nil,
                conversationId: conversationId,
                role: .assistant,
                content: "",
                status: .streaming,
                error: nil,
                seq: response.seq + 1,
                createdAt: Date(),
                completedAt: nil
            )
            try? await repo.saveIfAbsent(placeholder)
        } catch {
            // Mark the optimistic message as failed so it shows as an error bubble.
            try? await repo.updateStatus(
                id: clientId,
                status: .error,
                error: error.localizedDescription
            )
            // Also surface a persistent alert — the error bubble can be missed or synced away.
            sendError = error.localizedDescription
        }
    }

    func cancel() async {
        try? await api.cancelMessage(conversationId: conversationId)
    }

    /// Delete the failed user message and re-send its content.
    func retry(message: Message) async {
        let content = message.content
        try? await repo.delete(id: message.id)
        await send(content: content)
    }

    /// Load messages older than the current oldest. Returns the id of the current
    /// oldest message so the caller can restore scroll position.
    @discardableResult
    func loadMore() async -> String? {
        guard !isLoadingMore, let oldest = messages.first else { return nil }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let anchorId = oldest.id
        do {
            let response = try await api.listMessages(
                conversationId: conversationId,
                limit: 50,
                before: oldest.seq
            )
            try? await repo.saveAll(response.messages.map { $0.toMessage() })
            confirmedAllLoaded = !response.hasMore
            hasMore = response.hasMore
        } catch {}
        return anchorId
    }
}
