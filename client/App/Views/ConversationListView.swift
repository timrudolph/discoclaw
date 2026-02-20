import SwiftUI
import ClawClient

struct ConversationListView: View {
    @Binding var selectedId: String?
    let onSignOut: () -> Void
    let api: APIClient
    @StateObject private var viewModel: ConversationListViewModel

    @State private var renamingConversation: Conversation?
    @State private var renameTitle = ""
    @State private var searchText = ""
    @State private var showingDevices = false
    @State private var showingMemory = false

    @AppStorage("appearance") private var appearance = "auto"

    init(selectedId: Binding<String?>, repo: ConversationRepository, api: APIClient, onSignOut: @escaping () -> Void) {
        _selectedId = selectedId
        self.api = api
        _viewModel = StateObject(wrappedValue: ConversationListViewModel(repo: repo, api: api))
        self.onSignOut = onSignOut
    }

    private var filteredConversations: [Conversation] {
        guard !searchText.isEmpty else { return viewModel.conversations }
        return viewModel.conversations.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(filteredConversations, selection: $selectedId) { conversation in
                ConversationRow(conversation: conversation)
                    .tag(conversation.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: !conversation.isProtected) {
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
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first,
                   let conv = viewModel.conversations.first(where: { $0.id == id }) {
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
                        Divider()
                        Button(role: .destructive) {
                            Task { await viewModel.delete(conv) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $searchText, prompt: "Search")
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            if let id = await viewModel.newConversation() {
                                selectedId = id
                            }
                        }
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }
            }

            Divider()
            HStack {
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
                    Button {
                        showingMemory = true
                    } label: {
                        Label("Memory", systemImage: "brain")
                    }
                    Button {
                        showingDevices = true
                    } label: {
                        Label("Manage Devices", systemImage: "laptopcomputer.and.iphone")
                    }
                    Divider()
                    Button(role: .destructive, action: onSignOut) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
            }
            .padding(.leading, 6)
            .padding(.vertical, 2)
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
}

// MARK: - Row

private struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
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
            Text(conversation.updatedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
