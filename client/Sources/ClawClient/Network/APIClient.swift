import Foundation

public enum APIError: LocalizedError {
    case httpError(statusCode: Int, body: String)
    case unexpectedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .unexpectedResponse(let detail): return "Unexpected response: \(detail)"
        }
    }
}

/// Typed HTTP client for the ClawServer REST API.
/// All methods are async/throws. Thread-safe — uses URLSession which handles its own concurrency.
public final class APIClient: Sendable {
    public let baseURL: URL
    private let token: String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    // MARK: - Auth

    public func me() async throws -> MeResponse {
        try await get("/auth/me")
    }

    public func listMemory() async throws -> MemoryListResponse {
        try await get("/memory")
    }

    public func addMemory(content: String) async throws -> AddMemoryResponse {
        try await post("/memory", body: AddMemoryRequest(content: content))
    }

    public func deleteMemory(id: String) async throws {
        let (data, response) = try await session.data(for: makeRequest("DELETE", "/memory/\(id)"))
        try checkStatus(response, data: data)
    }

    public func listDevices() async throws -> DeviceListResponse {
        try await get("/auth/devices")
    }

    public func revokeDevice(id: String) async throws {
        let (data, response) = try await session.data(for: makeRequest("DELETE", "/auth/devices/\(id)"))
        try checkStatus(response, data: data)
    }

    // MARK: - Conversations

    public func listConversations(includeArchived: Bool = false) async throws -> [ConversationListItem] {
        try await get("/conversations\(includeArchived ? "?archived=true" : "")")
    }

    public func createConversation(title: String? = nil) async throws -> ConversationDetail {
        try await post("/conversations", body: CreateConversationRequest(title: title))
    }

    public func updateConversation(
        id: String,
        title: String? = nil,
        archived: Bool? = nil
    ) async throws -> ConversationDetail {
        try await patch(
            "/conversations/\(id)",
            body: UpdateConversationRequest(title: title, archived: archived)
        )
    }

    public func deleteConversation(id: String) async throws {
        let (data, response) = try await session.data(for: makeRequest("DELETE", "/conversations/\(id)"))
        try checkStatus(response, data: data)
    }

    // MARK: - Messages

    public func listMessages(
        conversationId: String,
        limit: Int = 50,
        before: Int? = nil
    ) async throws -> MessagesResponse {
        var path = "/conversations/\(conversationId)/messages?limit=\(limit)"
        if let before { path += "&before=\(before)" }
        return try await get(path)
    }

    public func sendMessage(
        conversationId: String,
        content: String,
        clientId: String? = nil
    ) async throws -> SendMessageResponse {
        try await post(
            "/conversations/\(conversationId)/messages",
            body: SendMessageRequest(content: content, clientId: clientId)
        )
    }

    // MARK: - Sync

    public func sync(since: Int = 0) async throws -> SyncResponse {
        try await get("/sync?since=\(since)")
    }

    // MARK: - WebSocket URL

    /// The URL for the WebSocket connection. Converts http→ws, https→wss and appends ?token=.
    public var webSocketURL: URL {
        var comps = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        comps.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        comps.path = "/ws"
        comps.queryItems = [URLQueryItem(name: "token", value: token)]
        return comps.url!
    }

    // MARK: - Internals

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await session.data(for: makeRequest("GET", path))
        try checkStatus(response, data: data)
        return try decode(T.self, from: data)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var req = makeRequest("POST", path)
        req.httpBody = try JSONEncoder().encode(body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)
        return try decode(T.self, from: data)
    }

    private func patch<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var req = makeRequest("PATCH", path)
        req.httpBody = try JSONEncoder().encode(body)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)
        return try decode(T.self, from: data)
    }

    /// Build a URLRequest for the given method and path.
    /// `path` may contain a query string (e.g. "/sync?since=42").
    private func makeRequest(_ method: String, _ path: String) -> URLRequest {
        // URL(string:relativeTo:) correctly handles paths with query strings.
        let url = URL(string: path, relativeTo: baseURL)!.absoluteURL
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.unexpectedResponse("not an HTTP response")
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "(binary)"
            throw APIError.httpError(statusCode: http.statusCode, body: body)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            let preview = String(data: data.prefix(200), encoding: .utf8) ?? "(binary)"
            throw APIError.unexpectedResponse("decode failed: \(error) — body: \(preview)")
        }
    }
}
