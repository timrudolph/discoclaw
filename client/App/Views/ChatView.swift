import SwiftUI
import ClawClient

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @EnvironmentObject private var syncEngine: SyncEngine

    let conversation: Conversation?
    private let conversationId: String
    private let api: APIClient

    @State private var draftText: String
    @State private var atBottom = true
    @State private var showingContextModules = false
    @State private var showingPersonaEditor = false

    private var draftKey: String { "draft.\(conversationId)" }

    init(conversationId: String, conversation: Conversation?, messageRepo: MessageRepository, api: APIClient) {
        self.conversationId = conversationId
        self.conversation = conversation
        self.api = api
        _viewModel = StateObject(
            wrappedValue: ChatViewModel(conversationId: conversationId, repo: messageRepo, api: api)
        )
        // Restore persisted draft (empty string if none).
        _draftText = State(initialValue: UserDefaults.standard.string(forKey: "draft.\(conversationId)") ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            ComposeBarView(
                text: $draftText,
                isSending: viewModel.isSending,
                isStreaming: viewModel.isStreaming,
                onSend: send,
                onStop: { Task { await viewModel.cancel() } }
            )
        }
        .navigationTitle(conversation?.title ?? "Chat")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: exportText, subject: Text(conversation?.title ?? "Chat")) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.messages.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingContextModules = true
                    } label: {
                        Label("Context Modules", systemImage: "doc.text.magnifyingglass")
                    }
                    Button {
                        showingPersonaEditor = true
                    } label: {
                        Label("Chat Identity", systemImage: "person.text.rectangle")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingContextModules) {
            ContextModulesView(api: api, conversationId: conversationId)
        }
        .sheet(isPresented: $showingPersonaEditor) {
            PersonaEditorView(api: api, conversationId: conversationId, conversation: conversation)
        }
        .onChange(of: draftText) { _, newValue in
            // Persist draft so it survives conversation switches.
            if newValue.isEmpty {
                UserDefaults.standard.removeObject(forKey: draftKey)
            } else {
                UserDefaults.standard.set(newValue, forKey: draftKey)
            }
        }
        .alert("Failed to Send", isPresented: Binding(
            get: { viewModel.sendError != nil },
            set: { if !$0 { viewModel.sendError = nil } }
        )) {
            Button("OK") { viewModel.sendError = nil }
        } message: {
            Text(viewModel.sendError ?? "")
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Export

    private var exportText: String {
        let title = conversation?.title ?? "Chat"
        let dateStr = Date().formatted(date: .long, time: .omitted)
        var lines = ["# \(title)", "Exported \(dateStr)", "", "---", ""]
        for message in viewModel.messages where message.status == .complete {
            let role = message.role == .user ? "You" : "Assistant"
            let time = message.createdAt.formatted(date: .omitted, time: .shortened)
            lines.append("[\(role) — \(time)]")
            lines.append(message.content)
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Message list

    private var messageList: some View {
        GeometryReader { scrollGeo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        // "Load earlier messages" button at the top.
                        if viewModel.hasMore {
                            Button {
                                Task {
                                    if let anchorId = await viewModel.loadMore() {
                                        proxy.scrollTo(anchorId, anchor: .top)
                                    }
                                }
                            } label: {
                                if viewModel.isLoadingMore {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Label("Load earlier messages", systemImage: "arrow.up.circle")
                                        .font(.caption)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                        }

                        ForEach(Array(viewModel.messages.enumerated()), id: \.element.id) { index, message in
                            let prevDate = index > 0 ? viewModel.messages[index - 1].createdAt : nil
                            if prevDate == nil || !Calendar.current.isDate(message.createdAt, inSameDayAs: prevDate!) {
                                DateSeparatorView(date: message.createdAt)
                                    .padding(.horizontal)
                            }
                            MessageBubbleView(
                                message: message,
                                toolLabel: syncEngine.activeTools[message.id],
                                onRetry: (message.role == .user && message.status == .error)
                                    ? { Task { await viewModel.retry(message: message) } }
                                    : nil
                            )
                            .padding(.horizontal)
                            .id(message.id)
                        }
                        // Invisible anchor at the bottom; also used to detect if we're at the bottom.
                        Color.clear
                            .frame(height: 1)
                            .id("__bottom__")
                            .background(
                                GeometryReader { anchorGeo in
                                    let scrollBottom = scrollGeo.frame(in: .global).maxY
                                    let anchorBottom = anchorGeo.frame(in: .global).maxY
                                    Color.clear.preference(
                                        key: AtBottomKey.self,
                                        value: anchorBottom <= scrollBottom + 50
                                    )
                                }
                            )
                    }
                    .padding(.vertical, 12)
                }
                .onPreferenceChange(AtBottomKey.self) { isAtBottom in
                    atBottom = isAtBottom
                }
                .onChange(of: viewModel.messages.count) {
                    let lastIsUser = viewModel.messages.last?.role == .user
                    if atBottom || lastIsUser {
                        scrollToBottom(proxy, animated: true)
                    }
                }
                .onChange(of: viewModel.lastMessageContent) {
                    if atBottom { scrollToBottom(proxy, animated: false) }
                }
                .onAppear {
                    scrollToBottom(proxy, animated: false)
                }
                .overlay(alignment: .bottomTrailing) {
                    if !atBottom {
                        Button {
                            atBottom = true
                            scrollToBottom(proxy, animated: true)
                        } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title2)
                                .padding(8)
                                .background(.thinMaterial, in: Circle())
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                        .padding(.bottom, 8)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: atBottom)
            }
        }
    }

    // MARK: - Actions

    private func send() {
        let text = draftText
        draftText = ""
        Task { await viewModel.send(content: text) }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("__bottom__") }
        } else {
            proxy.scrollTo("__bottom__")
        }
    }
}

// MARK: - Date separator

private struct DateSeparatorView: View {
    let date: Date

    private var label: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preference key

private struct AtBottomKey: PreferenceKey {
    static let defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}
