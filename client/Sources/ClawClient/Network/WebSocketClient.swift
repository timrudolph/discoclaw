import Foundation

/// Manages a single URLSessionWebSocketTask connection.
/// Must be used from the MainActor — all callbacks fire on the main actor.
@MainActor
public final class WebSocketClient {
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveLoopTask: Task<Void, Never>?

    /// Called for each successfully parsed event from the server.
    public var onEvent: ((WsEvent) -> Void)?
    /// Called when the connection opens.
    public var onConnect: (() -> Void)?
    /// Called when the connection closes or errors. Caller should schedule a reconnect.
    public var onDisconnect: (() -> Void)?

    public var isConnected: Bool {
        webSocketTask?.state == .running
    }

    public init() {}

    // MARK: - Lifecycle

    public func connect(to url: URL) {
        disconnect() // clean up any existing connection

        let task = URLSession.shared.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        onConnect?()

        // Start receive loop on the main actor.
        // URLSessionWebSocketTask.receive() suspends without blocking.
        receiveLoopTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.receiveLoop(task: task)
        }
    }

    public func disconnect() {
        receiveLoopTask?.cancel()
        receiveLoopTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - Receive loop

    private func receiveLoop(task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                if case .string(let text) = message, let event = WsEvent.parse(text) {
                    onEvent?(event)
                }
            } catch {
                // Connection closed or error — notify caller
                if !Task.isCancelled {
                    webSocketTask = nil
                    onDisconnect?()
                }
                return
            }
        }
    }
}
