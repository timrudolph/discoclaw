import SwiftUI
import ClawClient

@main
struct ClawApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

struct AppRootView: View {
    // Container is nil until a session is configured.
    @State private var container: AppContainer? = {
        guard let session = SessionConfig.load() else { return nil }
        return try? AppContainer(session: session)
    }()

    @State private var selectedConversationId: String?
    @State private var selectedConversation: Conversation?

    @AppStorage("appearance") private var appearance = "auto"

    private var preferredScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark":  return .dark
        default:      return nil
        }
    }

    var body: some View {
        if let container {
            NavigationSplitView {
                ConversationListView(
                    selectedId: $selectedConversationId,
                    repo: container.conversationRepo,
                    api: container.api,
                    onSignOut: {
                        container.syncEngine.stop()
                        SessionConfig.clear()
                        selectedConversationId = nil
                        selectedConversation = nil
                        self.container = nil
                    }
                )
            } detail: {
                if let id = selectedConversationId {
                    ChatView(
                        conversationId: id,
                        conversation: selectedConversation,
                        messageRepo: container.messageRepo,
                        api: container.api
                    )
                    .environmentObject(container.syncEngine)
                    // Re-create ChatView (and its @StateObject) when conversation changes.
                    .id(id)
                } else {
                    ContentUnavailableView(
                        "No Conversation",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Select a conversation or tap the compose button to start one.")
                    )
                }
            }
            .task {
                await container.syncEngine.start()
                // Auto-select the protected General conversation if nothing else is selected.
                if selectedConversationId == nil {
                    if let general = try? await container.conversationRepo.firstProtected() {
                        selectedConversationId = general.id
                    }
                }
            }
            // Keep selectedConversation in sync with selectedConversationId.
            .task(id: selectedConversationId) {
                guard let id = selectedConversationId else { selectedConversation = nil; return }
                selectedConversation = try? await container.conversationRepo.fetch(id: id)
            }
            .preferredColorScheme(preferredScheme)
        } else {
            OnboardingView { newSession in
                newSession.save()
                container = try? AppContainer(session: newSession)
            }
        }
    }
}
