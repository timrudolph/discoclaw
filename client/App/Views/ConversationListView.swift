import SwiftUI
import PhotosUI
import ClawClient

struct ConversationListView: View {
    @Binding var selectedId: String?
    let onSignOut: () -> Void
    let onNewChat: () -> Void
    let api: APIClient
    @Binding var sidebarMode: SidebarMode
    let beadsEnabled: Bool
    @StateObject private var viewModel: ConversationListViewModel
    @EnvironmentObject private var syncEngine: SyncEngine

    @State private var renamingConversation: Conversation?
    @State private var renameTitle = ""
    @State private var searchText = ""
    @State private var isSearchExpanded = false
    @State private var messageSearchResults: [MessageSearchResponse.SearchResult] = []
    @State private var isSearchingMessages = false
    @State private var showingDevices = false
    @State private var showingMemory = false
    @State private var showingWorkspace = false
    @State private var showingCrons = false
    @State private var showingProfile = false

    @AppStorage("appearance") private var appearance = "auto"

    init(selectedId: Binding<String?>, repo: ConversationRepository, messageRepo: MessageRepository, api: APIClient, sidebarMode: Binding<SidebarMode>, beadsEnabled: Bool = true, onNewChat: @escaping () -> Void, onSignOut: @escaping () -> Void) {
        _selectedId = selectedId
        self.api = api
        _sidebarMode = sidebarMode
        self.beadsEnabled = beadsEnabled
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

    private var protectedConversations: [Conversation] {
        filteredConversations.filter { $0.isProtected }
    }

    private var regularConversations: [Conversation] {
        filteredConversations.filter { !$0.isProtected }
    }

    var body: some View {
        List {
            // Protected (built-in) conversations — General, Tasks, Journal, etc.
            if !protectedConversations.isEmpty {
                Section {
                    ForEach(protectedConversations) { conversationRow(for: $0) }
                }
            }

            // User-created conversations
            Section {
                ForEach(regularConversations) { conversationRow(for: $0) }
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
        .onChange(of: searchText) { _, query in
            Task { await performMessageSearch(query: query) }
        }
        #if os(macOS)
        .listStyle(.sidebar)
        #else
        .listStyle(.plain)
        #endif
        #if os(iOS)
        .navigationTitle(UIDevice.current.userInterfaceIdiom == .phone ? "" : "Chats")
        .toolbar(UIDevice.current.userInterfaceIdiom == .phone ? .hidden : .automatic, for: .navigationBar)
        #else
        .navigationTitle("Chats")
        #endif
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        if beadsEnabled {
                            Picker("", selection: $sidebarMode) {
                                Text("Chats").tag(SidebarMode.chats)
                                Text("Beads").tag(SidebarMode.beads)
                            }
                            .pickerStyle(.segmented)
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSearchExpanded.toggle()
                                if !isSearchExpanded { searchText = "" }
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.body)
                                .foregroundStyle(isSearchExpanded ? .primary : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    if isSearchExpanded {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField("Search", text: $searchText)
                                .textFieldStyle(.plain)
                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                        .padding(.horizontal, 14)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    Divider()
                }
                .background(.bar)
                .animation(.easeInOut(duration: 0.2), value: isSearchExpanded)
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
            WorkspaceFilesView(api: api)
        }
        .sheet(isPresented: $showingMemory) {
            MemoryView(api: api)
        }
        .sheet(isPresented: $showingDevices) {
            DeviceManagementView(api: api)
        }
        .sheet(isPresented: $showingProfile) {
            ProfileView(api: api)
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

    // MARK: - Row builder

    @ViewBuilder
    private func conversationRow(for conversation: Conversation) -> some View {
        let isSelected = selectedId == conversation.id
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .phone {
            NavigationLink(value: PhoneNav(dest: .chat, id: conversation.id)) {
                ConversationRow(
                    conversation: conversation,
                    lastMessage: viewModel.lastMessages[conversation.id],
                    api: api,
                    isSelected: isSelected
                )
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: !conversation.isProtected) {
                conversationSwipeActions(for: conversation)
            }
        } else {
            ConversationRow(
                conversation: conversation,
                lastMessage: viewModel.lastMessages[conversation.id],
                api: api,
                isSelected: isSelected
            )
            .contentShape(Rectangle())
            .onTapGesture { selectedId = conversation.id }
            .contextMenu { contextMenuItems(for: conversation) }
            .listRowBackground(selectionBackground(isSelected: isSelected))
            .swipeActions(edge: .trailing, allowsFullSwipe: !conversation.isProtected) {
                conversationSwipeActions(for: conversation)
            }
        }
        #else
        ConversationRow(
            conversation: conversation,
            lastMessage: viewModel.lastMessages[conversation.id],
            api: api,
            isSelected: isSelected
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedId = conversation.id }
        .contextMenu { contextMenuItems(for: conversation) }
        .listRowBackground(selectionBackground(isSelected: isSelected))
        .swipeActions(edge: .trailing, allowsFullSwipe: !conversation.isProtected) {
            conversationSwipeActions(for: conversation)
        }
        #endif
    }

    @ViewBuilder
    private func selectionBackground(isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor)
        } else {
            Color.clear
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
                Button {
                    onNewChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)

                Spacer()

                Button {
                    showingMemory = true
                } label: {
                    Image(systemName: "brain")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Global Memory")

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
                    Button { showingWorkspace = true } label: {
                        Label("Workspace Files", systemImage: "doc.badge.gearshape")
                    }
                    Button { showingCrons = true } label: {
                        Label("Scheduled Prompts", systemImage: "clock.badge.checkmark")
                    }
                    Button { showingDevices = true } label: {
                        Label("Manage Devices", systemImage: "laptopcomputer.and.iphone")
                    }
                    Button { showingProfile = true } label: {
                        Label("My Profile", systemImage: "person.crop.circle")
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
    let api: APIClient
    var isSelected: Bool = false

    @State private var avatarImage: Image? = nil

    // Foreground colors flip to white when the row is selected (accent bg).
    private var titleColor: Color {
        if isSelected { return .white }
        return conversation.isArchived ? .secondary : .primary
    }
    private var previewColor: Color { isSelected ? .white.opacity(0.82) : .secondary }
    private var timeColor: Color    { isSelected ? .white.opacity(0.65) : .secondary.opacity(0.6) }

    var body: some View {
        HStack(spacing: 11) {
            avatarCircle
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(conversation.title ?? "New Conversation")
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(titleColor)
                    Spacer(minLength: 4)
                    Text(formattedDate(conversation.updatedAt))
                        .font(.caption)
                        .foregroundStyle(timeColor)
                        .lineLimit(1)
                        .fixedSize()
                }
                if let preview = previewText {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(previewColor)
                        .lineLimit(1)
                }
            }
        }
        .task(id: conversation.id) {
            // Only fetch for persona conversations — general/tasks/journal use icon fallback.
            guard conversation.assistantName != nil else { return }
            if let data = try? await api.fetchAssistantAvatar(conversationId: conversation.id),
               let img = imageFromData(data) {
                avatarImage = img
            }
        }
        #if os(macOS)
        .padding(.vertical, 3)
        #else
        .padding(.vertical, 4)
        #endif
    }

    @ViewBuilder
    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(avatarBackground)
                .frame(width: 42, height: 42)
            if let img = avatarImage {
                img
                    .resizable()
                    .scaledToFill()
                    .frame(width: 42, height: 42)
                    .clipShape(Circle())
            } else if conversation.isArchived {
                Image(systemName: "archivebox")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
            } else if let icon = conversation.kindIcon, conversation.assistantName == nil {
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.white)
            } else {
                Text(monogram)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 42, height: 42)
        .opacity(conversation.isArchived ? 0.55 : 1)
    }

    private var monogram: String {
        let name = conversation.assistantName ?? conversation.title ?? "?"
        return String(name.prefix(1)).uppercased()
    }

    private var avatarBackground: Color {
        if conversation.isArchived { return .secondary.opacity(0.6) }
        if let accent = conversation.accentSwiftUIColor { return accent }
        // Deterministic hue from the name so the same conversation always gets the same color.
        let seed = conversation.assistantName ?? conversation.title ?? conversation.id
        let hue = Double(abs(seed.hashValue) % 360) / 360.0
        return Color(hue: hue, saturation: 0.45, brightness: 0.62)
    }

    /// Apple Messages–style date: time today, "Yesterday", weekday this week, "Feb 20" this year, "1/15/24" older.
    private func formattedDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let daysAgo = cal.dateComponents([.day], from: date, to: .now).day, daysAgo < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        if cal.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.defaultDigits).day().year(.twoDigits))
    }

