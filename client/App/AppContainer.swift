import Foundation
import ClawClient

/// Holds all long-lived service objects for the app.
/// Created once on launch with a SessionConfig, injected as an environment object.
@MainActor
final class AppContainer: ObservableObject {
    let api: APIClient
    let conversationRepo: ConversationRepository
    let messageRepo: MessageRepository
    let syncEngine: SyncEngine

    init(session: SessionConfig) throws {
        let db = try AppDatabase.makeShared()
        api = APIClient(baseURL: session.serverURL, token: session.token)
        conversationRepo = ConversationRepository(db: db)
        messageRepo = MessageRepository(db: db)
        syncEngine = SyncEngine(api: api, conversations: conversationRepo, messages: messageRepo)
    }
}
