import SwiftUI
import ClawClient

struct MemoryView: View {
    let api: APIClient
    /// If set, operates on chat-level memory for this conversation.
    /// If nil, operates on global memory (all conversations).
    var conversationId: String? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var savedText = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String?

    private var isChat: Bool { conversationId != nil }
    private var isDirty: Bool { text != savedText }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        TextEditor(text: $text)
                            .font(.system(.body, design: .monospaced))
                            .padding(12)

                        if !isChat {
                            Divider()
                            Text("Included in every conversation.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle(isChat ? "Chat Memory" : "Global Memory")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!isDirty || isSaving)
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
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 400)
        #endif
    }

    private func load() async {
        isLoading = true
        do {
            let response = if let convId = conversationId {
                try await api.getConversationWorkspaceFile(conversationId: convId, name: "MEMORY.md")
            } else {
                try await api.getWorkspaceFile(name: "MEMORY.md")
            }
            text = response.content
            savedText = response.content
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        isSaving = true
        do {
            if let convId = conversationId {
                try await api.updateConversationWorkspaceFile(conversationId: convId, name: "MEMORY.md", content: text)
            } else {
                try await api.updateWorkspaceFile(name: "MEMORY.md", content: text)
            }
            savedText = text
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
