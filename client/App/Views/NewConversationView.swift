import SwiftUI
import ClawClient

struct NewConversationView: View {
    let api: APIClient
    let onCreate: (String) -> Void
    let create: (_ title: String?, _ modules: [String], _ memory: String?) async -> String?

    // ── Name ──────────────────────────────────────────────────────────────────
    @State private var title = ""

    // ── Context modules ───────────────────────────────────────────────────────
    @State private var availableModules: [ContextModule] = []
    @State private var selectedModules: Set<String> = []
    @State private var isLoadingModules = true

    // ── Model ─────────────────────────────────────────────────────────────────
    @State private var availableModels: [ConversationModel] = []
    @State private var defaultModelId: String = ""
    @State private var selectedModelId: String? = nil   // nil = server default
    @State private var isLoadingModels = true

    // ── Chat identity ─────────────────────────────────────────────────────────
    @State private var soul = ""
    @State private var identity = ""
    @State private var userBio = ""

    // ── Memory ────────────────────────────────────────────────────────────────
    @State private var memoryNote = ""

    // ── State ─────────────────────────────────────────────────────────────────
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
                VStack(alignment: .leading, spacing: 24) {

                    // Name
                    fieldSection(icon: "pencil", title: "Name") {
                        TextField("What's this conversation about?", text: $title, axis: .vertical)
                            .font(.body)
                            .textFieldStyle(.plain)
                            .focused($titleFocused)
                            .padding(12)
                            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .onSubmit { Task { await submit() } }
                    }

                    // Context modules
                    fieldSection(icon: "doc.text.magnifyingglass", title: "Context Modules",
                                 subtitle: "Injected into every prompt in this conversation.") {
                        if isLoadingModules {
                            loadingRow("Loading modules…")
                        } else if availableModules.isEmpty {
                            Text("No context modules on the server.")
                                .font(.caption).foregroundStyle(.tertiary)
                        } else {
                            chipGrid {
                                ForEach(availableModules) { module in
                                    Chip(label: module.label,
                                         isSelected: selectedModules.contains(module.name)) {
                                        selectedModules.formSymmetricDifference([module.name])
                                    }
                                }
                            }
                        }
                    }

                    // Model
                    DisclosureSection(icon: "cpu", title: "Model") {
                        if isLoadingModels {
                            loadingRow("Loading models…")
                        } else if availableModels.isEmpty {
                            Text("No models available.")
                                .font(.caption).foregroundStyle(.tertiary)
                        } else {
                            chipGrid {
                                // Default chip
                                Chip(
                                    label: "Default" + (defaultModelId.isEmpty ? "" : " (\(defaultModelId))"),
                                    isSelected: selectedModelId == nil
                                ) { selectedModelId = nil }

                                ForEach(availableModels) { model in
                                    Chip(label: model.label,
                                         isSelected: selectedModelId == model.id) {
                                        selectedModelId = model.id
                                    }
                                }
                            }
                        }
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

                    // Memory
                    DisclosureSection(icon: "brain", title: "Initial Memory",
                                      subtitle: "Saved to this conversation's memory.") {
                        ZStack(alignment: .topLeading) {
                            if memoryNote.isEmpty {
                                Text("e.g. \"This project uses TypeScript and pnpm.\"")
                                    .font(.body).foregroundStyle(.tertiary)
                                    .padding(12).allowsHitTesting(false)
                            }
                            TextEditor(text: $memoryNote)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 72)
                                .padding(8)
                        }
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(20)
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
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(isCreating)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 460, minHeight: 520)
        .task {
            async let modules: () = loadModules()
            async let models: () = loadModels()
            _ = await (modules, models)
            titleFocused = true
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func fieldSection<Content: View>(
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
    private func chipGrid<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 90), spacing: 8, alignment: .leading)],
            alignment: .leading, spacing: 8
        ) { content() }
    }

    @ViewBuilder
    private func loadingRow(_ label: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7)
            Text(label).font(.caption).foregroundStyle(.secondary)
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
            .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Data

    private func loadModules() async {
        isLoadingModules = true
        availableModules = (try? await api.listContextModules())?.modules ?? []
        isLoadingModules = false
    }

    private func loadModels() async {
        isLoadingModels = true
        if let response = try? await api.listModels() {
            availableModels = response.models
            defaultModelId = response.default
        }
        isLoadingModels = false
    }

    private func submit() async {
        isCreating = true
        error = nil
        let trimmedTitle    = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMemory   = memoryNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSoul     = soul.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIdentity = identity.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUserBio  = userBio.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let id = await create(
            trimmedTitle.isEmpty  ? nil : trimmedTitle,
            Array(selectedModules),
            trimmedMemory.isEmpty ? nil : trimmedMemory
        ) else {
            error = "Failed to create conversation."
            isCreating = false
            return
        }

        // Write identity files to the conversation workspace
        let writes: [(String, String)] = [
            ("SOUL.md", trimmedSoul),
            ("IDENTITY.md", trimmedIdentity),
            ("USER.md", trimmedUserBio),
        ].filter { !$0.1.isEmpty }
        for (name, content) in writes {
            _ = try? await api.updateConversationWorkspaceFile(conversationId: id, name: name, content: content)
        }

        // Apply model override if changed from default
        if let modelId = selectedModelId {
            _ = try? await api.updateConversation(id: id, modelOverride: .some(modelId))
        }

        onCreate(id)
        dismiss()
    }
}

// MARK: - Shared subviews

private struct Chip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold))
                }
                Text(label).font(.caption.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct DisclosureSection<Content: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
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

            if let subtitle, !expanded {
                Text(subtitle).font(.caption).foregroundStyle(.tertiary)
            }

            if expanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