    /// First non-empty line of the last message with markdown syntax stripped.
    private var previewText: String? {
        guard let content = lastMessage?.content, !content.isEmpty else { return nil }
        let firstLine = content
            .components(separatedBy: "\n")
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        var s = firstLine
        s = s.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*{1,2}([^*]*)\*{1,2}"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"_([^_]*)_"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"`[^`]*`"#, with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    private func imageFromData(_ data: Data) -> Image? {
        #if os(iOS)
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #else
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #endif
    }
}

// MARK: - Profile View

/// Global user profile editor (name + avatar).
/// Opened from the settings menu in the conversation list bottom bar.
private struct ProfileView: View {
    let api: APIClient

    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String = ""
    @State private var userImage: Image? = nil
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var isSaving = false
    @State private var savedRecently = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            avatarPreview
                        }
                        .buttonStyle(.plain)

                        TextField("Your name", text: $displayName)
                    }
                    .padding(.vertical, 4)
                    if isUploadingPhoto {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Uploading photo…")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption).foregroundStyle(.red)
                    }
                } header: {
                    Text("My Profile")
                } footer: {
                    Text("Your name and photo appear in your chat messages.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("My Profile")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else if savedRecently {
                        Label("Saved", systemImage: "checkmark")
                            .foregroundStyle(.green).font(.subheadline)
                    } else {
                        Button("Save") { Task { await save() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .onChange(of: selectedPhotoItem) { _, item in
                Task { await uploadPhoto(item) }
            }
            .task { await loadProfile() }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var avatarPreview: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.25))
                .frame(width: 56, height: 56)
            if let userImage {
                userImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }
        }
        .overlay(Circle().strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1))
    }

    private func loadProfile() async {
        if let me = try? await api.me() {
            displayName = me.user.name ?? ""
        }
        if let data = try? await api.fetchUserAvatar() {
            userImage = imageFromData(data)
        }
    }

    private func uploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isUploadingPhoto = true
        errorMessage = nil
        defer { isUploadingPhoto = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = compressToJPEG(data, maxSize: CGSize(width: 512, height: 512)) else {
            errorMessage = "Could not process image."
            return
        }
        do {
            try await api.uploadUserAvatar(jpeg)
            userImage = imageFromData(jpeg)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        do {
            try await api.updateUserProfile(name: displayName.isEmpty ? nil : displayName)
            savedRecently = true
            try? await Task.sleep(for: .seconds(1.5))
            savedRecently = false
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func imageFromData(_ data: Data) -> Image? {
        #if os(iOS)
        guard let ui = UIImage(data: data) else { return nil }
        return Image(uiImage: ui)
        #else
        guard let ns = NSImage(data: data) else { return nil }
        return Image(nsImage: ns)
        #endif
    }

    private func compressToJPEG(_ data: Data, maxSize: CGSize) -> Data? {
        #if os(iOS)
        guard let src = UIImage(data: data) else { return nil }
        let renderer = UIGraphicsImageRenderer(size: maxSize)
        let resized = renderer.image { _ in
            src.draw(in: CGRect(origin: .zero, size: maxSize))
        }
        return resized.jpegData(compressionQuality: 0.82)
        #else
        guard let src = NSImage(data: data) else { return nil }
        let resized = NSImage(size: maxSize)
        resized.lockFocus()
        src.draw(
            in: NSRect(origin: .zero, size: maxSize),
            from: NSRect(origin: .zero, size: src.size),
            operation: .copy,
            fraction: 1.0
        )
        resized.unlockFocus()
        guard let tiff = resized.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82])
        else { return nil }
        return jpeg
        #endif
    }
}
