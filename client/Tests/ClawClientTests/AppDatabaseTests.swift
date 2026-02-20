import XCTest
@testable import ClawClient

final class AppDatabaseTests: XCTestCase {
    var db: AppDatabase!
    var conversations: ConversationRepository!
    var messages: MessageRepository!

    override func setUp() async throws {
        db = try AppDatabase.makeInMemory()
        conversations = ConversationRepository(db: db)
        messages = MessageRepository(db: db)
    }

    // MARK: - Migrations

    func testMigrationsRun() async throws {
        let result = try await conversations.fetchAll()
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Conversations

    func testSaveAndFetchConversation() async throws {
        let conv = makeConversation(id: "c1", title: "Hello")
        try await conversations.save(conv)

        let fetched = try await conversations.fetch(id: "c1")
        XCTAssertEqual(fetched?.id, "c1")
        XCTAssertEqual(fetched?.title, "Hello")
    }

    func testArchivedConversationsFilteredByDefault() async throws {
        try await conversations.save(makeConversation(id: "active"))
        try await conversations.save(makeConversation(id: "archived", archivedAt: Date()))

        let active = try await conversations.fetchAll(includeArchived: false)
        XCTAssertEqual(active.count, 1)
        XCTAssertEqual(active.first?.id, "active")

        let all = try await conversations.fetchAll(includeArchived: true)
        XCTAssertEqual(all.count, 2)
    }

    func testDeleteConversationCascadesMessages() async throws {
        try await conversations.save(makeConversation(id: "c1"))
        try await messages.save(makeMessage(id: "m1", conversationId: "c1", seq: 1))
        try await messages.save(makeMessage(id: "m2", conversationId: "c1", seq: 2))

        try await conversations.delete(id: "c1")

        let remaining = try await messages.fetchMessages(conversationId: "c1")
        XCTAssertTrue(remaining.isEmpty)
    }

    // MARK: - Messages

    func testSaveAndFetchMessages() async throws {
        try await conversations.save(makeConversation(id: "c1"))
        try await messages.save(makeMessage(id: "m1", conversationId: "c1", seq: 1))
        try await messages.save(makeMessage(id: "m2", conversationId: "c1", seq: 2))

        let fetched = try await messages.fetchMessages(conversationId: "c1")
        XCTAssertEqual(fetched.count, 2)
        XCTAssertEqual(fetched.map(\.id), ["m1", "m2"]) // oldest-first
    }

    func testFetchMessagesBefore() async throws {
        try await conversations.save(makeConversation(id: "c1"))
        for i in 1...5 {
            try await messages.save(makeMessage(id: "m\(i)", conversationId: "c1", seq: i))
        }

        let page = try await messages.fetchMessages(conversationId: "c1", limit: 50, before: 4)
        XCTAssertEqual(page.map(\.seq), [1, 2, 3])
    }

    // MARK: - Streaming

    func testAppendDelta() async throws {
        try await conversations.save(makeConversation(id: "c1"))
        try await messages.save(makeMessage(id: "m1", conversationId: "c1", seq: 1, content: ""))

        try await messages.appendDelta(id: "m1", delta: "Hello")
        try await messages.appendDelta(id: "m1", delta: ", world!")

        let fetched = try await messages.fetch(id: "m1")
        XCTAssertEqual(fetched?.content, "Hello, world!")
    }

    func testUpdateStatus() async throws {
        try await conversations.save(makeConversation(id: "c1"))
        try await messages.save(makeMessage(id: "m1", conversationId: "c1", seq: 1))

        let now = Date()
        try await messages.updateStatus(id: "m1", status: .complete, completedAt: now)

        let fetched = try await messages.fetch(id: "m1")
        XCTAssertEqual(fetched?.status, .complete)
        XCTAssertNotNil(fetched?.completedAt)
    }

    func testUpdateStatusError() async throws {
        try await conversations.save(makeConversation(id: "c1"))
        try await messages.save(makeMessage(id: "m1", conversationId: "c1", seq: 1))

        try await messages.updateStatus(id: "m1", status: .error, error: "timeout")

        let fetched = try await messages.fetch(id: "m1")
        XCTAssertEqual(fetched?.status, .error)
        XCTAssertEqual(fetched?.error, "timeout")
    }

    // MARK: - Optimistic send

    func testConfirmOptimistic() async throws {
        try await conversations.save(makeConversation(id: "c1"))

        // Client creates an optimistic message with a temp id
        var optimistic = makeMessage(id: "temp-1", conversationId: "c1", seq: 0)
        optimistic.clientId = "client-uuid-1"
        optimistic.status = .pending
        try await messages.save(optimistic)

        // Server responds with the real id + seq
        try await messages.confirmOptimistic(
            clientId: "client-uuid-1",
            serverId: "server-uuid-1",
            seq: 42
        )

        let confirmed = try await messages.fetch(id: "server-uuid-1")
        XCTAssertNotNil(confirmed)
        XCTAssertEqual(confirmed?.seq, 42)
        XCTAssertEqual(confirmed?.status, .streaming)

        // Old temp id is gone
        let old = try await messages.fetch(id: "temp-1")
        XCTAssertNil(old)
    }

    func testFindByClientId() async throws {
        try await conversations.save(makeConversation(id: "c1"))
        var msg = makeMessage(id: "temp-1", conversationId: "c1", seq: 0)
        msg.clientId = "my-client-id"
        try await messages.save(msg)

        let found = try await messages.findByClientId("my-client-id")
        XCTAssertEqual(found?.id, "temp-1")
    }
}

// MARK: - Helpers

private func makeConversation(
    id: String,
    title: String? = nil,
    archivedAt: Date? = nil
) -> Conversation {
    Conversation(
        id: id,
        title: title,
        claudeSessionId: nil,
        createdAt: Date(),
        updatedAt: Date(),
        archivedAt: archivedAt
    )
}

private func makeMessage(
    id: String,
    conversationId: String,
    seq: Int,
    content: String = "test",
    role: Message.Role = .user,
    status: Message.Status = .complete
) -> Message {
    Message(
        id: id,
        clientId: nil,
        conversationId: conversationId,
        role: role,
        content: content,
        status: status,
        error: nil,
        seq: seq,
        createdAt: Date(),
        completedAt: nil
    )
}
