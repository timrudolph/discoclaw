import SwiftUI
import ClawClient

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @EnvironmentObject private var syncEngine: SyncEngine

    let conversation: Conversation?
    private let conversationId: String
    private let api: APIClient

    @State private var draftText = ""
    @State private var atBottom = true
    @State private var showingContextModules = false
    @State private var showingPersonaEditor = false

    init(conversationId: String, conversation: Conversation?, messageRepo: MessageRepository, api: APIClient) {
        self.conversationId = conversationId
        self.conversation = conversation
        self.api = api
        _viewModel = StateObject(
            wrappedValue: ChatViewModel(conversationId: conversationId, repo: messageRepo, api: api)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            ComposeBarView(
                text: $draftText,
                isSending: viewModel.isSending,
                onSend: send
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: exportText, subject: Text(conversation?.title ?? "Chat")) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.messages.isEmpty)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingContextModules = true
                } label: {
                    Label("Context Modules", systemImage: "doc.text.magnifyingglass")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showingPersonaEditor = true
                } label: {
                    Label("Chat Identity", systemImage: "person.text.rectangle")
                }
            }
        }
        .sheet(isPresented: $showingContextModules) {
            NavigationStack {
                ContextModulesView(api: api, conversationId: conversationId)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingContextModules = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingPersonaEditor) {
            NavigationStack {
                PersonaEditorView(api: api, conversationId: conversationId, conversation: conversation)
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

                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(
                                message: message,
                                toolLabel: syncEngine.activeTools[message.id]
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

// MARK: - Preference key

private struct AtBottomKey: PreferenceKey {
    static let defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value && nextValue()
    }
}
