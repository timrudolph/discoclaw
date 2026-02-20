import Combine
import Foundation

/// Orchestrates the full sync lifecycle:
///   1. On `start()` — delta-sync from server, then open WebSocket.
///   2. On WS event — apply changes to local DB, advance cursor.
///   3. On disconnect — reconnect after a short delay, re-sync any missed events.
///
/// Conforms to `ObservableObject` so SwiftUI views can observe connectivity
/// and tool activity state directly.
@MainActor
public final class SyncEngine: ObservableObject {
    /// Whether the WebSocket is currently connected.
    @Published public private(set) var isConnected = false
    /// Whether an HTTP sync is in flight.
    @Published public private(set) var isSyncing = false
    /// Active tool labels keyed by assistant message ID — drives UI spinners.
    @Published public private(set) var activeTools: [String: String] = [:]

    private let api: APIClient
    private let ws: WebSocketClient
    private let conversationRepo: ConversationRepository
    private let messageRepo: MessageRepository

    private var reconnectTask: Task<Void, Never>?

    public init(
        api: APIClient,
        conversations: ConversationRepository,
        messages: MessageRepository
    ) {
        self.api = api
        self.ws = WebSocketClient()
        self.conversationRepo = conversations
        self.messageRepo = messages

        ws.onEvent = { [weak self] event in self?.handle(event) }
        ws.onConnect = { [weak self] in self?.isConnected = true }
        ws.onDisconnect = { [weak self] in
            self?.isConnected = false
            self?.scheduleReconnect()
        }
    }

    // MARK: - Lifecycle

    public func start() async {
        await performSync()
        connectWebSocket()
    }

    public func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        ws.disconnect()
        isConnected = false
    }

    // MARK: - Sync

    private func performSync() async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let response = try await api.sync(since: SyncCursor.value)

            let convs = response.conversations.map { $0.toConversation() }
            try await conversationRepo.saveAll(convs)

            let msgs = response.messages.map { $0.toMessage() }
            try await messageRepo.saveAll(msgs)

            SyncCursor.advance(to: response.cursor)
        } catch {
            // Non-fatal: the local cache is still displayed. Will retry on reconnect.
        }
    }

    private func connectWebSocket() {
        ws.connect(to: api.webSocketURL)
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            await self.performSync()
            self.connectWebSocket()
        }
    }

    // MARK: - WebSocket event handling

    private func handle(_ event: WsEvent) {
        Task { [weak self] in
            guard let self else { return }
            await self.applyEvent(event)
        }
    }

    private func applyEvent(_ event: WsEvent) async {
        switch event {
        case .messageDelta(let messageId, _, let delta, let seq):
            try? await messageRepo.appendDelta(id: messageId, delta: delta)
            SyncCursor.advance(to: seq)

        case .messageComplete(let messageId, _, let content, let seq):
            // Overwrite with authoritative content — handles any missed delta chunks.
            try? await messageRepo.finalize(id: messageId, content: content, completedAt: Date())
            activeTools.removeValue(forKey: messageId)
            SyncCursor.advance(to: seq)

        case .messageError(let messageId, _, let error):
            try? await messageRepo.updateStatus(id: messageId, status: .error, error: error)
            activeTools.removeValue(forKey: messageId)

        case .toolStart(let messageId, _, let label):
            activeTools[messageId] = label

        case .toolEnd(let messageId, _):
            activeTools.removeValue(forKey: messageId)

        case .conversationUpdated:
            // Metadata changed on another device — pull the delta.
            await performSync()
        }
    }
}
