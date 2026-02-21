import SwiftUI
import ClawClient

struct ConversationListView: View {
    @Binding var selectedId: String?
    let onSignOut: () -> Void
    let onNewChat: () -> Void
    let api: APIClient
    @Binding var sidebarMode: SidebarMode
    let isTabContext: Bool
    @StateObject private var viewModel: ConversationListViewModel
    @EnvironmentObject private var syncEngine: SyncEngine

    @State private var renamingConversation: Conversation?
    @State private var renameTitle = ""
    @State private var searchText = ""
    @State private var messageSearchResults: [MessageSearchResponse.SearchResult] = []
    @State private var isSearchingMessages = false
    @State private var showingDevices = false
    @State private var showingMemory = false
    @State private var showingWorkspace = false
    @State private var showingCrons = false

    @AppStorage("appearance") private var appearance = "auto"

    init(selectedId: Binding<String?>, repo: ConversationRepository, messageRepo: MessageRepository, api: APIClient, sidebarMode: Binding<SidebarMode>, isTabContext: Bool = false, onNewChat: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        _selectedId = selectedId
        self.api = api
        _sidebarMode = sidebarMode
        self.isTabContext = isTabContext
        _viewModel = StateObject(wrappedValue: ConversationListViewModel(repo: repo, messageRepo: messageRepo, api: api))
        self.onNewChat = onNewChat
        self.onSignOut = onSignOut
    }

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return viewModel.conversations }
        return viewModel.conversations.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List(selection: $selectedId) {
            // Conversation title matches
            ForEach(filteredConversations) { conversation in
                if isTabContext {
                    NavigationLink(value: conversation.id) {
                        ConversationRow(
                            conversation: conversation,
                            lastMessage: viewModel.lastMessages[conversation.id]
                        )
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: !conversation.isProtected) {
                        conversationSwipeActions(for: conversation)
                    }
                } else {
                    ConversationRow(
                        conversation: conversation,
                        lastMessage: viewModel.lastMessages[conversation.id]
                    )
                    .tag(conversation.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: !conversation.isProtected) {
                        conversationSwipeActions(for: conversation)
                    }
                }
            }

            // Message content matches — shown when search is active
            if !searchText.isEmpty && !messageSearchResults.isEmpty {
                Section("Messages") {
                    ForEach(messageSearchResults) { result in
                        Button {
                            selectedId = result.conversationId
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(result.conversationTitle)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(result.snippet)
                                    .font(.subheadline)
                                    .lineLimit(2)
                                    .foregroundStyle(.primary)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !searchText.isEmpty && isSearchingMessages {
                Section {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Searching messages…").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first,
               let conv = viewModel.conversations.first(where: { $0.id == id }) {
                contextMenuItems(for: conv)
            }
        }
        .onChange(of: searchText) { _, query in
            Task { await performMessageSearch(query: query) }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, prompt: "Search")
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onNewChat()
                } label: {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .overlay {
            if viewModel.conversations.isEmpty {
                ContentUnavailableView(
                    "No Chats Yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Tap the compose button to start a conversation.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .sheet(isPresented: $showingCrons) {
            NavigationStack {
                CronJobsView(api: api, conversations: viewModel.conversations)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingCrons = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingWorkspace) {
            NavigationStack {
                WorkspaceFilesView(api: api)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingWorkspace = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingMemory) {
            NavigationStack {
                MemoryView(api: api)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingMemory = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingDevices) {
            NavigationStack {
                DeviceManagementView(api: api)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingDevices = false }
                        }
                    }
            }
        }
        .alert("Rename Conversation", isPresented: Binding(
            get: { renamingConversation != nil },
            set: { if !$0 { renamingConversation = nil } }
        )) {
            TextField("Name", text: $renameTitle)
            Button("Rename") {
                if let conv = renamingConversation {
                    Task { await viewModel.rename(conv, title: renameTitle) }
                }
                renamingConversation = nil
            }
            Button("Cancel", role: .cancel) {
                renamingConversation = nil
            }
        }
    }

    // MARK: - Swipe actions

    @ViewBuilder
    private func conversationSwipeActions(for conversation: Conversation) -> some View {
        if !conversation.isProtected {
            if conversation.isArchived {
                Button {
                    Task { await viewModel.unarchive(conversation) }
                } label: {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                }
                .tint(.blue)
            } else {
                Button {
                    Task { await viewModel.archive(conversation) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(.orange)
            }
            Button(role: .destructive) {
                Task { await viewModel.delete(conversation) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Message search

    private func performMessageSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            messageSearchResults = []
            return
        }
        isSearchingMessages = true
        do {
            let response = try await api.searchMessages(query: trimmed)
            messageSearchResults = response.results
        } catch {
            messageSearchResults = []
        }
        isSearchingMessages = false
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            // Connection status strip — slides in when the WebSocket is down.
            if !syncEngine.isConnected {
                Divider()
                HStack(spacing: 5) {
                    if syncEngine.isSyncing {
                        ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                        Text("Connecting…")
                    } else {
                        Image(systemName: "wifi.exclamationmark")
                        Text("Reconnecting…")
                    }
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(.orange.opacity(0.08))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
            HStack(spacing: 4) {
                if !isTabContext {
                    // Chats tab — active
                    Button {} label: {
                        Label("Chats", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.tint.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)

                    // Beads tab — inactive
                    Button { sidebarMode = .beads } label: {
                        Label("Beads", systemImage: "checkmark.circle")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Menu {
                    Toggle(isOn: $viewModel.showArchived) {
                        Label("Show Archived", systemImage: "archivebox")
                    }
                    Divider()
                    Picker("Appearance", selection: $appearance) {
                        Text("Auto").tag("auto")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    Divider()
                    Button { showingMemory = true } label: {
                        Label("Memory", systemImage: "brain")
                    }
                    Button { showingWorkspace = true } label: {
                        Label("Workspace Files", systemImage: "doc.badge.gearshape")
                    }
                    Button { showingCrons = true } label: {
                        Label("Scheduled Prompts", systemImage: "clock.badge.checkmark")
                    }
                    Button { showingDevices = true } label: {
                        Label("Manage Devices", systemImage: "laptopcomputer.and.iphone")
                    }
                    Divider()
                    Button(role: .destructive, action: onSignOut) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .background(.bar)
        .animation(.easeInOut(duration: 0.2), value: syncEngine.isConnected)
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenuItems(for conv: Conversation) -> some View {
        if !conv.isProtected {
            if conv.isArchived {
                Button {
                    Task { await viewModel.unarchive(conv) }
                } label: {
                    Label("Unarchive", systemImage: "tray.and.arrow.up")
                }
            } else {
                Button {
                    renameTitle = conv.title ?? ""
                    renamingConversation = conv
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    Task { await viewModel.archive(conv) }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
            }
            if !viewModel.availableModels.isEmpty {
                Divider()
                Menu("Model") {
                    Button {
                        Task { await viewModel.setModel(conv, modelId: nil) }
                    } label: {
                        if conv.modelOverride == nil {
                            Label("Default", systemImage: "checkmark")
                        } else {
                            Text("Default")
                        }
                    }
                    Divider()
                    ForEach(viewModel.availableModels) { model in
                        Button {
                            Task { await viewModel.setModel(conv, modelId: model.id) }
                        } label: {
                            if conv.modelOverride == model.id {
                                Label(model.label, systemImage: "checkmark")
                            } else {
                                Text(model.label)
                            }
                        }
                    }
                }
            }
            Divider()
            Button(role: .destructive) {
                Task { await viewModel.delete(conv) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Row

private struct ConversationRow: View {
    let conversation: Conversation
    let lastMessage: Message?

    /// First non-empty line of the message, with common markdown symbols stripped.
    private var previewText: String? {
        guard let content = lastMessage?.content, !content.isEmpty else { return nil }
        let firstLine = content
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        // Strip leading markdown: headers (#), bold (**), italic (*/_), inline code (`)
        var s = firstLine
        s = s.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*{1,2}([^*]*)\*{1,2}"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"_([^_]*)_"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"`[^`]*`"#, with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if conversation.isArchived {
                    Image(systemName: "archivebox")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if let icon = conversation.kindIcon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(conversation.title ?? "New Conversation")
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(conversation.isArchived ? .secondary : .primary)
            }
            if let preview = previewText {
                Text(preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 4) {
                Text(conversation.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                if let model = conversation.modelOverride {
                    Text(model)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }
}
