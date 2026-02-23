import SwiftUI
import ClawClient

// Files shown to the user — AGENTS.md and TOOLS.md are Discord-only and omitted.
private struct WorkspaceFileConfig {
    let name: String
    let icon: String
    let description: String
}

private let WORKSPACE_FILES: [WorkspaceFileConfig] = [
    WorkspaceFileConfig(
        name: "SOUL.md",
        icon: "heart.text.square",
        description: "Global assistant personality. Applies to all chats unless overridden by Chat Identity."
    ),
    WorkspaceFileConfig(
        name: "IDENTITY.md",
        icon: "person.text.rectangle",
        description: "Global assistant name and style. Overridden per-conversation via Chat Identity."
    ),
    WorkspaceFileConfig(
        name: "USER.md",
        icon: "person.circle",
        description: "Global context about you — who you are, what you work on. Overridden per-conversation."
    ),
    WorkspaceFileConfig(
        name: "MEMORY.md",
        icon: "note.text",
        description: "Free-form scratchpad injected into every conversation. Good for longer notes and project context."
    ),
]

struct WorkspaceFilesView: View {
    let api: APIClient

    @Environment(\.dismiss) private var dismiss

    @State private var files: [WorkspaceFilesResponse.WorkspaceFileInfo] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var editingFile: WorkspaceFilesResponse.WorkspaceFileInfo?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView(
                        "Couldn't Load Files",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    List(WORKSPACE_FILES, id: \.name) { config in
                        let info = files.first(where: { $0.name == config.name })
                        Button {
                            if let info {
                                editingFile = info
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: config.icon)
                                    .font(.title3)
                                    .foregroundStyle(info?.exists == true ? Color.accentColor : Color.secondary)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(config.name)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text(config.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let info, info.exists, !info.preview.isEmpty {
                                        Text(info.preview)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                            .padding(.top, 1)
                                    }
                                }

                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(info == nil)
                    }
                }
            }
            .navigationTitle("Workspace Files")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editingFile) { file in
                WorkspaceFileEditorView(api: api, file: file) {
                    Task { await load() }
                }
            }
            .task { await load() }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 380)
        #endif
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            let response = try await api.listWorkspaceFiles()
            files = response.files
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Editor

struct WorkspaceFileEditorView: View {
    let api: APIClient
    let file: WorkspaceFilesResponse.WorkspaceFileInfo
    let onSaved: () -> Void

    @State private var content = ""
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var error: String?
    @State private var isDirty = false
    @State private var showDiscardAlert = false

    @Environment(\.dismiss) private var dismiss

    private var fileDescription: String {
        WORKSPACE_FILES.first(where: { $0.name == file.name })?.description ?? ""
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        if !fileDescription.isEmpty {
                            Text(fileDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(.bar)
                            Divider()
                        }
                        TextEditor(text: $content)
                            .font(.system(.body, design: .monospaced))
                            .onChange(of: content) { isDirty = true }
                    }
                }
            }
            .navigationTitle(file.name)
            .interactiveDismissDisabled(isDirty)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isDirty { showDiscardAlert = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Text("Save")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isDirty || isSaving)
                }
            }
            .alert("Discard Changes?", isPresented: $showDiscardAlert) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("Your unsaved changes to \(file.name) will be lost.")
            }
            .alert("Error", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                Text(error ?? "")
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 400)
            #endif
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        do {
            let response = try await api.getWorkspaceFile(name: file.name)
            content = response.content
            isDirty = false
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func save() async {
        isSaving = true
        do {
            try await api.updateWorkspaceFile(name: file.name, content: content)
            isDirty = false
            onSaved()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        isSaving = false
    }
}
