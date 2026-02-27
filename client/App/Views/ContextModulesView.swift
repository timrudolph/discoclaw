import SwiftUI
import ClawClient

struct ContextModulesView: View {
    let api: APIClient
    let conversationId: String

    @Environment(\.dismiss) private var dismiss

    @State private var available: [ContextModule] = []
    @State private var active: Set<String> = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var savedRecently = false
    @State private var isApplying = false
    @State private var appliedRecently = false
    @State private var error: String?
    @State private var showingNewModule = false

    var body: some View {
        VStack(spacing: 0) {

            // ── Header ──────────────────────────────────────────────────────────
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 40))
                    .foregroundStyle(.tint)
                Text("Context Modules")
                    .font(.title2.bold())
                Text("Select modules to inject into every prompt in this conversation.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)

            Divider()

            // ── Content ─────────────────────────────────────────────────────────
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        moduleChips
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            Divider()

            // ── Footer ──────────────────────────────────────────────────────────
            HStack(spacing: 12) {
                // Apply Now
                Button {
                    Task { await applyNow() }
                } label: {
                    if isApplying {
                        ProgressView().scaleEffect(0.8)
                            .frame(width: 24, height: 24)
                    } else if appliedRecently {
                        Label("Applied", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Apply Now", systemImage: "bolt.fill")
                    }
                }
                .buttonStyle(.glass)
                .disabled(isApplying)
                .help("Reset the session so the next message starts fresh with these modules")

                Spacer()

                // Save status
                if isSaving {
                    HStack(spacing: 5) {
                        ProgressView().scaleEffect(0.7)
                        Text("Saving…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if savedRecently {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("Saved").font(.caption).foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }

                Button("Done") { dismiss() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .frame(minWidth: 420, minHeight: 440)
        .sheet(isPresented: $showingNewModule) {
            NewContextModuleView(api: api) { newModule in
                available.append(newModule)
                available.sort { $0.name < $1.name }
                active.insert(newModule.name)
                Task { await save() }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
        .task { await load() }
    }

    // MARK: - Chip grid

    private var moduleChips: some View {
        GlassEffectContainer {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(available) { module in
                    ModuleChipButton(
                        label: module.label,
                        isSelected: active.contains(module.name)
                    ) {
                        if active.contains(module.name) {
                            active.remove(module.name)
                        } else {
                            active.insert(module.name)
                        }
                        Task { await save() }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await deleteModule(module) }
                        } label: {
                            Label("Delete \"\(module.label)\"", systemImage: "trash")
                        }
                    }
                }

                Button { showingNewModule = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.caption2.weight(.bold))
                        Text("Add Custom")
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        do {
            async let availResult = api.listContextModules()
            async let activeResult = api.getConversationModules(conversationId: conversationId)
            let (avail, activeModules) = try await (availResult, activeResult)
            available = avail.modules
            active = Set(activeModules.modules)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func applyNow() async {
        isApplying = true
        appliedRecently = false
        try? await api.resetConversationSession(conversationId: conversationId)
        withAnimation {
            isApplying = false
            appliedRecently = true
        }
        try? await Task.sleep(for: .seconds(2))
        withAnimation { appliedRecently = false }
    }

    private func deleteModule(_ module: ContextModule) async {
        do {
            try await api.deleteContextModule(name: module.name)
            available.removeAll { $0.name == module.name }
            active.remove(module.name)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        savedRecently = false
        do {
            try await api.setConversationModules(conversationId: conversationId, modules: Array(active))
            withAnimation {
                isSaving = false
                savedRecently = true
            }
            try? await Task.sleep(for: .seconds(2))
            withAnimation { savedRecently = false }
        } catch {
            isSaving = false
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Chip button

private struct ModuleChipButton: View {
    let label: String
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                }
                Text(label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .glassEffect(
            isSelected ? .regular.tint(.accentColor) : .regular,
            in: .capsule
        )
    }
}

// MARK: - New Module Sheet

private struct NewContextModuleView: View {
    let api: APIClient
    let onCreate: (ContextModule) -> Void

    @State private var name = ""
    @State private var content = ""
    @State private var isCreating = false
    @State private var error: String?
    @FocusState private var nameFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var safeName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\.md$", with: "", options: .regularExpression)
    }

    private var canCreate: Bool {
        !safeName.isEmpty && !isCreating
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
                Text("New Context Module")
                    .font(.title2.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Filename", systemImage: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 0) {
                            TextField("my-context", text: $name)
                                .font(.body.monospaced())
                                .textFieldStyle(.plain)
                                .focused($nameFocused)
                                .onSubmit { if canCreate { Task { await submit() } } }
                            Text(".md")
                                .font(.body.monospaced())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(12)
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Content
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Content", systemImage: "text.alignleft")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ZStack(alignment: .topLeading) {
                            if content.isEmpty {
                                Text("# My Context\n\nAdd any information you want injected into prompts…")
                                    .font(.body.monospaced())
                                    .foregroundStyle(.tertiary)
                                    .padding(12)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $content)
                                .font(.body.monospaced())
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 140)
                                .padding(8)
                        }
                        .background(.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(20)
            }

            Divider()

            // Actions
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
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
                .disabled(!canCreate)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(minWidth: 400, minHeight: 420)
        .task { nameFocused = true }
    }

    private func submit() async {
        isCreating = true
        error = nil
        do {
            let module = try await api.createContextModule(name: safeName, content: content)
            onCreate(module)
            dismiss()
        } catch {
            self.error = error.localizedDescription
            isCreating = false
        }
    }
}
