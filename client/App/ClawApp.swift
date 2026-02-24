import SwiftUI
#if os(macOS)
import AppKit
#endif
import ClawClient

@main
struct ClawApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}

#if os(macOS)
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
#endif

enum SidebarMode {
    case chats, beads
}

#if os(iOS)
/// Typed navigation destination for the iPhone NavigationStack — disambiguates chat vs bead IDs.
struct PhoneNav: Hashable {
    enum Dest { case chat, bead }
    let dest: Dest
    let id: String
}
#endif

struct AppRootView: View {
    @State private var container: AppContainer? = {
        guard let session = SessionConfig.load() else { return nil }
        return try? AppContainer(session: session)
    }()

    @Environment(\.scenePhase) private var scenePhase

    @State private var sidebarMode: SidebarMode = .chats

    // Chats selection
    @State private var selectedConversationId: String?
    @State private var selectedConversation: Conversation?

    // Beads selection
    @State private var selectedBeadId: String?
    @State private var selectedBead: Bead?

    @State private var showingNewConversation = false

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
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                phoneView(container: container)
            } else {
                splitView(container: container)
            }
            #else
            splitView(container: container)
            #endif
        } else {
            OnboardingView { newSession in
                newSession.save()
                container = try? AppContainer(session: newSession)
            }
        }
    }

    // MARK: - Split view (macOS + iPad)

    @ViewBuilder
    private func splitView(container: AppContainer) -> some View {
        NavigationSplitView {
            Group {
                switch sidebarMode {
                case .chats:
                    ConversationListView(
                        selectedId: $selectedConversationId,
                        repo: container.conversationRepo,
                        messageRepo: container.messageRepo,
                        api: container.api,
                        sidebarMode: $sidebarMode,
                        onNewChat: { showingNewConversation = true },
                        onSignOut: {
                            container.syncEngine.stop()
                            SessionConfig.clear()
                            SyncCursor.reset()
                            AppDatabase.destroy()
                            selectedConversationId = nil
                            selectedConversation = nil
                            self.container = nil
                        }
                    )
                case .beads:
                    BeadsListView(
                        selectedId: $selectedBeadId,
                        api: container.api,
                        sidebarMode: $sidebarMode
                    )
                }
            }
        } detail: {
            switch sidebarMode {
            case .chats:
                if let id = selectedConversationId {
                    ChatView(
                        conversationId: id,
                        conversation: selectedConversation,
                        messageRepo: container.messageRepo,
                        api: container.api
                    )
                    .id(id)
                } else {
                    ContentUnavailableView(
                        "No Conversation",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Select a conversation or tap the compose button to start one.")
                    )
                }
            case .beads:
                if let id = selectedBeadId {
                    BeadDetailView(beadId: id, api: container.api) { updated in
                        selectedBead = updated
                    }
                    .id(id)
                } else {
                    ContentUnavailableView(
                        "No Bead Selected",
                        systemImage: "checkmark.circle",
                        description: Text("Select a bead from the list.")
                    )
                }
            }
        }
        .environmentObject(container.syncEngine)
        .sheet(isPresented: $showingNewConversation) {
            NewConversationView(
                api: container.api,
                onCreate: { id in selectedConversationId = id },
                create: { title, modules, memory in
                    await makeConversation(container: container, title: title, modules: modules, memory: memory)
                }
            )
        }
        .task {
            await container.syncEngine.start()
            #if os(macOS)
            if selectedConversationId == nil {
                if let general = try? await container.conversationRepo.firstProtected() {
                    selectedConversationId = general.id
                }
            }
            #endif
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await container.syncEngine.reconnectIfNeeded() }
            }
        }
        .task(id: selectedConversationId) {
            guard let id = selectedConversationId else { selectedConversation = nil; return }
            for await conv in container.conversationRepo.observe(id: id).values {
                selectedConversation = conv
            }
        }
        .preferredColorScheme(preferredScheme)
    }

    // MARK: - Phone view (iPhone compact — NavigationStack, no TabView)

    #if os(iOS)
    @ViewBuilder
    private func phoneView(container: AppContainer) -> some View {
        NavigationStack {
            Group {
                switch sidebarMode {
                case .chats:
                    ConversationListView(
                        selectedId: $selectedConversationId,
                        repo: container.conversationRepo,
                        messageRepo: container.messageRepo,
                        api: container.api,
                        sidebarMode: $sidebarMode,
                        onNewChat: { showingNewConversation = true },
                        onSignOut: {
                            container.syncEngine.stop()
                            SessionConfig.clear()
                            SyncCursor.reset()
                            AppDatabase.destroy()
                            selectedConversationId = nil
                            selectedConversation = nil
                            self.container = nil
                        }
                    )
                case .beads:
                    BeadsListView(
                        selectedId: $selectedBeadId,
                        api: container.api,
                        sidebarMode: $sidebarMode
                    )
                }
            }
            .navigationDestination(for: PhoneNav.self) { nav in
                switch nav.dest {
                case .chat:
                    ChatView(
                        conversationId: nav.id,
                        conversation: nav.id == selectedConversationId ? selectedConversation : nil,
                        messageRepo: container.messageRepo,
                        api: container.api
                    )
                case .bead:
                    BeadDetailView(beadId: nav.id, api: container.api) { updated in
                        selectedBead = updated
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewConversation) {
            NewConversationView(
                api: container.api,
                onCreate: { id in selectedConversationId = id },
                create: { title, modules, memory in
                    await makeConversation(container: container, title: title, modules: modules, memory: memory)
                }
            )
        }
        .environmentObject(container.syncEngine)
        .task { await container.syncEngine.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await container.syncEngine.reconnectIfNeeded() }
            }
        }
        .task(id: selectedConversationId) {
            guard let id = selectedConversationId else { selectedConversation = nil; return }
            for await conv in container.conversationRepo.observe(id: id).values {
                selectedConversation = conv
            }
        }
        .preferredColorScheme(preferredScheme)
    }
    #endif

    // MARK: - Helpers

    private func makeConversation(container: AppContainer, title: String?, modules: [String], memory: String?) async -> String? {
        do {
            let detail = try await container.api.createConversation(title: title)
            let conv = Conversation(
                id: detail.id,
                title: detail.title,
                claudeSessionId: nil,
                createdAt: Date(timeIntervalSince1970: Double(detail.createdAt) / 1000),
                updatedAt: Date(timeIntervalSince1970: Double(detail.updatedAt) / 1000),
                archivedAt: nil,
                isProtected: detail.isProtected ?? false,
                kind: detail.kind,
                modelOverride: detail.modelOverride
            )
            try await container.conversationRepo.save(conv)
            if !modules.isEmpty {
                try? await container.api.setConversationModules(conversationId: detail.id, modules: modules)
            }
            if let memory, !memory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                _ = try? await container.api.addMemory(content: memory.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return detail.id
        } catch {
            return nil
        }
    }
}
