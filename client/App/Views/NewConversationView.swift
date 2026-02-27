import SwiftUI
import ClawClient

struct NewConversationView: View {
    let api: APIClient
    let onCreate: (String) -> Void
    let create: (_ title: String?, _ modules: [String], _ memory: String?, _ modelOverride: String?, _ cwdOverride: String?) async -> String?

    @State private var title = ""
    @State private var workingDirectory = ""

    // ── Chat identity ─────────────────────────────────────────────────────────
    @State private var soul = ""
    @State private var identity = ""
    @State private var userBio = ""

    @State private var isCreating = false
    @State private var error: String?
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ────────────────────────────────────────────────────────
            VStack(spacing: 10) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("New Conversation")
                    .font(.title2.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)

            Divider()

            // ── Body ──────────────────────────────────────────────────────────
            ScrollView {
              GlassEffectContainer {
                VStack(alignment: .leading, spacing: 20) {

                    // Name
                    field(icon: "pencil", title: "Name") {
                        TextField("What's this conversation about?", text: $title, axis: .vertical)
                            .font(.body)
                            .textFieldStyle(.plain)
                            .focused($titleFocused)
                            .padding(12)
                            .glassEffect(.regular, in: .rect(cornerRadius: 10))
                            .onSubmit { Task { await submit() } }
                    }

                    // Working directory
                    field(icon: "folder", title: "Working Directory",
                          subtitle: "The directory Claude will work in. Leave empty to use the default workspace.") {
                        TextField("/path/to/project", text: $workingDirectory)
                            .font(.system(.body, design: .monospaced))
                            .textFieldStyle(.plain)
                            .padding(12)
                            .glassEffect(.regular, in: .rect(cornerRadius: 10))
                            .onSubmit { Task { await submit() } }
                    }

                    // Chat identity
                    DisclosureSection(icon: "person.text.rectangle.fill", title: "Chat Identity") {
                        VStack(alignment: .leading, spacing: 16) {
                            identityEditor(icon: "sparkles", name: "SOUL.md",
                                           placeholder: "Who the assistant is — personality, values, essence.",
                                           text: $soul)
                            identityEditor(icon: "theatermasks.fill", name: "IDENTITY.md",
                                           placeholder: "Name, vibe, and style for this chat.",
                                           text: $identity)
                            identityEditor(icon: "person.circle.fill", name: "USER.md",
                                           placeholder: "Context about who you are and what you're working on.",
                                           text: $userBio)
                        }
                    }
                }
                .padding(20)
              }
            }

            Divider()

            // ── Footer ────────────────────────────────────────────────────────
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if let error {
                    Text(error).font(.caption).foregroundStyle(.red).lineLimit(1)
                }
                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 6) {
                        if isCreating { ProgressView().scaleEffect(0.75) }
                        Text(isCreating ? "Creating…" : "Create")
                    }
                    .frame(minWidth: 80)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 380)
        #endif
        .task { titleFocused = true }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func field<Content: View>(
        icon: String, title: String, subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).foregroundStyle(.tint).font(.caption.weight(.semibold))
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(.tertiary)
            }
            content()
        }
    }

    @ViewBuilder
    private func identityEditor(icon: String, name: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).foregroundStyle(.tint).font(.caption.weight(.semibold))
                Text(name).font(.caption.weight(.semibold)).fontDesign(.monospaced)
            }
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72)
                    .padding(6)
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
    }

    // MARK: - Submit

    private func submit() async {
        isCreating = true
        error = nil
        let trimmedTitle    = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCwd      = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSoul     = soul.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIdentity = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUserBio  = userBio.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let id = await create(
            trimmedTitle.isEmpty ? nil : trimmedTitle,
            [],
            nil,
            nil,
            trimmedCwd.isEmpty ? nil : trimmedCwd
        ) else {
            error = "Failed to create conversation."
            isCreating = false
            return
        }

        // Write any identity files to the conversation workspace
        let writes: [(String, String)] = [
            ("SOUL.md",     trimmedSoul),
            ("IDENTITY.md", trimmedIdentity),
            ("USER.md",     trimmedUserBio),
        ].filter { !$0.1.isEmpty }
        for (name, content) in writes {
            _ = try? await api.updateConversationWorkspaceFile(conversationId: id, name: name, content: content)
        }

        onCreate(id)
        dismiss()
    }
}

// MARK: - Shared subviews

private struct DisclosureSection<Content: View>: View {
    let icon: String
    let title: String
    @ViewBuilder let content: () -> Content
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon).foregroundStyle(.tint).font(.caption.weight(.semibold))
                    Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
