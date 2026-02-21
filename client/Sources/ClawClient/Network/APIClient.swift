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

    public func updateUserProfile(name: String?) async throws {
        var req = makeRequest("PATCH", "/auth/me")
        req.httpBody = try JSONEncoder().encode(["name": name])
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)
    }

    // MARK: - Avatars

    public func uploadUserAvatar(_ jpeg: Data) async throws {
        var req = makeRequest("PUT", "/auth/avatar")
        req.httpBody = jpeg
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)
    }

    public func fetchUserAvatar() async throws -> Data? {
        let req = makeRequest("GET", "/auth/avatar")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        try checkStatus(response, data: data)
        return data
    }

    public func uploadAssistantAvatar(conversationId: String, _ jpeg: Data) async throws {
        var req = makeRequest("PUT", "/conversations/\(conversationId)/avatar")
        req.httpBody = jpeg
        req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)
    }

    public func fetchAssistantAvatar(conversationId: String) async throws -> Data? {
        let req = makeRequest("GET", "/conversations/\(conversationId)/avatar")
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        try checkStatus(response, data: data)
        return data
    }

    // MARK: - Cron jobs

    public func listCronJobs() async throws -> CronJobsResponse {
        try await get("/crons")
    }

    public func createCronJob(name: String, schedule: String, timezone: String, prompt: String, conversationId: String) async throws -> CronJob {
        try await post("/crons", body: CreateCronJobRequest(name: name, schedule: schedule, timezone: timezone, prompt: prompt, conversationId: conversationId))
    }

    public func updateCronJob(id: String, enabled: Bool? = nil, name: String? = nil, schedule: String? = nil, timezone: String? = nil, prompt: String? = nil) async throws -> CronJob {
        try await patch("/crons/\(id)", body: UpdateCronJobRequest(enabled: enabled, name: name, schedule: schedule, timezone: timezone, prompt: prompt))
    }

    public func deleteCronJob(id: String) async throws {
        let (data, response) = try await session.data(for: makeRequest("DELETE", "/crons/\(id)"))
        try checkStatus(response, data: data)
    }

    // MARK: - Beads

    public func listBeads(status: String = "open", limit: Int = 100) async throws -> BeadsResponse {
        try await get("/beads?status=\(status)&limit=\(limit)")
    }

    public func getBead(id: String) async throws -> Bead {
        try await get("/beads/\(id)")
    }

    public func createBead(title: String, description: String? = nil, priority: Int? = nil, owner: String? = nil) async throws -> Bead {
        try await post("/beads", body: CreateBeadRequest(title: title, description: description, priority: priority, owner: owner))
    }

    public func updateBead(id: String, title: String? = nil, description: String? = nil, status: String? = nil, priority: Int? = nil, owner: String? = nil) async throws -> Bead? {
        try await patch("/beads/\(id)", body: UpdateBeadRequest(title: title, description: description, status: status, priority: priority, owner: owner))
    }

    public func closeBead(id: String, reason: String? = nil) async throws -> Bead? {
        try await post("/beads/\(id)/close", body: CloseBeadRequest(reason: reason))
    }

    public func addBeadLabel(id: String, label: String) async throws -> Bead {
        try await post("/beads/\(id)/labels", body: AddBeadLabelRequest(label: label))
    }

    // MARK: - Workspace files

    public func listWorkspaceFiles() async throws -> WorkspaceFilesResponse {
        try await get("/workspace/files")
    }

    public func getWorkspaceFile(name: String) async throws -> WorkspaceFileResponse {
        try await get("/workspace/files/\(name)")
    }

    public func updateWorkspaceFile(name: String, content: String) async throws {
        var req = makeRequest("PUT", "/workspace/files/\(name)")
        req.httpBody = try JSONEncoder().encode(WorkspaceFileUpdateRequest(content: content))
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: req)
        try checkStatus(response, data: data)
    }

    // MARK: - Memory (global)

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

    // MARK: - Memory (per-conversation)

    public func listConversationMemory(conversationId: String) async throws -> MemoryListResponse {
        try await get("/conversations/\(conversationId)/memory")
    }

    public func addConversationMemory(conversationId: String, content: String) async throws -> AddMemoryResponse {
        try await post("/conversations/\(conversationId)/memory", body: AddMemoryRequest(content: content))
    }

    public func deleteConversationMemory(conversationId: String, id: String) async throws {
        let (data, response) = try await session.data(for: makeRequest("DELETE", "/conversations/\(conversationId)/memory/\(id)"))
        try checkStatus(response, data: data)
    }

    public func listDevices() async throws -> DeviceListResponse {
        try await get("/auth/devices")
    }

    public func revokeDevice(id: String) async throws {
        let (data, response) = try await session.data(for: makeRequest("DELETE", "/auth/devices/\(id)"))
        try checkStatus(response, data: data)
    }

    // MARK: - Models

    public func listModels() async throws -> ModelsResponse {
        try await get("/models")
    }

    // MARK: - Context modules

    public func listContextModules() async throws -> ContextModulesListResponse {
        try await get("/context-modules")
    }

    public func createContextModule(name: String, content: String) async throws -> ContextModule {
        try await post("/context-modules", body: CreateContextModuleRequest(name: name, content: content))
    }

    public func deleteContextModule(name: String) async throws {
        let (data, response) = try await session.data(for: makeRequest("DELETE", "/context-modules/\(name)"))
        try checkStatus(response, data: data)
    }

    // MARK: - Persona

    public func updatePersona(conversationId: String, soul: String?, identity: String?, userBio: String?) async throws -> ConversationPersona {
        try await put("/conversations/\(conversationId)/persona",
                      body: UpdatePersonaRequest(soul: soul, identity: identity, userBio: userBio))
    }

    public func resetConversationSession(conversationId: String) async throws {
        let (data, response) = try await session.data(for: makeRequest("POST", "/conversations/\(conversationId)/reset-session"))
        try checkStatus(response, data: data)
    }

    public func getConversationModules(conversationId: String) async throws -> ConversationModulesResponse {
        try await get("/conversations/\(conversationId)/context-modules")
    }

    public func setConversationModules(conversationId: String, modules: [String]) async throws {
        var req = makeRequest("PUT", "/conversations/\(conversationId)/context-modules")
        req.httpBody = try JSONEncoder().encode(["modules": modules])
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: req)
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
        archived: Bool? = nil,
        modelOverride: String?? = nil,
        assistantName: String?? = nil,
        accentColor: String?? = nil
    ) async throws -> ConversationDetail {
        try await patch(
            "/conversations/\(id)",
            body: UpdateConversationRequest(
                title: title,
                archived: archived,
                modelOverride: modelOverride,
                assistantName: assistantName,
                accentColor: accentColor
            )
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

    public func cancelMessage(conversationId: String) async throws {
        let (data, response) = try await session.data(
            for: makeRequest("POST", "/conversations/\(conversationId)/cancel")
        )
        try checkStatus(response, data: data)
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

    // MARK: - Search

    public func searchMessages(query: String, limit: Int = 20) async throws -> MessageSearchResponse {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await get("/search?q=\(encoded)&limit=\(limit)")
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

    private func put<B: Encodable, T: Decodable>(_ path: String, body: B) async throws -> T {
        var req = makeRequest("PUT", path)
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
