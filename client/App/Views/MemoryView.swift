import SwiftUI
import ClawClient

struct MemoryView: View {
    let api: APIClient
    /// If set, operates on chat-level memory for this conversation.
    /// If nil, operates on global memory (all conversations).
    var conversationId: String? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var items: [MemoryListResponse.MemoryItem] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var newItemText = ""
    @State private var isAdding = false
    @State private var deleting: String?

    private var isChat: Bool { conversationId != nil }

    var body: some View {
        NavigationStack {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // ── Add section ───────────────────────────────────────
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            TextEditor(text: $newItemText)
                                .font(.body)
                                .frame(minHeight: 64, maxHeight: 120)
                                .scrollContentBackground(.hidden)
                            HStack {
                                Spacer()
                                Button {
                                    Task { await addItem() }
                                } label: {
                                    if isAdding {
                                        ProgressView().scaleEffect(0.8)
                                    } else {
                                        Text("Add")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(newItemText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAdding)
                            }
                        }
                        .padding(.vertical, 4)
                    } header: {
                        Text("New memory")
                    } footer: {
                        if isChat {
                            Text("Facts added here are only included in this chat.")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Facts added here are included in every conversation, across all chats.")
                                .foregroundStyle(.secondary)
                        }
                    }

                    // ── Items section ─────────────────────────────────────
                    Section {
                        if items.isEmpty {
                            ContentUnavailableView(
                                "No Memories Yet",
                                systemImage: "brain",
                                description: Text(isChat
                                    ? "Add facts specific to this chat — context, preferences, or anything the assistant should remember here."
                                    : "Add facts you want the assistant to always know — preferences, context about your work, or anything that should carry across every conversation.")
                            )
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(items) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.content)
                                        .font(.subheadline)
                                        .textSelection(.enabled)
                                    Text(Date(timeIntervalSince1970: Double(item.createdAt) / 1000),
                                         style: .relative)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 2)
                                .overlay {
                                    if deleting == item.id {
                                        HStack {
                                            Spacer()
                                            ProgressView().scaleEffect(0.7)
                                        }
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        Task { await deleteItem(item) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } header: {
                        if !items.isEmpty {
                            Text("\(items.count) item\(items.count == 1 ? "" : "s")")
                        }
                    }
                }
            }
        }
        .navigationTitle(isChat ? "Chat Memory" : "Global Memory")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: {
            Text(error ?? "")
        }
        .task { await load() }
        } // NavigationStack
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private func load() async {
        isLoading = true
        do {
            let response = if let convId = conversationId {
                try await api.listConversationMemory(conversationId: convId)
            } else {
                try await api.listMemory()
            }
            items = response.items
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func addItem() async {
        let text = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isAdding = true
        do {
            if let convId = conversationId {
                _ = try await api.addConversationMemory(conversationId: convId, content: text)
                newItemText = ""
                let response = try await api.listConversationMemory(conversationId: convId)
                items = response.items
            } else {
                _ = try await api.addMemory(content: text)
                newItemText = ""
                let response = try await api.listMemory()
                items = response.items
            }
        } catch {
            self.error = error.localizedDescription
        }
        isAdding = false
    }

    private func deleteItem(_ item: MemoryListResponse.MemoryItem) async {
        deleting = item.id
        do {
            if let convId = conversationId {
                try await api.deleteConversationMemory(conversationId: convId, id: item.id)
            } else {
                try await api.deleteMemory(id: item.id)
            }
            items.removeAll { $0.id == item.id }
        } catch {
            self.error = error.localizedDescription
        }
        deleting = nil
    }
}
