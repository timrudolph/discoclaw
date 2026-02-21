import SwiftUI
import ClawClient

/// Edits the per-conversation identity files (SOUL.md / IDENTITY.md / USER.md).
/// Presented as a sheet from the chat toolbar.
struct PersonaEditorView: View {
    let api: APIClient
    let conversationId: String
    /// Pass in the current conversation so fields are pre-populated immediately.
    let conversation: Conversation?

    @Environment(\.dismiss) private var dismiss

    @State private var soul: String = ""
    @State private var identity: String = ""
    @State private var userBio: String = ""

    @State private var isSaving = false
    @State private var savedRecently = false
    @State private var saveError: String?

    var body: some View {
        Form {
            section(
                title: "SOUL.md",
                subtitle: "Who the assistant fundamentally is — personality, values, essence.",
                text: $soul
            )
            section(
                title: "IDENTITY.md",
                subtitle: "Name, vibe, and style for this chat.",
                text: $identity
            )
            section(
                title: "USER.md",
                subtitle: "Context about who you are and what you're working on.",
                text: $userBio
            )
        }
        .formStyle(.grouped)
        .navigationTitle("Chat Identity")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else if savedRecently {
                    Label("Saved", systemImage: "checkmark")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                } else {
                    Button("Save") { Task { await save() } }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .alert("Save Failed", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .onAppear { loadFromConversation() }
    }

    // MARK: - Section builder

    @ViewBuilder
    private func section(title: String, subtitle: String, text: Binding<String>) -> some View {
        Section {
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
        } header: {
            Text(title)
        } footer: {
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func loadFromConversation() {
        soul     = conversation?.soul     ?? ""
        identity = conversation?.identity ?? ""
        userBio  = conversation?.userBio  ?? ""
    }

    private func save() async {
        isSaving = true
        saveError = nil
        do {
            _ = try await api.updatePersona(
                conversationId: conversationId,
                soul:     soul.isEmpty     ? nil : soul,
                identity: identity.isEmpty ? nil : identity,
                userBio:  userBio.isEmpty  ? nil : userBio
            )
            savedRecently = true
            try? await Task.sleep(for: .seconds(1.5))
            savedRecently = false
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
