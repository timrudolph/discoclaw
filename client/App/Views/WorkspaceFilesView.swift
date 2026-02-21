import SwiftUI
import ClawClient

struct WorkspaceFilesView: View {
    let api: APIClient

    @State private var files: [WorkspaceFilesResponse.WorkspaceFileInfo] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var editingFile: WorkspaceFilesResponse.WorkspaceFileInfo?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(files) { file in
                    Button {
                        editingFile = file
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: fileIcon(file.name))
                                .font(.title3)
                                .foregroundStyle(file.exists ? Color.accentColor : Color.secondary)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(file.exists ? (file.preview.isEmpty ? "(empty)" : file.preview) : "Not created yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Workspace Files")
        .sheet(item: $editingFile) { file in
            NavigationStack {
                WorkspaceFileEditorView(api: api, file: file) {
                    // Refresh after save
                    Task { await load() }
                }
            }
        }
        .task { await load() }
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

    private func fileIcon(_ name: String) -> String {
        switch name {
        case "SOUL.md":     return "heart.text.square"
        case "IDENTITY.md": return "person.text.rectangle"
        case "USER.md":     return "person.circle"
        case "AGENTS.md":   return "cpu"
        case "MEMORY.md":   return "brain"
        case "TOOLS.md":    return "wrench.and.screwdriver"
        default:            return "doc.text"
        }
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

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: content) { isDirty = true }
            }
        }
        .navigationTitle(file.name)
        .interactiveDismissDisabled(isDirty)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    if isDirty {
                        showDiscardAlert = true
                    } else {
                        dismiss()
                    }
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
        .task { await load() }
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
